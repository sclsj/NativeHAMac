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
    
    public init(network: Bool, rendering: Bool, interaction: Bool, lifecycle: Bool, general: Bool) {
        self.network = network
        self.rendering = rendering
        self.interaction = interaction
        self.lifecycle = lifecycle
        self.general = general
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
    
    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: Date())
        
        let gitHash = AppVersion.gitHash
        let gitDirty = AppVersion.gitDirty
        
        // e.g. log_abcdef_clean_20260721_123000
        tableName = "log_\(gitHash)_\(gitDirty)_\(dateString)"
        
        openDatabase()
    }
    
    private func openDatabase() {
        let fileManager = FileManager.default
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        let dbURL = cacheURL.appendingPathComponent("NativeHA_Logs.sqlite")
        
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Failed to open SQLite database at \(dbURL.path)")
            return
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
        queue.async { [weak self] in
            guard let self = self, let statement = self.insertStatement else { return }
            
            sqlite3_bind_double(statement, 1, timestamp)
            sqlite3_bind_text(statement, 2, (severity as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (category as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, (file as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (function as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 6, Int32(line))
            sqlite3_bind_text(statement, 7, (message as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(self.db)!)
                print("Failed to insert log entry: \(errmsg)")
            }
            
            sqlite3_reset(statement)
        }
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
