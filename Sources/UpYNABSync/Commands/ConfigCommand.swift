import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Set up account mappings between Up Banking and YNAB",
        discussion: """
        This command helps you configure which Up Banking accounts sync to which YNAB accounts.
        
        You can map:
        • Your Up Transaction Account to any YNAB account
        • Each Up Saver account to any YNAB account
        
        Smart Categorization Setup:
        • Run 'up-ynab-sync config --categorization' to enable automatic categorization
        • Configure confidence thresholds and auto-apply settings
        • Set up categorization preferences for future syncs
        
        All mappings are saved locally and used for synchronization.
        
        Prerequisites:
        • API tokens must be set up (run 'up-ynab-sync auth' first)
        • Active internet connection for API calls
        """
    )
    
    @Flag(name: .shortAndLong, help: "Reset all existing mappings and start fresh")
    var reset: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show current configuration without making changes")
    var show: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output with account details")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Configure categorization settings")
    var categorization: Bool = false
    
    @Option(name: .long, help: "Specify budget profile to configure (defaults to active profile)")
    var budget: String?
    
    private var upBankingService: UpBankingService { UpBankingService.shared }
    private var ynabService: YNABService { YNABService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        if show {
            try await showCurrentConfiguration()
            return
        }
        
        if categorization {
            try await configureCategorizationSettings()
            return
        }
        
        if reset {
            try await resetConfiguration()
        }
        
        try await performConfiguration()
        
        displaySuccess("Account mappings configured successfully! You can now run 'up-ynab-sync sync' to start syncing.")
    }
    
    // MARK: - Budget Profile Helper
    
    private func getCurrentBudgetProfile() throws -> BudgetProfile {
        if let budgetName = budget {
            return try configManager.getProfile(budgetName)
        } else {
            return try configManager.getActiveProfile()
        }
    }
    
    private func getCurrentBudgetContext() throws -> (profile: BudgetProfile, isSpecified: Bool) {
        if let budgetName = budget {
            let profile = try configManager.getProfile(budgetName)
            return (profile, true)
        } else {
            let profile = try configManager.getActiveProfile()
            return (profile, false)
        }
    }
    
    func validatePrerequisites() async throws {
        // Check API tokens
        let keychain = KeychainManager.shared
        
        guard keychain.hasToken(service: KeychainManager.upBankingService) else {
            throw CLIError.prerequisiteNotMet("Up Banking API token not found. Please run 'up-ynab-sync auth' first.")
        }
        
        guard keychain.hasToken(service: KeychainManager.ynabService) else {
            throw CLIError.prerequisiteNotMet("YNAB API token not found. Please run 'up-ynab-sync auth' first.")
        }
        
        // Test API connections
        displayInfo("Testing API connections...")
        
        do {
            let upConnected = try await upBankingService.testConnection()
            guard upConnected else {
                throw CLIError.prerequisiteNotMet("Unable to connect to Up Banking API. Please check your token.")
            }
            
            let ynabConnected = try await ynabService.testConnection()
            guard ynabConnected else {
                throw CLIError.prerequisiteNotMet("Unable to connect to YNAB API. Please check your token.")
            }
            
            displaySuccess("API connections verified")
        } catch {
            throw CLIError.prerequisiteNotMet("API connection test failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Configuration Display
    
    private func configureCategorizationSettings() async throws {
        do {
            let (profile, isSpecified) = try getCurrentBudgetContext()
            
            if isSpecified {
                displayInfo("⚙️ Configuring Categorization Settings for budget profile: \(profile.id)")
            } else {
                displayInfo("⚙️ Configuring Categorization Settings for active profile: \(profile.id)")
            }
            
            let currentSettings = profile.categorizationSettings ?? BudgetCategorizationSettings.default
        
        print("\n📋 Current Settings:")
        print("Categorization enabled: \(currentSettings.enabled ? "Yes" : "No")")
        print("Auto-apply during sync: \(currentSettings.autoApplyDuringSync ? "Yes" : "No")")
        print("Min confidence threshold: \(Int(currentSettings.minConfidenceThreshold * 100))%")
        print("Suggest new rules: \(currentSettings.suggestNewRules ? "Yes" : "No")")
        
        print("\n🔧 Configuration Options:")
        
        let enabledValue = InteractiveInput.readConfirmation(
            prompt: "Enable automatic categorization?",
            defaultValue: currentSettings.enabled
        )
        
        var autoApplyValue = false
        var confidenceValue = currentSettings.minConfidenceThreshold
        var suggestValue = currentSettings.suggestNewRules
        
        if enabledValue {
            autoApplyValue = InteractiveInput.readConfirmation(
                prompt: "Auto-apply categorization during sync?",
                defaultValue: currentSettings.autoApplyDuringSync
            )
            
            print("Minimum confidence threshold (50-100%): ", terminator: "")
            if let input = InteractiveInput.readLine(prompt: ""),
               let value = Int(input),
               value >= 50 && value <= 100 {
                confidenceValue = Double(value) / 100.0
            } else {
                confidenceValue = currentSettings.minConfidenceThreshold
            }
            
            suggestValue = InteractiveInput.readConfirmation(
                prompt: "Suggest new rules during sync?",
                defaultValue: currentSettings.suggestNewRules
            )
        }
        
            let newSettings = BudgetCategorizationSettings(
                enabled: enabledValue,
                autoApplyDuringSync: autoApplyValue,
                minConfidenceThreshold: confidenceValue,
                suggestNewRules: suggestValue
            )
            
            // Update the profile with new categorization settings
            let updatedProfile = BudgetProfile(
                id: profile.id,
                ynabBudgetId: profile.ynabBudgetId,
                ynabBudgetName: profile.ynabBudgetName,
                accountMappings: profile.accountMappings,
                categorizationSettings: newSettings
            )
            
            try configManager.updateProfile(updatedProfile)
            
            print("\n✅ Categorization settings updated successfully!")
            print("Categorization: \(newSettings.enabled ? "Enabled" : "Disabled")")
            if newSettings.enabled {
                print("Auto-apply: \(newSettings.autoApplyDuringSync ? "Yes" : "No")")
                print("Confidence threshold: \(Int(newSettings.minConfidenceThreshold * 100))%")
                print("Suggest new rules: \(newSettings.suggestNewRules ? "Yes" : "No")")
            }
            
        } catch ConfigError.noActiveProfile {
            displayWarning("No budget profiles configured.")
            displayInfo("💡 Run 'up-ynab-sync budget add <name>' to create your first budget profile")
        } catch {
            displayError(error)
        }
    }
    
    private func showCurrentConfiguration() async throws {
        do {
            let (profile, isSpecified) = try getCurrentBudgetContext()
            
            if isSpecified {
                displayInfo("Configuration for budget profile: \(profile.id)")
            } else {
                displayInfo("Current configuration (active profile: \(profile.id)):")
            }
            
            print("")
            print("🎯 YNAB Budget: \(profile.ynabBudgetName)")
            print("🆔 Budget ID: \(profile.ynabBudgetId)")
            print("")
            print("📊 Account Mappings:")
            
            if profile.accountMappings.isEmpty {
                print("  No account mappings configured")
                print("  💡 Run 'up-ynab-sync config' to set up account mappings")
            } else {
                for (index, mapping) in profile.accountMappings.enumerated() {
                    let typeIcon = mapping.isTransactionAccount ? "💳" : "💰"
                    print("  \(index + 1). \(typeIcon) \(mapping.upAccountName)")
                    print("     → \(mapping.ynabAccountName)")
                    
                    if verbose {
                        print("     Up ID: \(mapping.upAccountId)")
                        print("     YNAB ID: \(mapping.ynabAccountId)")
                    }
                    print("")
                }
            }
            
            // Show categorization settings if available
            print("🎯 Categorization Settings:")
            if let categorizationSettings = profile.categorizationSettings {
                print("  Enabled: \(categorizationSettings.enabled ? "Yes" : "No")")
                if categorizationSettings.enabled {
                    print("  Auto-apply during sync: \(categorizationSettings.autoApplyDuringSync ? "Yes" : "No")")
                    print("  Min confidence threshold: \(Int(categorizationSettings.minConfidenceThreshold * 100))%")
                    print("  Suggest new rules: \(categorizationSettings.suggestNewRules ? "Yes" : "No")")
                }
            } else {
                print("  Not configured")
                print("  💡 Run 'up-ynab-sync config --categorization' to set up categorization")
            }
            
        } catch ConfigError.noActiveProfile {
            displayWarning("No budget profiles configured.")
            displayInfo("💡 Run 'up-ynab-sync budget add <name>' to create your first budget profile")
        } catch {
            throw CLIError.configurationError("Failed to load configuration: \(error.localizedDescription)")
        }
    }
    
    private func resetConfiguration() async throws {
        displayWarning("Resetting all account mappings...")
        
        if configManager.hasConfiguration() {
            let shouldReset = InteractiveInput.readConfirmation(
                prompt: "This will delete all existing account mappings. Are you sure?",
                defaultValue: false
            )
            
            if !shouldReset {
                throw CLIError.userCancelled
            }
            
            try configManager.clearConfiguration()
            displaySuccess("Configuration reset")
        } else {
            displayInfo("No existing configuration to reset")
        }
    }
    
    // MARK: - Main Configuration Flow
    
    private func performConfiguration() async throws {
        do {
            let (currentProfile, isSpecified) = try getCurrentBudgetContext()
            
            if isSpecified {
                displayInfo("🔧 Setting up account mappings for budget profile: \(currentProfile.id)")
            } else {
                displayInfo("🔧 Setting up account mappings for active profile: \(currentProfile.id)")
            }
            print("")
            
            // Use current profile's budget, no need to select again
            let budgetId = currentProfile.ynabBudgetId
            let budgetName = currentProfile.ynabBudgetName
            
            displayInfo("Using YNAB budget: \(budgetName)")
            
            // Step 1: Get YNAB accounts for the profile's budget
            let ynabAccounts = try await getYNABAccounts(budgetId: budgetId)
            
            // Step 2: Get Up Banking accounts
            let upAccounts = try await getUpBankingAccounts()
            
            // Step 3: Create account mappings
            let mappings = try await createAccountMappings(
                upAccounts: upAccounts,
                ynabAccounts: ynabAccounts
            )
            
            // Step 4: Convert legacy mappings to budget mappings
            let budgetMappings = mappings.map { legacyMapping in
                BudgetAccountMapping(
                    upAccountId: legacyMapping.upAccountId,
                    upAccountName: legacyMapping.upAccountName,
                    upAccountType: legacyMapping.upAccountType,
                    ynabAccountId: legacyMapping.ynabAccountId,
                    ynabAccountName: legacyMapping.ynabAccountName
                )
            }
            
            // Step 5: Update the budget profile
            let updatedProfile = BudgetProfile(
                id: currentProfile.id,
                ynabBudgetId: currentProfile.ynabBudgetId,
                ynabBudgetName: currentProfile.ynabBudgetName,
                accountMappings: budgetMappings,
                categorizationSettings: currentProfile.categorizationSettings
            )
            
            try configManager.updateProfile(updatedProfile)
            
            // Step 6: Display summary
            try await displayConfigurationSummary(profile: updatedProfile)
            
        } catch ConfigError.noActiveProfile {
            displayWarning("No budget profiles configured.")
            displayInfo("💡 Run 'up-ynab-sync budget add <name>' to create your first budget profile")
            throw CLIError.configurationError("No active budget profile. Please create a budget profile first.")
        } catch {
            throw error
        }
    }
    
    // MARK: - YNAB Budget Selection
    
    private func selectYNABBudget() async throws -> YNABBudget {
        displayInfo("Fetching YNAB budgets...")
        
        let budgets = try await ynabService.getBudgets()
        
        guard !budgets.isEmpty else {
            throw CLIError.configurationError("No YNAB budgets found. Please create a budget in YNAB first.")
        }
        
        if budgets.count == 1 {
            displayInfo("Using YNAB budget: \(budgets[0].name)")
            return budgets[0]
        }
        
        // Multiple budgets - let user choose
        print("📊 Available YNAB budgets:")
        let budgetNames = budgets.map { $0.name }
        
        guard let selectedIndex = InteractiveInput.readChoiceIndex(
            prompt: "Select your YNAB budget:",
            choices: budgetNames
        ) else {
            throw CLIError.invalidInput("Invalid budget selection")
        }
        
        let selectedBudget = budgets[selectedIndex]
        displaySuccess("Selected budget: \(selectedBudget.name)")
        print("")
        
        return selectedBudget
    }
    
    // MARK: - Account Retrieval
    
    private func getYNABAccounts(budgetId: String) async throws -> [YNABAccount] {
        displayInfo("Fetching YNAB accounts...")
        
        let accounts = try await ynabService.getAccounts(budgetId: budgetId)
        
        // Filter out closed accounts
        let activeAccounts = accounts.filter { !$0.closed }
        
        guard !activeAccounts.isEmpty else {
            throw CLIError.configurationError("No active YNAB accounts found in the selected budget.")
        }
        
        displaySuccess("Found \(activeAccounts.count) active YNAB accounts")
        
        if verbose {
            print("YNAB accounts:")
            for account in activeAccounts {
                let balance = NumberFormatter.currency.string(from: NSNumber(value: Double(account.balance) / 1000.0)) ?? "$0.00"
                print("  • \(account.name) (\(account.type)): \(balance)")
            }
            print("")
        }
        
        return activeAccounts
    }
    
    private func getUpBankingAccounts() async throws -> [UpAccount] {
        displayInfo("Fetching Up Banking accounts...")
        
        let accounts = try await upBankingService.getActiveAccounts()
        
        guard !accounts.isEmpty else {
            throw CLIError.configurationError("No Up Banking accounts found.")
        }
        
        displaySuccess("Found \(accounts.count) Up Banking accounts")
        
        if verbose {
            print("Up Banking accounts:")
            for account in accounts {
                let typeIcon = account.accountType == "TRANSACTIONAL" ? "💳" : "💰"
                print("  • \(typeIcon) \(account.displayName) (\(account.accountType)): \(account.balance.formattedValue)")
            }
            print("")
        }
        
        return accounts
    }
    
    // MARK: - Account Mapping Creation
    
    private func createAccountMappings(
        upAccounts: [UpAccount],
        ynabAccounts: [YNABAccount]
    ) async throws -> [ConfigManager.AccountMapping] {
        
        var mappings: [ConfigManager.AccountMapping] = []
        
        print("🔗 Creating account mappings...")
        print("")
        
        // Display Up Banking accounts
        print("Up Banking accounts:")
        for (index, account) in upAccounts.enumerated() {
            let typeIcon = account.accountType == "TRANSACTIONAL" ? "💳" : "💰"
            print("\(index + 1). \(typeIcon) \(account.displayName) (\(account.balance.formattedValue))")
        }
        print("")
        
        // Display YNAB accounts
        print("Available YNAB accounts:")
        for (index, account) in ynabAccounts.enumerated() {
            let balance = NumberFormatter.currency.string(from: NSNumber(value: Double(account.balance) / 1000.0)) ?? "$0.00"
            print("\(index + 1). \(account.name) (\(balance))")
        }
        print("")
        
        // Create mappings for each Up account
        for upAccount in upAccounts {
            let typeIcon = upAccount.accountType == "TRANSACTIONAL" ? "💳" : "💰"
            
            print("Map \(typeIcon) \(upAccount.displayName) to which YNAB account?")
            
            let ynabAccountNames = ynabAccounts.map { account in
                let balance = NumberFormatter.currency.string(from: NSNumber(value: Double(account.balance) / 1000.0)) ?? "$0.00"
                return "\(account.name) (\(balance))"
            }
            
            guard let selectedIndex = InteractiveInput.readChoiceIndexWithSkip(
                prompt: "Select YNAB account (1-\(ynabAccounts.count)) or skip:",
                choices: ynabAccountNames
            ) else {
                throw CLIError.invalidInput("Invalid account selection")
            }
            
            if selectedIndex == -1 {
                displayInfo("⏭️ Skipped \(upAccount.displayName)")
                print("")
                continue
            }
            
            let selectedYnabAccount = ynabAccounts[selectedIndex]
            
            let mapping = ConfigManager.AccountMapping(
                upAccountId: upAccount.id,
                upAccountName: upAccount.displayName,
                upAccountType: upAccount.accountType,
                ynabAccountId: selectedYnabAccount.id,
                ynabAccountName: selectedYnabAccount.name
            )
            
            mappings.append(mapping)
            
            displaySuccess("✓ \(upAccount.displayName) → \(selectedYnabAccount.name)")
            print("")
        }
        
        return mappings
    }
    
    // MARK: - Configuration Summary
    
    private func displayConfigurationSummary(profile: BudgetProfile) async throws {
        print("📋 Configuration Summary:")
        print("")
        
        print("🎯 YNAB Budget: \(profile.ynabBudgetName)")
        print("📋 Budget Profile: \(profile.id)")
        print("")
        
        print("🔗 Account Mappings:")
        for (index, mapping) in profile.accountMappings.enumerated() {
            let typeIcon = mapping.isTransactionAccount ? "💳" : "💰"
            print("  \(index + 1). \(typeIcon) \(mapping.upAccountName)")
            print("     → \(mapping.ynabAccountName)")
            print("")
        }
        
        print("✅ Configuration saved for budget profile: \(profile.id)")
        print("")
    }
}