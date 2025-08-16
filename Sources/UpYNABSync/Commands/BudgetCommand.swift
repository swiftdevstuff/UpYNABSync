import ArgumentParser
import Foundation

struct BudgetCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "budget",
        abstract: "Manage multiple YNAB budget profiles",
        discussion: """
        Manage multiple YNAB budget profiles for different budgets with isolated configurations.
        
        Each budget profile contains:
        • YNAB budget ID and name
        • Account mappings specific to that budget
        • Categorization settings specific to that budget
        • Isolated sync history and merchant rules
        
        Common operations:
        • List all configured budget profiles
        • Add a new budget profile
        • Switch between budget profiles
        • Remove unused budget profiles
        • Show configuration for any profile
        
        Examples:
        up-ynab-sync budget list
        up-ynab-sync budget add personal
        up-ynab-sync budget switch business
        up-ynab-sync budget show personal
        up-ynab-sync budget remove old-budget
        """,
        subcommands: [
            ListCommand.self,
            AddCommand.self,
            SwitchCommand.self,
            RemoveCommand.self,
            ShowCommand.self
        ]
    )
    
    init() {}
    
    func run() async throws {
        print("Use 'up-ynab-sync budget --help' to see available budget management commands")
    }
}

// MARK: - List Command

extension BudgetCommand {
    struct ListCommand: AsyncParsableCommand, BaseCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all configured budget profiles"
        )
        
        @Flag(name: .shortAndLong, help: "Show detailed information for each profile")
        var verbose: Bool = false
        
        private var configManager: ConfigManager { ConfigManager.shared }
        
        func run() async throws {
            displayInfo("📊 Budget Profiles:")
            
            do {
                let profiles = try configManager.getAllProfiles()
                let activeProfileId = try? configManager.getActiveProfile().id
                
                if profiles.isEmpty {
                    displayWarning("No budget profiles configured.")
                    displayInfo("💡 Run 'up-ynab-sync budget add <name>' to create your first budget profile")
                    return
                }
                
                print("")
                
                for (index, profile) in profiles.enumerated() {
                    let isActive = profile.id == activeProfileId
                    let activeIndicator = isActive ? " (active)" : ""
                    let statusIcon = isActive ? "👉" : "📋"
                    
                    print("\(index + 1). \(statusIcon) \(profile.displayName)\(activeIndicator)")
                    
                    if verbose {
                        print("   ID: \(profile.id)")
                        print("   YNAB Budget: \(profile.ynabBudgetId)")
                        print("   Account Mappings: \(profile.accountMappings.count)")
                        print("   Categorization: \(profile.categorizationSettings?.enabled == true ? "Enabled" : "Disabled")")
                        print("   Created: \(DateFormatter.dateOnly.string(from: profile.createdAt))")
                        print("")
                    }
                }
                
                if !verbose {
                    print("")
                    displayInfo("💡 Use --verbose for detailed information")
                }
                
            } catch {
                displayError(error)
            }
        }
    }
}

// MARK: - Add Command

extension BudgetCommand {
    struct AddCommand: AsyncParsableCommand, BaseCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a new budget profile"
        )
        
        @Argument(help: "Name for the new budget profile")
        var name: String
        
        @Option(name: .long, help: "YNAB budget ID (will prompt to select if not provided)")
        var budgetId: String?
        
        private var configManager: ConfigManager { ConfigManager.shared }
        private var ynabService: YNABService { YNABService.shared }
        
        func run() async throws {
            try await validatePrerequisites()
            
            displayInfo("➕ Adding new budget profile: \(name)")
            
            do {
                // Check if profile already exists
                let existingProfiles = try configManager.getAllProfiles()
                if existingProfiles.contains(where: { $0.id == name }) {
                    throw CLIError.configurationError("Budget profile '\(name)' already exists")
                }
                
                // Get YNAB budget ID
                let selectedBudgetId: String
                let selectedBudgetName: String
                
                if let providedBudgetId = budgetId {
                    selectedBudgetId = providedBudgetId
                    selectedBudgetName = try await ynabService.getBudgetName(budgetId: providedBudgetId)
                } else {
                    (selectedBudgetId, selectedBudgetName) = try await selectYNABBudget()
                }
                
                // Create new budget profile
                let newProfile = BudgetProfile(
                    id: name,
                    ynabBudgetId: selectedBudgetId,
                    ynabBudgetName: selectedBudgetName
                )
                
                // Add profile to configuration
                try configManager.addProfile(newProfile)
                
                displaySuccess("Budget profile '\(name)' added successfully!")
                displayInfo("YNAB Budget: \(selectedBudgetName)")
                displayInfo("💡 Run 'up-ynab-sync budget switch \(name)' to make it active")
                displayInfo("💡 Run 'up-ynab-sync config' to configure account mappings for this budget")
                
            } catch {
                displayError(error)
            }
        }
        
        func validatePrerequisites() async throws {
            let keychain = KeychainManager.shared
            
            guard keychain.hasToken(service: KeychainManager.ynabService) else {
                throw CLIError.prerequisiteNotMet("YNAB API token not found. Please run 'up-ynab-sync auth' first.")
            }
            
            displayInfo("Testing YNAB API connection...")
            let ynabConnected = try await ynabService.testConnection()
            guard ynabConnected else {
                throw CLIError.prerequisiteNotMet("Unable to connect to YNAB API. Please check your token.")
            }
        }
        
        private func selectYNABBudget() async throws -> (String, String) {
            displayInfo("Fetching YNAB budgets...")
            
            let budgets = try await ynabService.getBudgets()
            
            guard !budgets.isEmpty else {
                throw CLIError.configurationError("No YNAB budgets found. Please create a budget in YNAB first.")
            }
            
            if budgets.count == 1 {
                let budget = budgets[0]
                displayInfo("Using YNAB budget: \(budget.name)")
                return (budget.id, budget.name)
            }
            
            // Multiple budgets - let user choose
            print("\n📊 Available YNAB budgets:")
            let budgetNames = budgets.map { $0.name }
            
            guard let selectedIndex = InteractiveInput.readChoiceIndex(
                prompt: "Select your YNAB budget:",
                choices: budgetNames
            ) else {
                throw CLIError.invalidInput("Invalid budget selection")
            }
            
            let selectedBudget = budgets[selectedIndex]
            displaySuccess("Selected budget: \(selectedBudget.name)")
            
            return (selectedBudget.id, selectedBudget.name)
        }
    }
}

