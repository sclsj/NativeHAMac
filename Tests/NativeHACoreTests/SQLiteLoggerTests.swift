import XCTest
import SQLite3
@testable import NativeHACore

final class SQLiteLoggerTests: XCTestCase {
    func testSeverityThresholdsAreIndependentBySubsystem() {
        let policy = LoggingPolicy(
            minimumSeverity: LogSeverityPolicy(
                webSocket: .warning,
                network: .debug,
                rendering: nil,
                interaction: .info,
                lifecycle: .warning,
                general: .error
            )
        )

        XCTAssertFalse(policy.shouldLog(severity: .debug, category: .webSocket))
        XCTAssertFalse(policy.shouldLog(severity: .info, category: .webSocket))
        XCTAssertTrue(policy.shouldLog(severity: .warning, category: .webSocket))
        XCTAssertTrue(policy.shouldLog(severity: .error, category: .webSocket))
        XCTAssertTrue(policy.shouldLog(severity: .debug, category: .network))
        XCTAssertFalse(policy.shouldLog(severity: .error, category: .rendering))
        XCTAssertFalse(policy.shouldLog(severity: .debug, category: .interaction))
        XCTAssertTrue(policy.shouldLog(severity: .info, category: .interaction))
    }

    func testFlushPersistsCompleteMessagesInOneTransaction() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let logger = AppLogger(databaseURL: fixture.databaseURL, policy: fixture.policy)
        let largeMessage = String(repeating: "full-payload-", count: 10_000)
        for index in 0..<100 {
            logger.log(
                timestamp: Double(index),
                severity: "debug",
                category: "webSocket",
                file: "Connection.swift",
                function: "receive",
                line: index,
                message: index == 99 ? largeMessage : "message-\(index)"
            )
        }

        XCTAssertEqual(logger.bufferedEntryCount, 100)
        XCTAssertTrue(logger.flushAndWait())
        XCTAssertEqual(logger.bufferedEntryCount, 0)
        XCTAssertEqual(logger.successfulTransactionCount, 1)

        let rows = try readMessages(
            databaseURL: fixture.databaseURL,
            tableName: logger.tableName
        )
        XCTAssertEqual(rows.count, 100)
        XCTAssertEqual(rows.first, "message-0")
        XCTAssertEqual(rows.last, largeMessage)
    }

    func testLockedDatabaseRetainsEntriesAndRetriesWithoutDropping() throws {
        var fixture = try makeFixture()
        fixture.policy.busyTimeoutMilliseconds = 25
        fixture.policy.retryIntervalSeconds = 60
        let logger = AppLogger(databaseURL: fixture.databaseURL, policy: fixture.policy)
        logger.log(
            timestamp: 0,
            severity: "info",
            category: "general",
            file: "test.swift",
            function: #function,
            line: #line,
            message: "bootstrap"
        )
        XCTAssertTrue(logger.flushAndWait())

        var lockingDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &lockingDatabase), SQLITE_OK)
        defer { sqlite3_close(lockingDatabase) }
        XCTAssertEqual(
            sqlite3_exec(lockingDatabase, "BEGIN IMMEDIATE;", nil, nil, nil),
            SQLITE_OK
        )

        logger.log(
            timestamp: 1,
            severity: "debug",
            category: "webSocket",
            file: "test.swift",
            function: #function,
            line: #line,
            message: "must-survive-lock"
        )
        XCTAssertFalse(logger.flushAndWait())
        XCTAssertEqual(logger.bufferedEntryCount, 1)

        XCTAssertEqual(sqlite3_exec(lockingDatabase, "COMMIT;", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(logger.flushAndWait())
        XCTAssertEqual(logger.bufferedEntryCount, 0)

        let rows = try readMessages(
            databaseURL: fixture.databaseURL,
            tableName: logger.tableName
        )
        XCTAssertEqual(rows, ["bootstrap", "must-survive-lock"])
    }

    func testEntryThresholdFlushesWithoutWaitingForTimer() async throws {
        var fixture = try makeFixture()
        fixture.policy.flushEntryThreshold = 3
        fixture.policy.flushIntervalSeconds = 60
        let logger = AppLogger(databaseURL: fixture.databaseURL, policy: fixture.policy)

        for index in 0..<3 {
            logger.log(
                timestamp: Double(index),
                severity: "debug",
                category: "network",
                file: "test.swift",
                function: #function,
                line: #line,
                message: "threshold-\(index)"
            )
        }

        let deadline = Date().addingTimeInterval(2)
        var rows: [String] = []
        while Date() < deadline {
            rows = (try? readMessages(
                databaseURL: fixture.databaseURL,
                tableName: logger.tableName
            )) ?? []
            if rows.count == 3 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(rows, ["threshold-0", "threshold-1", "threshold-2"])
        XCTAssertEqual(logger.successfulTransactionCount, 1)
    }

    private func makeFixture() throws -> (
        directory: URL,
        databaseURL: URL,
        policy: LoggingPolicy
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nativeha-logger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let policy = LoggingPolicy(
            minimumSeverity: LogSeverityPolicy(
                webSocket: .debug,
                network: .debug,
                rendering: .debug,
                interaction: .debug,
                lifecycle: .debug,
                general: .debug
            ),
            flushIntervalSeconds: 60,
            flushEntryThreshold: 1_000,
            busyTimeoutMilliseconds: 1_000,
            retryIntervalSeconds: 1
        )
        return (
            directory,
            directory.appendingPathComponent("NativeHA_Logs.sqlite"),
            policy
        )
    }

    private func readMessages(databaseURL: URL, tableName: String) throws -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteLoggerTestError.openFailed
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT message FROM \(tableName) ORDER BY id;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw SQLiteLoggerTestError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var messages: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else {
                throw SQLiteLoggerTestError.readFailed
            }
            messages.append(String(cString: text))
        }
        return messages
    }
}

private enum SQLiteLoggerTestError: Error {
    case openFailed
    case prepareFailed
    case readFailed
}
