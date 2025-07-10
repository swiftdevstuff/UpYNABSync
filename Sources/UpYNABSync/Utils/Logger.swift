import Foundation

class Logger: @unchecked Sendable {
    static let shared = Logger()
    private init() {}
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
        
        var color: String {
            switch self {
            case .debug: return "\u{001B}[0;37m"    // Light gray
            case .info: return "\u{001B}[0;36m"     // Cyan
            case .warning: return "\u{001B}[0;33m"  // Yellow
            case .error: return "\u{001B}[0;31m"    // Red
            }
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    private let fileManager = FileManager.default
    private let resetColor = "\u{001B}[0;0m"
    
    private var currentLogFile: URL?
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(timestamp)] \(level.rawValue) [\(fileName):\(line)] \(message)"
        
        // Console output with colors and emojis
        let consoleMessage = "\(level.color)\(level.emoji) \(message)\(resetColor)"
        print(consoleMessage)
        
        // File output
        writeToFile(logMessage)
    }
    
    private func writeToFile(_ message: String) {
        do {
            try ConfigManager.shared.ensureLogsDirectory()
            let logsDir = ConfigManager.shared.getLogsDirectory()
            
            // Create daily log file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let logFile = logsDir.appendingPathComponent("up-ynab-sync-\(dateString).log")
            
            // Rotate logs if needed
            try rotateLogsIfNeeded(in: logsDir)
            
            let fullMessage = message + "\n"
            
            if fileManager.fileExists(atPath: logFile.path) {
                // Append to existing file
                if let data = fullMessage.data(using: .utf8) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                }
            } else {
                // Create new file
                try fullMessage.write(to: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("⚠️ Failed to write to log file: \(error)")
        }
    }
    
    private func rotateLogsIfNeeded(in directory: URL) throws {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let logFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [])
        
        for logFile in logFiles {
            guard logFile.pathExtension == "log" else { continue }
            
            let resourceValues = try logFile.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = resourceValues.creationDate, creationDate < sevenDaysAgo {
                try fileManager.removeItem(at: logFile)
                print("🗑️ Rotated old log file: \(logFile.lastPathComponent)")
            }
        }
    }
    
    // Convenience methods
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}

extension Logger {
    func logSyncStart(dateRange: String) {
        info("🔄 Starting sync for date range: \(dateRange)")
    }
    
    func logSyncComplete(summary: String) {
        info("✅ Sync completed: \(summary)")
    }
    
    func logSyncError(_ error: Error) {
        self.error("❌ Sync failed: \(error.localizedDescription)")
    }
    
    func logAPICall(service: String, endpoint: String, method: String = "GET") {
        debug("🌐 API Call: \(method) \(service) - \(endpoint)")
    }
    
    func logAPIResponse(service: String, statusCode: Int, responseTime: TimeInterval) {
        debug("📡 API Response: \(service) - Status: \(statusCode), Time: \(String(format: "%.2f", responseTime))s")
    }
    
    func logDatabaseOperation(_ operation: String, table: String, count: Int = 1) {
        debug("💾 Database: \(operation) \(count) record(s) in \(table)")
    }
    
    func logAmountConversion(upAmount: Int, ynabAmount: Int) {
        debug("💰 Amount conversion: Up \(upAmount) cents → YNAB \(ynabAmount) milliunits")
    }
}