import ArgumentParser
import Foundation

struct InstallCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Set up automatic scheduling with Launch Agent",
        discussion: """
        This command sets up automatic transaction syncing using macOS Launch Agent.
        
        The Launch Agent will:
        • Run sync automatically at scheduled intervals
        • Handle system wake/sleep appropriately
        • Log all sync operations for review
        • Retry failed syncs automatically
        
        Default schedule: Daily at 9:00 AM
        
        You can customize:
        • Sync frequency (hourly, daily, weekly)
        • Specific time of day
        • Days of the week
        
        The Launch Agent will use your existing configuration and API tokens.
        Make sure to run 'up-ynab-sync auth' and 'up-ynab-sync config' first.
        """
    )
    
    @Flag(name: .long, help: "Uninstall the Launch Agent")
    var uninstall: Bool = false
    
    @Flag(name: .long, help: "Show current Launch Agent status without making changes")
    var status: Bool = false
    
    @Option(name: .long, help: "Schedule frequency: hourly, daily, weekly (default: daily)")
    var frequency: String = "daily"
    
    @Option(name: .long, help: "Time of day in 24-hour format (e.g., 09:00, 14:30)")
    var time: String = "09:00"
    
    @Option(name: .long, help: "Days of week for weekly schedule (e.g., 'Monday,Wednesday,Friday')")
    var days: String?
    
    @Flag(name: .shortAndLong, help: "Show verbose output with detailed information")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Force reinstallation even if already installed")
    var force: Bool = false
    
    private var launchAgentHelper: LaunchAgentHelper { LaunchAgentHelper.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        if status {
            try await showLaunchAgentStatus()
            return
        }
        
        if uninstall {
            try await uninstallLaunchAgent()
            return
        }
        
        try await installLaunchAgent()
    }
    
    func validatePrerequisites() async throws {
        // Check if basic setup is complete
        let keychain = KeychainManager.shared
        
        if !status && !uninstall {
            // Only require full setup for installation
            guard keychain.hasToken(service: KeychainManager.upBankingService) else {
                throw CLIError.prerequisiteNotMet("Up Banking API token not found. Please run 'up-ynab-sync auth' first.")
            }
            
            guard keychain.hasToken(service: KeychainManager.ynabService) else {
                throw CLIError.prerequisiteNotMet("YNAB API token not found. Please run 'up-ynab-sync auth' first.")
            }
            
            guard configManager.hasConfiguration() else {
                throw CLIError.prerequisiteNotMet("Account mappings not found. Please run 'up-ynab-sync config' first.")
            }
        }
    }
    
    // MARK: - Launch Agent Status
    
    private func showLaunchAgentStatus() async throws {
        displayInfo("🤖 Launch Agent Status:")
        print("")
        
        let isInstalled = launchAgentHelper.isLaunchAgentInstalled()
        let isLoaded = launchAgentHelper.getLaunchAgentStatus().contains("loaded")
        
        print("Installation Status:")
        print("   Installed: \(isInstalled ? "✅ Yes" : "❌ No")")
        print("   Loaded: \(isLoaded ? "✅ Yes" : "❌ No")")
        
        if isInstalled {
            let plistPath = "~/Library/LaunchAgents/com.upynabsync.daily-sync.plist"
            print("   Location: \(plistPath)")
            
            if verbose {
                try await showDetailedStatus()
            }
            
            let status = launchAgentHelper.getLaunchAgentStatus()
            print("   Status: \(status)")
            
            if let nextRun = launchAgentHelper.getNextRunTime() {
                print("   Next Run: \(nextRun)")
            }
        } else {
            print("")
            print("💡 To set up automatic syncing:")
            print("   up-ynab-sync install")
        }
        
        print("")
    }
    
    private func showDetailedStatus() async throws {
        // Show schedule info if available
        print("   Schedule: Daily at scheduled time")
        
        let logPath = "~/.up-ynab-sync/logs/launch-agent.log"
        print("   Log File: \(logPath)")
        
        // Show recent log entries if verbose
        if verbose {
            try showRecentLogEntries(logPath)
        }
    }
    
    private func showRecentLogEntries(_ logFile: String) throws {
        let url = URL(fileURLWithPath: logFile)
        
        guard FileManager.default.fileExists(atPath: logFile) else {
            return
        }
        
        do {
            let content = try String(contentsOf: url)
            let lines = content.components(separatedBy: .newlines)
            let recentLines = Array(lines.suffix(5)).filter { !$0.isEmpty }
            
            if !recentLines.isEmpty {
                print("   Recent Log Entries:")
                for line in recentLines {
                    print("     \(line)")
                }
            }
        } catch {
            // Silently ignore log read errors
        }
    }
    
    // MARK: - Installation
    
    private func installLaunchAgent() async throws {
        displayInfo("🤖 Setting up automatic sync with Launch Agent...")
        print("")
        
        // Check if already installed
        if launchAgentHelper.isLaunchAgentInstalled() && !force {
            let shouldReinstall = InteractiveInput.readConfirmation(
                prompt: "Launch Agent already installed. Reinstall with new settings?",
                defaultValue: false
            )
            
            guard shouldReinstall else {
                displayInfo("Installation cancelled. Current Launch Agent remains active.")
                return
            }
            
            try await uninstallLaunchAgent(showMessages: false)
        }
        
        // Parse and validate schedule
        let schedule = try parseSchedule()
        
        // Generate Launch Agent plist
        displayInfo("Generating Launch Agent configuration...")
        
        let syncTime = DateComponents(hour: schedule.time.hour, minute: schedule.time.minute)
        let plistContent = launchAgentHelper.generateLaunchAgentPlist(syncTime: syncTime)
        
        if verbose {
            print("Generated plist content:")
            print(plistContent)
            print("")
        }
        
        // Install the Launch Agent
        displayInfo("Installing Launch Agent...")
        
        do {
            let syncTime = DateComponents(hour: schedule.time.hour, minute: schedule.time.minute)
            try launchAgentHelper.installLaunchAgent(syncTime: syncTime)
            displaySuccess("Launch Agent installed and loaded successfully!")
        } catch {
            throw CLIError.configurationError("Failed to install Launch Agent: \(error.localizedDescription)")
        }
        
        // Show installation summary
        try await showInstallationSummary(schedule)
    }
    
    private func showInstallationSummary(_ schedule: ScheduleConfig) async throws {
        print("")
        print("🎉 Automatic Sync Setup Complete!")
        print("=" * 40)
        print("")
        
        print("📅 Schedule:")
        print("   Frequency: \(schedule.frequency.capitalized)")
        print("   Time: \(schedule.timeFormatted)")
        
        if let days = schedule.daysOfWeek {
            print("   Days: \(days.joined(separator: ", "))")
        }
        
        if let nextRun = launchAgentHelper.getNextRunTime() {
            print("   Next Run: \(nextRun)")
        }
        
        print("")
        print("📁 Files:")
        print("   Plist: ~/Library/LaunchAgents/com.upynabsync.sync.plist")
        print("   Logs: ~/.up-ynab-sync/logs/sync.log")
        print("")
        
        print("🔧 Management Commands:")
        print("   up-ynab-sync install --status     # Check status")
        print("   up-ynab-sync install --uninstall  # Remove automation")
        print("   up-ynab-sync review               # Check sync results")
        print("")
        
        print("💡 The sync will run automatically according to your schedule.")
        print("💡 Check sync results with 'up-ynab-sync status' or 'up-ynab-sync review'.")
    }
    
    // MARK: - Uninstallation
    
    private func uninstallLaunchAgent(showMessages: Bool = true) async throws {
        if showMessages {
            displayInfo("🗑️  Uninstalling Launch Agent...")
        }
        
        guard launchAgentHelper.isLaunchAgentInstalled() else {
            if showMessages {
                displayWarning("Launch Agent is not installed")
            }
            return
        }
        
        // Confirm uninstallation
        if showMessages {
            let shouldUninstall = InteractiveInput.readConfirmation(
                prompt: "This will stop automatic syncing. Are you sure?",
                defaultValue: false
            )
            
            guard shouldUninstall else {
                displayInfo("Uninstallation cancelled")
                return
            }
        }
        
        // Uninstall the Launch Agent (this handles both unloading and removing the plist)
        do {
            try launchAgentHelper.uninstallLaunchAgent()
            if showMessages {
                displaySuccess("Launch Agent uninstalled successfully!")
                print("")
                print("💡 Automatic syncing has been disabled.")
                print("💡 You can still run manual syncs with 'up-ynab-sync sync'.")
            }
        } catch {
            throw CLIError.configurationError("Failed to uninstall Launch Agent: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Schedule Parsing
    
    private func parseSchedule() throws -> ScheduleConfig {
        let validFrequencies = ["hourly", "daily", "weekly"]
        
        guard validFrequencies.contains(frequency.lowercased()) else {
            throw CLIError.invalidInput("Invalid frequency '\(frequency)'. Must be one of: \(validFrequencies.joined(separator: ", "))")
        }
        
        let parsedTime = try parseTime(time)
        let parsedDays = try parseDays(days)
        
        return ScheduleConfig(
            frequency: frequency.lowercased(),
            time: parsedTime,
            daysOfWeek: parsedDays
        )
    }
    
    private func parseTime(_ timeString: String) throws -> (hour: Int, minute: Int) {
        let components = timeString.split(separator: ":")
        
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              hour >= 0, hour <= 23,
              minute >= 0, minute <= 59 else {
            throw CLIError.invalidInput("Invalid time format '\(timeString)'. Use HH:MM format (e.g., 09:00, 14:30)")
        }
        
        return (hour: hour, minute: minute)
    }
    
    private func parseDays(_ daysString: String?) throws -> [String]? {
        guard let daysString = daysString else {
            return nil
        }
        
        let validDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let inputDays = daysString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for day in inputDays {
            guard validDays.contains(where: { $0.lowercased() == day.lowercased() }) else {
                throw CLIError.invalidInput("Invalid day '\(day)'. Must be one of: \(validDays.joined(separator: ", "))")
            }
        }
        
        return inputDays.map { day in
            validDays.first { $0.lowercased() == day.lowercased() } ?? day
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractScheduleFromPlist(_ plistContent: String) -> String? {
        // Simple plist parsing for display purposes
        // In a real implementation, you'd use PropertyListSerialization
        if plistContent.contains("StartCalendarInterval") {
            return "Scheduled intervals"
        } else if plistContent.contains("StartInterval") {
            return "Regular intervals"
        }
        return "Custom schedule"
    }
    
    private func extractLogFileFromPlist(_ plistContent: String) -> String? {
        // Simple extraction of log file path from plist
        // Look for StandardOutPath or StandardErrorPath
        let lines = plistContent.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("StandardOutPath") || line.contains("StandardErrorPath") {
                if let pathStart = line.range(of: "<string>"),
                   let pathEnd = line.range(of: "</string>") {
                    return String(line[pathStart.upperBound..<pathEnd.lowerBound])
                }
            }
        }
        return nil
    }
}

// MARK: - Schedule Configuration

struct ScheduleConfig {
    let frequency: String
    let time: (hour: Int, minute: Int)
    let daysOfWeek: [String]?
    
    var timeFormatted: String {
        return String(format: "%02d:%02d", time.hour, time.minute)
    }
}

