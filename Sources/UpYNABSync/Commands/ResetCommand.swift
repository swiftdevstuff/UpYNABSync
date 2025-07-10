import ArgumentParser
import Foundation

struct ResetCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset all UpYNABSync data and configuration",
        discussion: """
        This command completely resets UpYNABSync to a fresh state.
        
        The following will be removed:
        • All API tokens (Up Banking + YNAB)
        • Account mappings and configuration
        • Transaction sync history and database
        • Automation setup (Launch Agent)
        • All logs and temporary files
        
        This operation cannot be undone. After reset, you'll need to run
        'up-ynab-sync auth' and 'up-ynab-sync config' to set up the tool again.
        """
    )
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts")
    var force: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    private var keychain: KeychainManager { KeychainManager.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    private var launchAgentHelper: LaunchAgentHelper { LaunchAgentHelper.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        if !force {
            try await showResetWarning()
            let confirmed = try await getConfirmation()
            if !confirmed {
                throw CLIError.userCancelled
            }
        }
        
        try await performCompleteReset()
        
        displaySuccess("Reset completed successfully!")
        print("")
        print("UpYNABSync has been reset to factory defaults.")
        print("Ready for fresh setup. Run 'up-ynab-sync auth' to begin.")
    }
    
    func validatePrerequisites() async throws {
        // No prerequisites for reset - we want to reset even if things are broken
    }
    
    // MARK: - Reset Warning and Confirmation
    
    private func showResetWarning() async throws {
        print("")
        print("⚠️  WARNING: This will completely reset UpYNABSync")
        print("")
        print("The following will be removed:")
        print("• All API tokens (Up Banking + YNAB)")
        print("• Account mappings and configuration")
        print("• Transaction sync history")
        print("• Automation setup")
        print("• All logs")
        print("")
        print("This cannot be undone.")
        print("")
        
        if verbose {
            print("Specific items that will be removed:")
            print("• Keychain entries:")
            print("  - Up Banking API token")
            print("  - YNAB API token")
            print("• Directory: ~/.up-ynab-sync/")
            print("  - config.json")
            print("  - sync.db")
            print("  - logs/")
            print("• Launch Agent: ~/Library/LaunchAgents/com.upynabsync.sync.plist")
            print("")
        }
    }
    
    private func getConfirmation() async throws -> Bool {
        print("To confirm complete reset, type 'RESET' (in capitals): ", terminator: "")
        guard let input = readLine() else {
            return false
        }
        
        return input == "RESET"
    }
    
    // MARK: - Complete Reset Implementation
    
    private func performCompleteReset() async throws {
        displayInfo("Performing complete reset...")
        
        var resetResults: [String] = []
        
        // 1. Stop and remove Launch Agent
        do {
            try await resetLaunchAgent()
            resetResults.append("✅ Launch Agent removed")
        } catch {
            resetResults.append("⚠️  Launch Agent removal: \(error.localizedDescription)")
        }
        
        // 2. Clear Keychain tokens
        do {
            try resetKeychainTokens()
            resetResults.append("✅ API tokens cleared from Keychain")
        } catch {
            resetResults.append("⚠️  Keychain clearing: \(error.localizedDescription)")
        }
        
        // 3. Remove entire configuration directory
        do {
            try resetConfigurationDirectory()
            resetResults.append("✅ Configuration directory removed")
        } catch {
            resetResults.append("⚠️  Configuration directory removal: \(error.localizedDescription)")
        }
        
        // Display results
        print("")
        print("Reset Results:")
        for result in resetResults {
            print(result)
        }
        print("")
    }
    
    private func resetLaunchAgent() async throws {
        displayInfo("Removing Launch Agent automation...")
        
        // Check if Launch Agent is installed
        let plistPath = launchAgentHelper.getLaunchAgentPlistPath()
        
        if FileManager.default.fileExists(atPath: plistPath.path) {
            // Unload if running
            try await launchAgentHelper.unload()
            
            // Remove plist file
            try FileManager.default.removeItem(at: plistPath)
            
            if verbose {
                print("  • Unloaded Launch Agent")
                print("  • Removed plist file: \(plistPath.path)")
            }
        } else {
            if verbose {
                print("  • No Launch Agent found to remove")
            }
        }
    }
    
    private func resetKeychainTokens() throws {
        displayInfo("Clearing API tokens from Keychain...")
        
        // Clear Up Banking token
        if keychain.hasToken(service: KeychainManager.upBankingService) {
            try keychain.deleteToken(service: KeychainManager.upBankingService)
            if verbose {
                print("  • Removed Up Banking token")
            }
        }
        
        // Clear YNAB token
        if keychain.hasToken(service: KeychainManager.ynabService) {
            try keychain.deleteToken(service: KeychainManager.ynabService)
            if verbose {
                print("  • Removed YNAB token")
            }
        }
        
        if verbose && !keychain.hasToken(service: KeychainManager.upBankingService) && !keychain.hasToken(service: KeychainManager.ynabService) {
            print("  • No tokens found in Keychain")
        }
    }
    
    private func resetConfigurationDirectory() throws {
        displayInfo("Removing configuration directory...")
        
        let configDir = configManager.getConfigDirectoryPath()
        
        if FileManager.default.fileExists(atPath: configDir.path) {
            try FileManager.default.removeItem(at: configDir)
            if verbose {
                print("  • Removed directory: \(configDir.path)")
            }
        } else {
            if verbose {
                print("  • No configuration directory found")
            }
        }
    }
}