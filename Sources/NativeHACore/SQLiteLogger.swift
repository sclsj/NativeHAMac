import Foundation
import SQLite3

public enum LogCategory: String {
    case webSocket
    case network
    case rendering
    case interaction
    case lifecycle
    case general
}

public enum LogSeverity: String {
    case debug
    case info
    case warning
    case error

    fileprivate var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct LogSeverityPolicy {
    public var webSocket: LogSeverity?
    public var network: LogSeverity?
    public var rendering: LogSeverity?
    public var interaction: LogSeverity?
    public var lifecycle: LogSeverity?
    public var general: LogSeverity?

    public init(
        webSocket: LogSeverity?,
        network: LogSeverity?,
        rendering: LogSeverity?,
        interaction: LogSeverity?,
        lifecycle: LogSeverity?,
        general: LogSeverity?
    ) {
        self.webSocket = webSocket
        self.network = network
        self.rendering = rendering
        self.interaction = interaction
        self.lifecycle = lifecycle
        self.general = general
    }

    func minimumSeverity(for category: LogCategory) -> LogSeverity? {
        switch category {
        case .webSocket: return webSocket
        case .network: return network
        case .rendering: return rendering
        case .interaction: return interaction
        case .lifecycle: return lifecycle
        case .general: return general
        }
    }
}

public struct LoggingPolicy {
    public var minimumSeverity: LogSeverityPolicy
    public var flushIntervalSeconds: TimeInterval
    public var flushEntryThreshold: Int
    public var busyTimeoutMilliseconds: Int32
    public var retryIntervalSeconds: TimeInterval

    public init(
        minimumSeverity: LogSeverityPolicy,
        flushIntervalSeconds: TimeInterval = 1,
        flushEntryThreshold: Int = 256,
        busyTimeoutMilliseconds: Int32 = 1_000,
        retryIntervalSeconds: TimeInterval = 1
    ) {
        self.minimumSeverity = minimumSeverity
        self.flushIntervalSeconds = max(flushIntervalSeconds, 0.01)
        self.flushEntryThreshold = max(flushEntryThreshold, 1)
        self.busyTimeoutMilliseconds = max(busyTimeoutMilliseconds, 0)
        self.retryIntervalSeconds = max(retryIntervalSeconds, 0.01)
    }

    public func shouldLog(severity: LogSeverity, category: LogCategory) -> Bool {
        guard let minimum = minimumSeverity.minimumSeverity(for: category) else {
            return false
        }
        return severity.rank >= minimum.rank
    }
}

private var storedLoggingPolicy = LoggingPolicy(
    minimumSeverity: LogSeverityPolicy(
        webSocket: .debug,
        network: .debug,
        rendering: .debug,
        interaction: .debug,
        lifecycle: .debug,
        general: .debug
    )
)

private let loggingPolicyLock = NSLock()

/// Set before starting app work; reads are safe from every logging thread.
public var activeLoggingPolicy: LoggingPolicy {
    get {
        loggingPolicyLock.lock()
        defer { loggingPolicyLock.unlock() }
        return storedLoggingPolicy
    }
    set {
        loggingPolicyLock.lock()
        storedLoggingPolicy = newValue
        loggingPolicyLock.unlock()
    }
}

/// Preserve non-UTF8 diagnostic payloads without silently replacing bytes.
func diagnosticPayload(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? "base64:\(data.base64EncodedString())"
}

func isDiagnosticCancellation(_ error: Error) -> Bool {
    error is CancellationError ||
        (error as? URLError)?.code == .cancelled ||
        (error as? HomeAssistantWebSocketError) == .cancelled
}

public final class AppLogger {
    private struct Entry {
        let timestamp: Double
        let severity: String
        let category: String
        let file: String
        let function: String
        let line: Int
        let message: String
    }

    public static let shared = AppLogger()
    
    private let queue = DispatchQueue(label: "com.nativeha.logger", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let bufferLock = NSLock()
    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?
    let tableName: String
    let databaseURL: URL
    private let policy: LoggingPolicy
    private var bufferedEntries: [Entry] = []
    private var scheduledFlushToken: UUID?
    private var immediateFlushScheduled = false
    private var retryPending = false
    private var completedTransactionCount = 0
    
    private convenience init() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(
            databaseURL: cacheURL.appendingPathComponent("NativeHA_Logs.sqlite"),
            policy: activeLoggingPolicy
        )
    }

