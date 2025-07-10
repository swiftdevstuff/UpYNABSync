import Foundation

class LaunchAgentHelper: @unchecked Sendable {
    static let shared = LaunchAgentHelper()
    private init() {}
    
    private let logger = Logger.shared
    private let fileManager = FileManager.default
    
    private let launchAgentLabel = "com.upynabsync.daily-sync"
    private var launchAgentPath: URL {
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(launchAgentLabel).plist")
    }
    
    private var launchAgentDirectory: URL {
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }
    
    enum LaunchAgentError: Error, LocalizedError {
        case executableNotFound
        case launchAgentDirectoryNotFound
        case plistCreationFailed
        case installationFailed(String)
        case uninstallationFailed(String)
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Could not find the up-ynab-sync executable"
            case .launchAgentDirectoryNotFound:
                return "LaunchAgents directory not found"
            case .plistCreationFailed:
                return "Failed to create Launch Agent plist file"
            case .installationFailed(let message):
                return "Launch Agent installation failed: \(message)"
            case .uninstallationFailed(let message):
                return "Launch Agent uninstallation failed: \(message)"
            case .permissionDenied:
                return "Permission denied. Please check file permissions."
            }
        }
    }
    
    func generateLaunchAgentPlist(syncTime: DateComponents = DateComponents(hour: 9, minute: 0)) -> String {
        let executablePath = getExecutablePath()
        let logPath = ConfigManager.shared.getLogsDirectory()
            .appendingPathComponent("launch-agent.log").path
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>sync</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(syncTime.hour ?? 9)</integer>
                <key>Minute</key>
                <integer>\(syncTime.minute ?? 0)</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
            <key>RunAtLoad</key>
            <false/>
            <key>LaunchOnlyOnce</key>
            <false/>
        </dict>
        </plist>
        """
    }
    
    private func getExecutablePath() -> String {
        // First try to find the executable in the current process
        if let executablePath = ProcessInfo.processInfo.arguments.first {
            return executablePath
        }
        
        // Fallback to common installation paths
        let commonPaths = [
            "/usr/local/bin/up-ynab-sync",
            "/opt/homebrew/bin/up-ynab-sync",
            "~/bin/up-ynab-sync"
        ]
        
        for path in commonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }
        
        // If all else fails, return a reasonable default
        return "/usr/local/bin/up-ynab-sync"
    }
    
    func installLaunchAgent(syncTime: DateComponents = DateComponents(hour: 9, minute: 0)) throws {
        // Ensure LaunchAgents directory exists
        try ensureLaunchAgentDirectory()
        
        // Generate plist content
        let plistContent = generateLaunchAgentPlist(syncTime: syncTime)
        
        // Write plist file
        do {
            try plistContent.write(to: launchAgentPath, atomically: true, encoding: .utf8)
            logger.info("Launch Agent plist created at: \(launchAgentPath.path)")
        } catch {
            logger.error("Failed to write Launch Agent plist: \(error)")
            throw LaunchAgentError.plistCreationFailed
        }
        
        // Load the Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", launchAgentPath.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Launch Agent installation failed: \(output)")
            throw LaunchAgentError.installationFailed(output)
        }
        
        logger.info("Launch Agent installed successfully")
    }
    
    func uninstallLaunchAgent() throws {
        guard isLaunchAgentInstalled() else {
            logger.info("Launch Agent is not installed")
            return
        }
        
        // Unload the Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", launchAgentPath.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.warning("Launch Agent unload failed: \(output)")
        }
        
        // Remove the plist file
        do {
            try fileManager.removeItem(at: launchAgentPath)
            logger.info("Launch Agent plist removed")
        } catch {
            logger.error("Failed to remove Launch Agent plist: \(error)")
            throw LaunchAgentError.uninstallationFailed(error.localizedDescription)
        }
        
        logger.info("Launch Agent uninstalled successfully")
    }
    
    func isLaunchAgentInstalled() -> Bool {
        return fileManager.fileExists(atPath: launchAgentPath.path)
    }
    
    func getLaunchAgentStatus() -> String {
        guard isLaunchAgentInstalled() else {
            return "❌ Not installed"
        }
        
        // Check if the Launch Agent is loaded
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", launchAgentLabel]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse the output to get more details
            if output.contains("PID") {
                return "✅ Installed and loaded"
            } else {
                return "⚠️ Installed but not loaded"
            }
        } else {
            return "⚠️ Installed but not loaded"
        }
    }
    
    func getNextRunTime() -> String? {
        guard isLaunchAgentInstalled() else {
            return nil
        }
        
        // Try to read the plist file to get the schedule
        do {
            let plistData = try Data(contentsOf: launchAgentPath)
            if let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let calendarInterval = plist["StartCalendarInterval"] as? [String: Any],
               let hour = calendarInterval["Hour"] as? Int,
               let minute = calendarInterval["Minute"] as? Int {
                
                let now = Date()
                let calendar = Calendar.current
                var nextRun = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
                
                // If the scheduled time today has already passed, schedule for tomorrow
                if nextRun <= now {
                    nextRun = calendar.date(byAdding: .day, value: 1, to: nextRun) ?? nextRun
                }
                
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                
                return formatter.string(from: nextRun)
            }
        } catch {
            logger.error("Failed to read Launch Agent plist: \(error)")
        }
        
        return nil
    }
    
    private func ensureLaunchAgentDirectory() throws {
        if !fileManager.fileExists(atPath: launchAgentDirectory.path) {
            do {
                try fileManager.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create LaunchAgents directory: \(error)")
                throw LaunchAgentError.launchAgentDirectoryNotFound
            }
        }
    }
    
    func validateInstallation() -> [String] {
        var issues: [String] = []
        
        // Check if executable exists
        let executablePath = getExecutablePath()
        if !fileManager.fileExists(atPath: executablePath) {
            issues.append("Executable not found at: \(executablePath)")
        }
        
        // Check if plist file exists
        if !isLaunchAgentInstalled() {
            issues.append("Launch Agent plist not found")
        }
        
        // Check if logs directory exists
        let logsDir = ConfigManager.shared.getLogsDirectory()
        if !fileManager.fileExists(atPath: logsDir.path) {
            issues.append("Logs directory not found: \(logsDir.path)")
        }
        
        return issues
    }
    
    // MARK: - Reset Support
    
    func getLaunchAgentPlistPath() -> URL {
        return launchAgentPath
    }
    
    func unload() async throws {
        guard isLaunchAgentInstalled() else {
            return
        }
        
        // Unload the Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", launchAgentPath.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.warning("Launch Agent unload failed: \(output)")
        }
    }
    
    func forceUninstall() async throws {
        // Force unload first
        try await unload()
        
        // Remove the plist file even if unload failed
        if fileManager.fileExists(atPath: launchAgentPath.path) {
            try fileManager.removeItem(at: launchAgentPath)
        }
        
        logger.info("Launch Agent force uninstalled")
    }
}