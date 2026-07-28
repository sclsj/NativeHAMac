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

public var activeLoggingPolicy = LoggingPolicy(
    minimumSeverity: LogSeverityPolicy(
        webSocket: .debug,
        network: .debug,
        rendering: .debug,
        interaction: .debug,
        lifecycle: .debug,
        general: .debug
    )
)

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
    private let databaseURL: URL
    private let policy: LoggingPolicy
    private var bufferedEntries: [Entry] = []
    private var scheduledFlushToken: UUID?
    private var immediateFlushScheduled = false
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
            print("Failed to open SQLite database at \(databaseURL.path)")
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
                print("Failed to create table")
                sqlite3_finalize(createTableStatement)
                closeDatabase()
                return false
            }
        } else {
            print("Failed to prepare create table statement")
            sqlite3_finalize(createTableStatement)
            closeDatabase()
            return false
        }
        sqlite3_finalize(createTableStatement)
        
        let insertString = "INSERT INTO \(tableName) (timestamp, severity, category, file, function, line, message) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("Failed to prepare insert statement: \(errmsg)")
            closeDatabase()
            return false
        }
        return true
    }
    
    deinit {
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
        if bufferedEntries.count >= policy.flushEntryThreshold {
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
        bufferLock.unlock()
        _ = flushBufferedEntries()
    }

    private func runScheduledFlush(token: UUID) {
        bufferLock.lock()
        guard scheduledFlushToken == token else {
            bufferLock.unlock()
            return
        }
        scheduledFlushToken = nil
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
            sqlite3_bind_double(statement, 1, entry.timestamp)
            sqlite3_bind_text(statement, 2, (entry.severity as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (entry.category as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, (entry.file as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (entry.function as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 6, Int32(entry.line))
            sqlite3_bind_text(statement, 7, (entry.message as NSString).utf8String, -1, SQLITE_TRANSIENT)

            let stepResult = sqlite3_step(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
            guard stepResult == SQLITE_DONE else {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                print("Failed to insert log entry: \(errmsg)")
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

    private func requeueForRetry(_ entries: [Entry]) {
        var retryToken: UUID?
        bufferLock.lock()
        bufferedEntries.insert(contentsOf: entries, at: 0)
        if !immediateFlushScheduled {
            let token = UUID()
            scheduledFlushToken = token
            retryToken = token
        }
        bufferLock.unlock()

        if let retryToken = retryToken {
            queue.asyncAfter(deadline: .now() + policy.retryIntervalSeconds) { [weak self] in
                self?.runScheduledFlush(token: retryToken)
            }
        }
    }

    private func executeSQL(_ sql: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            if result != SQLITE_BUSY, result != SQLITE_LOCKED, let errorMessage = errorMessage {
                print("SQLite logger error: \(String(cString: errorMessage))")
            }
            sqlite3_free(errorMessage)
            return false
        }
        return true
    }
}

public func AppLog(_ message: @autoclosure () -> String, severity: LogSeverity = .info, category: LogCategory = .general, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
    #if DEBUG
    guard activeLoggingPolicy.shouldLog(severity: severity, category: category) else { return }
    
    let msg = message()
    
    let sev = severity.rawValue
    let cat = category.rawValue
    let f = (String(describing: file) as NSString).lastPathComponent
    let fun = String(describing: function)
    let t = Date().timeIntervalSince1970
    
    AppLogger.shared.log(timestamp: t, severity: sev, category: cat, file: f, function: fun, line: Int(line), message: msg)
    #endif
}
