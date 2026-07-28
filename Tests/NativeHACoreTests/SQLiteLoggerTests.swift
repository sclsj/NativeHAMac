import XCTest
import SQLite3
@testable import NativeHACore

final class SQLiteLoggerTests: XCTestCase {
    func testOversizedDatabaseAndSidecarsAreRemovedBeforeLoggerOpens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nativeha-logger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("NativeHA_Logs.sqlite")
        let journalURL = URL(fileURLWithPath: databaseURL.path + "-journal")
        try Data(repeating: 0x41, count: 1_025).write(to: databaseURL)
        try Data([0x42]).write(to: journalURL)

        let removed = try AppLogger.resetOversizedDatabase(
            at: databaseURL,
            maximumBytes: 1_024
        )

        XCTAssertTrue(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testMessagesAreBoundedBeforeEnteringTheAsyncSQLiteQueue() {
        let message = String(repeating: "a", count: 32) + "sensitive-tail"
        let bounded = AppLogger.boundedMessage(message, maximumCharacters: 16)

        XCTAssertEqual(bounded, String(repeating: "a", count: 16) + "… [truncated]")
        XCTAssertFalse(bounded.contains("sensitive-tail"))
    }

    func testPendingQueueIsBoundedWhileSQLiteIsLocked() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nativeha-logger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("NativeHA_Logs.sqlite")
        let policy = LoggingPolicy(
            network: true,
            rendering: true,
            interaction: true,
            lifecycle: true,
            general: true,
            busyTimeoutMilliseconds: 5_000,
            maximumPendingEntries: 2
        )
        let logger = AppLogger(databaseURL: databaseURL, policy: policy)

        var lockingDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &lockingDatabase), SQLITE_OK)
        defer { sqlite3_close(lockingDatabase) }
        XCTAssertEqual(
            sqlite3_exec(lockingDatabase, "BEGIN EXCLUSIVE;", nil, nil, nil),
            SQLITE_OK
        )

        for index in 0..<100 {
            logger.log(
                timestamp: Double(index),
                severity: "debug",
                category: "network",
                file: "test.swift",
                function: #function,
                line: #line,
                message: "entry-\(index)"
            )
        }

        XCTAssertEqual(logger.pendingEntryCount, 2)
        XCTAssertEqual(sqlite3_exec(lockingDatabase, "COMMIT;", nil, nil, nil), SQLITE_OK)

        let deadline = Date().addingTimeInterval(2)
        while logger.pendingEntryCount != 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(logger.pendingEntryCount, 0)
    }
}