    init(databaseURL: URL, policy: LoggingPolicy) {
        self.databaseURL = databaseURL
        self.policy = policy
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: Date())
        
        let gitHash = AppVersion.gitHash
        let gitDirty = AppVersion.gitDirty
        
        // e.g. log_abcdef_clean_20260721_123000
        let launchID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        tableName = "log_\(gitHash)_\(gitDirty)_\(dateString)_\(launchID)"
        queue.setSpecific(key: queueKey, value: 1)
    }
    
    @discardableResult
    private func openDatabaseIfNeeded() -> Bool {
        if db != nil, insertStatement != nil {
            return true
        }
        if db == nil, sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            reportStorageFailure("open")
            closeDatabase()
            return false
        }
        sqlite3_busy_timeout(db, policy.busyTimeoutMilliseconds)
        guard executeSQL("PRAGMA journal_mode=WAL;") else {
            closeDatabase()
            return false
        }
        guard executeSQL("PRAGMA synchronous=FULL;") else {
            closeDatabase()
            return false
        }
        
        let createTableString = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL,
            severity TEXT,
            category TEXT,
            file TEXT,
            function TEXT,
            line INTEGER,
            message TEXT
        );
        """
        
        var createTableStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                // Table created
            } else {
                reportStorageFailure("create table")
                sqlite3_finalize(createTableStatement)
                closeDatabase()
                return false
            }
        } else {
            reportStorageFailure("prepare table")
            sqlite3_finalize(createTableStatement)
            closeDatabase()
            return false
        }
        sqlite3_finalize(createTableStatement)
        
        let insertString = "INSERT INTO \(tableName) (timestamp, severity, category, file, function, line, message) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) != SQLITE_OK {
            reportStorageFailure("prepare insert")
            closeDatabase()
            return false
        }
        return true
    }
    
    deinit {
        // Weak scheduled callbacks must not discard an ordinary final batch.
        // A failed final flush is reported to stderr and cannot survive exit.
        flushAndWait()
        closeDatabase()
    }

    private func closeDatabase() {
        if let insertStatement = insertStatement {
            sqlite3_finalize(insertStatement)
            self.insertStatement = nil
        }
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    public func log(
        timestamp: Double,
        severity: String,
        category: String,
        file: String,
        function: String,
        line: Int,
        message: String
    ) {
        let entry = Entry(
            timestamp: timestamp,
            severity: severity,
            category: category,
            file: file,
            function: function,
            line: line,
            message: message
        )

        var timerToken: UUID?
        var scheduleImmediateFlush = false
        bufferLock.lock()
        bufferedEntries.append(entry)
        if retryPending {
            // New traffic must not bypass the retry interval after a failed write.
        } else if bufferedEntries.count >= policy.flushEntryThreshold {
            scheduledFlushToken = nil
            if !immediateFlushScheduled {
                immediateFlushScheduled = true
                scheduleImmediateFlush = true
            }
        } else if scheduledFlushToken == nil, !immediateFlushScheduled {
            let token = UUID()
            scheduledFlushToken = token
            timerToken = token
        }
        bufferLock.unlock()

        if scheduleImmediateFlush {
            queue.async { [weak self] in
                self?.runImmediateFlush()
            }
        } else if let timerToken = timerToken {
            queue.asyncAfter(deadline: .now() + policy.flushIntervalSeconds) { [weak self] in
                self?.runScheduledFlush(token: timerToken)
            }
        }
    }

    /// Forces all currently accepted entries through one SQLite transaction.
    /// The return value is false when the entries remain buffered for retry.
    @discardableResult
    public func flushAndWait() -> Bool {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return flushBufferedEntries()
        }
        var result = false
        queue.sync {
            result = flushBufferedEntries()
        }
        return result
    }

    var successfulTransactionCount: Int {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return completedTransactionCount
        }
        return queue.sync { completedTransactionCount }
    }

    var bufferedEntryCount: Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return bufferedEntries.count
    }

    private func runImmediateFlush() {
        bufferLock.lock()
        immediateFlushScheduled = false
        let shouldFlush = !retryPending
        bufferLock.unlock()
        if shouldFlush { _ = flushBufferedEntries() }
    }

    private func runScheduledFlush(token: UUID) {
        bufferLock.lock()
        guard scheduledFlushToken == token else {
            bufferLock.unlock()
            return
        }
        scheduledFlushToken = nil
        retryPending = false
        bufferLock.unlock()
        _ = flushBufferedEntries()
    }

    @discardableResult
    private func flushBufferedEntries() -> Bool {
        bufferLock.lock()
        let entries = bufferedEntries
        bufferedEntries.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        guard !entries.isEmpty else {
            return true
        }
        guard openDatabaseIfNeeded(), writeTransaction(entries) else {
            requeueForRetry(entries)
            return false
        }
        return true
    }

    private func writeTransaction(_ entries: [Entry]) -> Bool {
        guard let statement = insertStatement, executeSQL("BEGIN IMMEDIATE TRANSACTION;") else {
            return false
        }

        for entry in entries {
            let bindings = [
                sqlite3_bind_double(statement, 1, entry.timestamp),
                bindText(entry.severity, to: statement, at: 2),
                bindText(entry.category, to: statement, at: 3),
                bindText(entry.file, to: statement, at: 4),
                bindText(entry.function, to: statement, at: 5),
                sqlite3_bind_int64(statement, 6, Int64(entry.line)),
                bindText(entry.message, to: statement, at: 7),
            ]
            if let failure = bindings.first(where: { $0 != SQLITE_OK }) {
                reportStorageFailure("bind entry", code: failure)
                sqlite3_clear_bindings(statement)
                sqlite3_reset(statement)
                _ = executeSQL("ROLLBACK;")
                return false
            }
            guard insertEntry(statement) else {
                _ = executeSQL("ROLLBACK;")
                return false
            }
        }

        guard executeSQL("COMMIT;") else {
            _ = executeSQL("ROLLBACK;")
            return false
        }
        completedTransactionCount += 1
        return true
    }

    private func bindText(_ value: String, to statement: OpaquePointer, at index: Int32) -> Int32 {
        value.withCString { bytes in
            sqlite3_bind_text64(
                statement, index, bytes, UInt64(value.utf8.count), SQLITE_TRANSIENT, UInt8(SQLITE_UTF8)
            )
        }
    }

    private func insertEntry(_ statement: OpaquePointer) -> Bool {
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE { reportStorageFailure("insert entry", code: result) }
        sqlite3_clear_bindings(statement)
        sqlite3_reset(statement)
        return result == SQLITE_DONE
    }

    private func requeueForRetry(_ entries: [Entry]) {
        let token = UUID()
        bufferLock.lock()
        bufferedEntries.insert(contentsOf: entries, at: 0)
        retryPending = true
        scheduledFlushToken = token
        bufferLock.unlock()

        queue.asyncAfter(deadline: .now() + policy.retryIntervalSeconds) { [weak self] in
            self?.runScheduledFlush(token: token)
        }
    }

    // Never send logger failures back through AppLog: that would recursively
    // grow the failed batch. Keep SQLite code, path and session visible on stderr.
    private func reportStorageFailure(_ operation: String, code: Int32? = nil) {
        let result = code ?? sqlite3_errcode(db)
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
        let message = "NativeHA logger \(operation) failed (SQLite \(result)): \(detail); " +
            "database=\(databaseURL.path) session=\(tableName). Entries remain buffered until retry or exit.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func executeSQL(_ sql: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            reportStorageFailure(sql, code: result)
            sqlite3_free(errorMessage)
            return false
        }
        return true
    }
}

public func AppLog(_ message: @autoclosure () -> String, severity: LogSeverity = .info, category: LogCategory = .general, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
    guard activeLoggingPolicy.shouldLog(severity: severity, category: category) else { return }
    
    let msg = message()
    
    let sev = severity.rawValue
    let cat = category.rawValue
    let f = (String(describing: file) as NSString).lastPathComponent
    let fun = String(describing: function)
    let t = Date().timeIntervalSince1970
    
    AppLogger.shared.log(timestamp: t, severity: sev, category: cat, file: f, function: fun, line: Int(line), message: msg)
}
