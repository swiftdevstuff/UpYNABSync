import ArgumentParser
import Foundation

struct StatusCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status and system health",
        discussion: """
        This command displays comprehensive status information about your sync setup.
        
        Information shown:
        • Overall system status and configuration
        • API connection health for Up Banking and YNAB
        • Last sync results and timing
        • Account mapping status with balances
        • Launch Agent automation status
        • Database health and statistics
        
        Use this command to troubleshoot issues and verify your setup is working correctly.
        """
    )
    
    @Flag(name: .shortAndLong, help: "Show verbose output with detailed information")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Test API connections and show detailed connectivity information")
    var testConnections: Bool = false
    
    @Flag(name: .long, help: "Show database statistics and health information")
    var showDatabase: Bool = false
    
    @Option(name: .long, help: "Show status for specific budget profile (defaults to active profile)")
    var budget: String?
    
    private var syncService: SyncService { SyncService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    private var upBankingService: UpBankingService { UpBankingService.shared }
    private var ynabService: YNABService { YNABService.shared }
    
    func run() async throws {
        displayInfo("📊 Checking system status...")
        print("")
        
        let status = try await getSyncStatus(budgetId: budget)
        
        try await displayOverallStatus(status)
        try await displayConfigurationStatus(status)
        try await displayAccountStatus(status)
        
        if testConnections {
            try await displayConnectionStatus()
        }
        
        try await displayAutomationStatus(status)
        
        if showDatabase || verbose {
            try await displayDatabaseStatus(status)
        }
        
        try await displayCategorizationStatus()
        try await displaySummaryAndRecommendations(status)
    }
    
    func validatePrerequisites() async throws {
        // Status command doesn't require full setup - it reports on what's missing
    }
    
    // MARK: - Status Retrieval
    
    private func getSyncStatus(budgetId: String?) async throws -> SyncStatus {
        do {
            return try await syncService.getSyncStatus(budgetId: budgetId)
        } catch {
            // Create a basic status if service fails
            let hasTokens = checkTokensAvailable()
            let hasConfig = configManager.hasConfiguration()
            
            return SyncStatus(
                isConfigured: hasConfig,
                hasValidTokens: hasTokens,
                lastSyncDate: nil,
                lastSyncStatus: nil,
                nextScheduledSync: nil,
                accountStatuses: [],
                launchAgentStatus: LaunchAgentStatus(
                    isInstalled: false,
                    isLoaded: false,
                    nextRunTime: nil,
                    lastRunTime: nil,
                    lastRunStatus: nil
                ),
                databaseHealth: DatabaseHealth(
                    isAccessible: false,
                    totalRecords: 0,
                    failedTransactions: 0,
                    oldestRecord: nil,
                    lastCleanup: nil,
                    integrityCheck: false
                )
            )
        }
    }
    
    private func checkTokensAvailable() -> Bool {
        let keychain = KeychainManager.shared
        return keychain.hasToken(service: KeychainManager.upBankingService) &&
               keychain.hasToken(service: KeychainManager.ynabService)
    }
    
    // MARK: - Status Display Methods
    
    private func displayOverallStatus(_ status: SyncStatus) async throws {
        print("🎯 Overall Status: \(status.overallStatus)")
        print("")
        
        if let lastSync = status.lastSyncDate {
            let timeAgo = DateComponentsFormatter.shared.string(from: lastSync, to: Date()) ?? "unknown"
            print("🕐 Last Sync: \(DateFormatter.display.string(from: lastSync)) (\(timeAgo) ago)")
            
            if let lastStatus = status.lastSyncStatus {
                print("📈 Last Result: \(lastStatus.emoji) \(lastStatus.rawValue.capitalized)")
            }
        } else {
            print("🕐 Last Sync: Never")
        }
        
        if let nextSync = status.nextScheduledSync {
            print("⏰ Next Scheduled: \(DateFormatter.display.string(from: nextSync))")
        }
        
        print("")
    }
    
    private func displayConfigurationStatus(_ status: SyncStatus) async throws {
        print("⚙️  Configuration:")
        
        do {
            if let budgetName = budget {
                let profile = try configManager.getProfile(budgetName)
                print("   📋 Budget Profile: \(budgetName)")
                print("   📊 YNAB Budget: \(profile.ynabBudgetName)")
                print("   🔗 Account Mappings: \(profile.accountMappings.count) accounts")
                
                if profile.accountMappings.isEmpty {
                    print("   ❌ No account mappings configured")
                    print("   💡 Run 'up-ynab-sync config --budget \(budgetName)' to configure mappings")
                } else {
                    print("   ✅ Account mappings configured")
                }
                
            } else if configManager.hasAnyConfiguration() {
                let activeProfile = try configManager.getActiveProfile()
                let allProfiles = try configManager.getAllProfiles()
                
                print("   📋 Active Budget Profile: \(activeProfile.id)")
                print("   📊 YNAB Budget: \(activeProfile.ynabBudgetName)")
                print("   🔗 Account Mappings: \(activeProfile.accountMappings.count) accounts")
                print("   📈 Total Profiles: \(allProfiles.count)")
                
                if activeProfile.accountMappings.isEmpty {
                    print("   ❌ No account mappings configured for active profile")
                    print("   💡 Run 'up-ynab-sync config' to configure mappings")
                } else {
                    print("   ✅ Account mappings configured")
                }
                
                if verbose && allProfiles.count > 1 {
                    print("   📋 All Profiles:")
                    for profile in allProfiles {
                        let isActive = profile.id == activeProfile.id
                        let indicator = isActive ? " (active)" : ""
                        print("     • \(profile.id): \(profile.ynabBudgetName)\(indicator)")
                    }
                }
            } else {
                print("   ❌ No budget profiles configured")
                print("   💡 Run 'up-ynab-sync budget add <name>' to create your first budget profile")
            }
        } catch {
            print("   ⚠️  Error loading configuration: \(error.localizedDescription)")
        }
        
        if status.hasValidTokens {
            print("   ✅ API tokens configured")
        } else {
            print("   ❌ API tokens missing or invalid")
            print("   💡 Run 'up-ynab-sync auth' to set up authentication")
        }
        
        print("")
    }
    
    private func displayAccountStatus(_ status: SyncStatus) async throws {
        print("🏦 Account Status:")
        
        if status.accountStatuses.isEmpty {
            print("   No accounts configured")
            return
        }
        
        for accountStatus in status.accountStatuses {
            let typeIcon = accountStatus.mapping.upAccountType == "TRANSACTIONAL" ? "💳" : "💰"
            
            print("   \(typeIcon) \(accountStatus.mapping.upAccountName)")
            print("      → \(accountStatus.mapping.ynabAccountName)")
            print("      Status: \(accountStatus.healthStatus)")
            
            // Show balances if available
            if let upBalance = accountStatus.upBalance,
               let ynabBalance = accountStatus.ynabBalance {
                let upFormatted = NumberFormatter.currency.string(from: NSNumber(value: upBalance)) ?? "$0.00"
                let ynabFormatted = NumberFormatter.currency.string(from: NSNumber(value: ynabBalance)) ?? "$0.00"
                
                if accountStatus.balanceMatch {
                    print("      Balance: \(upFormatted) ✅")
                } else {
                    print("      Up Balance: \(upFormatted)")
                    print("      YNAB Balance: \(ynabFormatted) ⚠️")
                }
            }
            
            // Show transaction count and last sync
            if accountStatus.transactionCount > 0 {
                print("      Transactions: \(accountStatus.transactionCount)")
            }
            
            if let lastSync = accountStatus.lastSyncDate {
                let timeAgo = DateComponentsFormatter.shared.string(from: lastSync, to: Date()) ?? "unknown"
                print("      Last Sync: \(timeAgo) ago")
            }
            
            // Show recent errors
            if !accountStatus.recentErrors.isEmpty && verbose {
                print("      Recent Errors:")
                for error in accountStatus.recentErrors.prefix(3) {
                    print("        • \(error.type.emoji) \(error.message)")
                }
                if accountStatus.recentErrors.count > 3 {
                    print("        • ... and \(accountStatus.recentErrors.count - 3) more")
                }
            }
            
            print("")
        }
    }
    
    private func displayConnectionStatus() async throws {
        print("🌐 API Connection Test:")
        
        // Test Up Banking
        do {
            let upConnected = try await upBankingService.testConnection()
            if upConnected {
                print("   ✅ Up Banking API: Connected")
                
                if verbose {
                    let accounts = try await upBankingService.getActiveAccounts()
                    print("      Found \(accounts.count) accounts")
                }
            } else {
                print("   ❌ Up Banking API: Connection failed")
            }
        } catch {
            print("   ❌ Up Banking API: Error - \(error.localizedDescription)")
        }
        
        // Test YNAB
        do {
            let ynabConnected = try await ynabService.testConnection()
            if ynabConnected {
                print("   ✅ YNAB API: Connected")
                
                if verbose {
                    let budgets = try await ynabService.getBudgets()
                    print("      Found \(budgets.count) budgets")
                }
            } else {
                print("   ❌ YNAB API: Connection failed")
            }
        } catch {
            print("   ❌ YNAB API: Error - \(error.localizedDescription)")
        }
        
        print("")
    }
    
    private func displayAutomationStatus(_ status: SyncStatus) async throws {
        print("🤖 Automation:")
        print("   \(status.launchAgentStatus.displayStatus)")
        
        if verbose && status.launchAgentStatus.isInstalled {
            if let lastRun = status.launchAgentStatus.lastRunTime {
                let timeAgo = DateComponentsFormatter.shared.string(from: lastRun, to: Date()) ?? "unknown"
                print("   Last Run: \(timeAgo) ago")
            }
            
            if let lastStatus = status.launchAgentStatus.lastRunStatus {
                print("   Last Status: \(lastStatus)")
            }
        }
        
        if !status.launchAgentStatus.isInstalled {
            print("   💡 Run 'up-ynab-sync install' to set up automatic syncing")
        }
        
        print("")
    }
    
    private func displayDatabaseStatus(_ status: SyncStatus) async throws {
        print("💾 Database:")
        print("   \(status.databaseHealth.status)")
        
        if verbose && status.databaseHealth.isAccessible {
            if let oldest = status.databaseHealth.oldestRecord {
                let timeAgo = DateComponentsFormatter.shared.string(from: oldest, to: Date()) ?? "unknown"
                print("   Oldest Record: \(timeAgo) ago")
            }
            
            if let lastCleanup = status.databaseHealth.lastCleanup {
                let timeAgo = DateComponentsFormatter.shared.string(from: lastCleanup, to: Date()) ?? "unknown"
                print("   Last Cleanup: \(timeAgo) ago")
            }
        }
        
        print("")
    }
    
    private func displayCategorizationStatus() async throws {
        let configManager = ConfigManager.shared
        
        guard configManager.hasConfiguration() else {
            return
        }
        
        do {
            let settings = try configManager.getCategorizationSettings()
            
            print("🎯 Categorization:")
            print("   Status: \(settings.enabled ? "Enabled" : "Disabled")")
            
            if settings.enabled {
                print("   Auto-apply during sync: \(settings.autoApplyDuringSync ? "Yes" : "No")")
                print("   Min confidence threshold: \(Int(settings.minConfidenceThreshold * 100))%")
                
                let merchantService = MerchantLearningService.shared
                if let rules = try? merchantService.getAllMerchantRules() {
                    print("   Rules: \(rules.count)")
                    
                    if verbose && !rules.isEmpty {
                        let usedRules = rules.filter { $0.usageCount > 0 }
                        print("   Used rules: \(usedRules.count)")
                        
                        let topRules = rules.sorted { $0.usageCount > $1.usageCount }.prefix(3)
                        if !topRules.isEmpty {
                            print("   Top rules:")
                            for rule in topRules {
                                print("     • \(rule.merchantPattern) → \(rule.categoryName) (\(rule.usageCount) uses)")
                            }
                        }
                    }
                    
                    if let stats = try? merchantService.getMerchantRuleStats() {
                        if let totalUsage = stats["total_usage"] as? Int, totalUsage > 0 {
                            print("   Total categorizations: \(totalUsage)")
                        }
                    }
                }
            } else {
                print("   💡 Run 'up-ynab-sync config --categorization' to enable categorization")
            }
            
            print("")
        } catch {
            print("🎯 Categorization: Error loading settings")
            print("")
        }
    }
    
    private func displaySummaryAndRecommendations(_ status: SyncStatus) async throws {
        print("💡 Recommendations:")
        
        var recommendations: [String] = []
        
        if !status.hasValidTokens {
            recommendations.append("Set up API authentication with 'up-ynab-sync auth'")
        }
        
        if !status.isConfigured {
            recommendations.append("Configure account mappings with 'up-ynab-sync config'")
        }
        
        if status.lastSyncDate == nil && status.isConfigured && status.hasValidTokens {
            recommendations.append("Perform your first sync with 'up-ynab-sync sync'")
        }
        
        if !status.launchAgentStatus.isInstalled && status.isConfigured {
            recommendations.append("Set up automatic syncing with 'up-ynab-sync install'")
        }
        
        // Check for old sync
        if let lastSync = status.lastSyncDate {
            let daysSinceSync = Calendar.current.dateComponents([.day], from: lastSync, to: Date()).day ?? 0
            if daysSinceSync > 7 {
                recommendations.append("Consider running a sync - it's been \(daysSinceSync) days since last sync")
            }
        }
        
        // Check for failed transactions
        if status.databaseHealth.failedTransactions > 0 {
            recommendations.append("Review failed transactions with 'up-ynab-sync review'")
        }
        
        if recommendations.isEmpty {
            print("   ✅ Your setup looks good! Everything is configured and working properly.")
        } else {
            for (index, recommendation) in recommendations.enumerated() {
                print("   \(index + 1). \(recommendation)")
            }
        }
        
        print("")
        
        // Display quick commands
        if verbose {
            print("🚀 Quick Commands:")
            print("   up-ynab-sync sync          # Sync last 24 hours")
            print("   up-ynab-sync sync --days 7 # Sync last 7 days")
            print("   up-ynab-sync status -v     # Detailed status")
            print("   up-ynab-sync review        # Review failed items")
            print("")
        }
    }
}

// MARK: - Formatting Extensions

extension DateComponentsFormatter {
    static let shared: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full
        return formatter
    }()
}