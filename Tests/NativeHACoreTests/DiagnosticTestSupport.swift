#if DEBUG
import Foundation
import SQLite3
import XCTest
@testable import NativeHACore

// Uses the real AppLog sink so integration tests verify persisted diagnostics,
// in debug builds, rather than merely a mock callback.
func persistedDiagnosticMessages(containing marker: String) throws -> [String] {
    let logger = AppLogger.shared
    XCTAssertTrue(logger.flushAndWait())
    var database: OpaquePointer?
    guard sqlite3_open_v2(logger.databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(database)
        throw DiagnosticReadError.failed
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT message FROM \(logger.tableName) WHERE instr(CAST(message AS BLOB), CAST(? AS BLOB)) > 0 ORDER BY id", -1, &statement, nil) == SQLITE_OK else {
        throw DiagnosticReadError.failed
    }
    defer { sqlite3_finalize(statement) }
    marker.withCString { bytes in
        _ = sqlite3_bind_text(statement, 1, bytes, -1, SQLITE_TRANSIENT)
    }
    var messages: [String] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
        if let bytes = sqlite3_column_text(statement, 0) {
            messages.append(String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, 0))), as: UTF8.self))
        }
        result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else { throw DiagnosticReadError.failed }
    return messages
}

private enum DiagnosticReadError: Error { case failed }

#endif
