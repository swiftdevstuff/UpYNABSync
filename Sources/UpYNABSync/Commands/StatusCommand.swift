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
    
    private var syncService: SyncService { SyncService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    private var upBankingService: UpBankingService { UpBankingService.shared }
    private var ynabService: YNABService { YNABService.shared }
    
    func run() async throws {
        displayInfo("📊 Checking system status...")
        print("")
        
        let status = try await getSyncStatus()
        
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
        
        try await displaySummaryAndRecommendations(status)
    }
    
    func validatePrerequisites() async throws {
        // Status command doesn't require full setup - it reports on what's missing
    }
    
    // MARK: - Status Retrieval
    
    private func getSyncStatus() async throws -> SyncStatus {
        do {
            return try await syncService.getSyncStatus()
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
        
        if status.isConfigured {
            print("   ✅ Account mappings configured")
            
            if verbose {
                do {
                    let config = try configManager.loadConfiguration()
                    let budgetName = try await ynabService.getBudgetName(budgetId: config.ynabBudgetId)
                    print("   📊 YNAB Budget: \(budgetName)")
                    print("   🔗 Mappings: \(config.accountMappings.count) accounts")
                } catch {
                    print("   ⚠️  Error loading configuration details: \(error.localizedDescription)")
                }
            }
        } else {
            print("   ❌ Account mappings not configured")
            print("   💡 Run 'up-ynab-sync config' to set up account mappings")
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