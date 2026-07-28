import Foundation
import SQLite3

public enum LogCategory: String {
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
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct LoggingPolicy {
    public var network: Bool
    public var rendering: Bool
    public var interaction: Bool
    public var lifecycle: Bool
    public var general: Bool
    public var maximumDatabaseBytes: Int64
    public var maximumMessageCharacters: Int
    public var busyTimeoutMilliseconds: Int32
    public var maximumPendingEntries: Int
    
    public init(
        network: Bool,
        rendering: Bool,
        interaction: Bool,
        lifecycle: Bool,
        general: Bool,
        maximumDatabaseBytes: Int64 = 128 * 1_024 * 1_024,
        maximumMessageCharacters: Int = 4_096,
        busyTimeoutMilliseconds: Int32 = 1_000,
        maximumPendingEntries: Int = 1_024
    ) {
        self.network = network
        self.rendering = rendering
        self.interaction = interaction
        self.lifecycle = lifecycle
        self.general = general
        self.maximumDatabaseBytes = max(maximumDatabaseBytes, 1)
        self.maximumMessageCharacters = max(maximumMessageCharacters, 1)
        self.busyTimeoutMilliseconds = max(busyTimeoutMilliseconds, 0)
        self.maximumPendingEntries = max(maximumPendingEntries, 1)
    }
}

public var activeLoggingPolicy = LoggingPolicy(
    network: true,
    rendering: true,
    interaction: true,
    lifecycle: true,
    general: true
)

public final class AppLogger {
    public static let shared = AppLogger()
    
    private let queue = DispatchQueue(label: "com.nativeha.logger", qos: .utility)
    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?
    private let tableName: String
    private let databaseURL: URL
    private let policy: LoggingPolicy
    private var successfulInsertsSinceSizeCheck = 0
    private var hasReachedSizeLimit = false
    private let admissionLock = NSLock()
    private var pendingEntries = 0
    
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
        
        openDatabase()
    }
    
    private func openDatabase() {
        let fileManager = FileManager.default
        _ = try? Self.resetOversizedDatabase(
            at: databaseURL,
            maximumBytes: policy.maximumDatabaseBytes,
            fileManager: fileManager
        )
        
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            print("Failed to open SQLite database at \(databaseURL.path)")
            return
        }
        sqlite3_busy_timeout(db, policy.busyTimeoutMilliseconds)
        
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
            }
        } else {
            print("Failed to prepare create table statement")
        }
        sqlite3_finalize(createTableStatement)
        
        let insertString = "INSERT INTO \(tableName) (timestamp, severity, category, file, function, line, message) VALUES (?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("Failed to prepare insert statement: \(errmsg)")
        }
    }
    
    deinit {
        if let insertStatement = insertStatement {
            sqlite3_finalize(insertStatement)
        }
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    public func log(timestamp: Double, severity: String, category: String, file: String, function: String, line: Int, message: String) {
        guard admitLogEntry() else {
            return
        }
        let boundedMessage = Self.boundedMessage(
            message,
            maximumCharacters: policy.maximumMessageCharacters
        )
        queue.async { [weak self] in
            guard let self = self else { return }
            defer { self.finishLogEntry() }
            guard !self.hasReachedSizeLimit, let statement = self.insertStatement else {
                return
            }
            
            sqlite3_bind_double(statement, 1, timestamp)
            sqlite3_bind_text(statement, 2, (severity as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (category as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, (file as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (function as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 6, Int32(line))
            sqlite3_bind_text(statement, 7, (boundedMessage as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(self.db)!)
                print("Failed to insert log entry: \(errmsg)")
            } else {
                self.successfulInsertsSinceSizeCheck += 1
            }
            
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
            self.checkSizeLimitIfNeeded()
        }
    }

    private func admitLogEntry() -> Bool {
        admissionLock.lock()
        defer { admissionLock.unlock() }
        guard pendingEntries < policy.maximumPendingEntries else {
            return false
        }
        pendingEntries += 1
        return true
    }

    private func finishLogEntry() {
        admissionLock.lock()
        pendingEntries -= 1
        admissionLock.unlock()
    }

    var pendingEntryCount: Int {
        admissionLock.lock()
        defer { admissionLock.unlock() }
        return pendingEntries
    }

    static func boundedMessage(_ message: String, maximumCharacters: Int) -> String {
        let maximumCharacters = max(maximumCharacters, 1)
        guard message.count > maximumCharacters else {
            return message
        }
        return "\(message.prefix(maximumCharacters))… [truncated]"
    }

    @discardableResult
    static func resetOversizedDatabase(
        at databaseURL: URL,
        maximumBytes: Int64,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: databaseURL.path),
            let size = attributes[.size] as? NSNumber,
            size.int64Value > maximumBytes
        else {
            return false
        }

        for suffix in ["", "-journal", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        return true
    }

    private func checkSizeLimitIfNeeded() {
        guard successfulInsertsSinceSizeCheck >= 256 else {
            return
        }
        successfulInsertsSinceSizeCheck = 0
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return
        }
        hasReachedSizeLimit = size.int64Value >= policy.maximumDatabaseBytes
    }
}

@inlinable
public func AppLog(_ message: @autoclosure () -> String, severity: LogSeverity = .info, category: LogCategory = .general, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
    #if DEBUG
    var isEnabled = false
    switch category {
    case .network: isEnabled = activeLoggingPolicy.network
    case .rendering: isEnabled = activeLoggingPolicy.rendering
    case .interaction: isEnabled = activeLoggingPolicy.interaction
    case .lifecycle: isEnabled = activeLoggingPolicy.lifecycle
    case .general: isEnabled = activeLoggingPolicy.general
    }
    
    guard isEnabled else { return }
    
    let msg = message()
    
    let sev = severity.rawValue
    let cat = category.rawValue
    let f = (String(describing: file) as NSString).lastPathComponent
    let fun = String(describing: function)
    let t = Date().timeIntervalSince1970
    
    AppLogger.shared.log(timestamp: t, severity: sev, category: cat, file: f, function: fun, line: Int(line), message: msg)
    #endif
}