// MARK: - Switch Command

extension BudgetCommand {
    struct SwitchCommand: AsyncParsableCommand, BaseCommand {
        static let configuration = CommandConfiguration(
            commandName: "switch",
            abstract: "Switch to a different budget profile"
        )
        
        @Argument(help: "Name of the budget profile to switch to")
        var name: String
        
        private var configManager: ConfigManager { ConfigManager.shared }
        
        func run() async throws {
            displayInfo("🔄 Switching to budget profile: \(name)")
            
            do {
                // Verify profile exists
                let profile = try configManager.getProfile(name)
                
                // Switch to the profile
                try configManager.setActiveProfile(name)
                
                displaySuccess("Switched to budget profile: \(profile.displayName)")
                displayInfo("YNAB Budget: \(profile.ynabBudgetName)")
                displayInfo("Account Mappings: \(profile.accountMappings.count)")
                
            } catch {
                displayError(error)
            }
        }
    }
}

// MARK: - Remove Command

extension BudgetCommand {
    struct RemoveCommand: AsyncParsableCommand, BaseCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a budget profile"
        )
        
        @Argument(help: "Name of the budget profile to remove")
        var name: String
        
        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var force: Bool = false
        
        private var configManager: ConfigManager { ConfigManager.shared }
        
        func run() async throws {
            displayWarning("🗑️ Removing budget profile: \(name)")
            
            do {
                // Verify profile exists
                let profile = try configManager.getProfile(name)
                
                // Check if it's the active profile
                let activeProfile = try? configManager.getActiveProfile()
                if activeProfile?.id == name {
                    displayError(CLIError.configurationError("Cannot remove active budget profile '\(name)'. Switch to another profile first."))
                    return
                }
                
                // Confirm deletion unless forced
                if !force {
                    print("\nProfile Details:")
                    print("• Name: \(profile.displayName)")
                    print("• YNAB Budget: \(profile.ynabBudgetName)")
                    print("• Account Mappings: \(profile.accountMappings.count)")
                    print("• Categorization Rules: Will be removed")
                    print("• Sync History: Will be removed")
                    
                    let confirmed = InteractiveInput.readConfirmation(
                        prompt: "\nThis will permanently delete all data for this budget profile. Are you sure?",
                        defaultValue: false
                    )
                    
                    if !confirmed {
                        displayInfo("Operation cancelled")
                        return
                    }
                }
                
                // Remove the profile
                try configManager.removeProfile(name)
                
                displaySuccess("Budget profile '\(name)' removed successfully!")
                displayWarning("All sync history and categorization rules for this budget have been removed")
                
            } catch {
                displayError(error)
            }
        }
    }
}

// MARK: - Show Command

extension BudgetCommand {
    struct ShowCommand: AsyncParsableCommand, BaseCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show configuration for a budget profile"
        )
        
        @Argument(help: "Name of the budget profile to show (defaults to active profile)")
        var name: String?
        
        @Flag(name: .shortAndLong, help: "Show detailed configuration")
        var verbose: Bool = false
        
        private var configManager: ConfigManager { ConfigManager.shared }
        
        func run() async throws {
            do {
                let profile: BudgetProfile
                
                if let name = name {
                    profile = try configManager.getProfile(name)
                    displayInfo("📋 Budget Profile: \(name)")
                } else {
                    profile = try configManager.getActiveProfile()
                    displayInfo("📋 Active Budget Profile: \(profile.id)")
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
                
                print("🎯 Categorization Settings:")
                if let categorization = profile.categorizationSettings {
                    print("  Enabled: \(categorization.enabled ? "Yes" : "No")")
                    if categorization.enabled {
                        print("  Auto-apply during sync: \(categorization.autoApplyDuringSync ? "Yes" : "No")")
                        print("  Min confidence threshold: \(Int(categorization.minConfidenceThreshold * 100))%")
                        print("  Suggest new rules: \(categorization.suggestNewRules ? "Yes" : "No")")
                    }
                } else {
                    print("  Not configured")
                    print("  💡 Run 'up-ynab-sync config --categorization' to set up categorization")
                }
                
                if verbose {
                    print("")
                    print("📅 Profile Information:")
                    print("  Created: \(DateFormatter.display.string(from: profile.createdAt))")
                    print("  Updated: \(DateFormatter.display.string(from: profile.updatedAt))")
                }
                
            } catch {
                displayError(error)
            }
        }
    }
}