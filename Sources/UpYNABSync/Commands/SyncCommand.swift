import ArgumentParser
import Foundation

struct SyncCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync transactions from Up Banking to YNAB",
        discussion: """
        This command syncs transactions from your Up Banking accounts to YNAB.
        
        By default, it syncs transactions from the last 24 hours. You can:
        • Use --days to sync the last N days
        • Use --full for custom date range selection
        • Use --dry-run to see what would be synced without making changes
        • Use --categorize to enable automatic merchant categorization
        
        Prerequisites:
        • API tokens must be set up (run 'up-ynab-sync auth')
        • Account mappings must be configured (run 'up-ynab-sync config')
        • For categorization: merchant rules must be created (run 'up-ynab-sync learn')
        
        The sync process:
        1. Loads your account mappings
        2. Fetches new transactions from each Up Banking account
        3. Checks for duplicates against local database
        4. Applies merchant categorization rules (if --categorize is enabled)
        5. Creates corresponding transactions in YNAB
        6. Records successful syncs to prevent future duplicates
        """
    )
    
    @Option(name: .shortAndLong, help: "Sync transactions from the last N days (e.g., --days 7)")
    var days: Int?
    
    @Flag(name: .long, help: "Interactive mode to select custom date range")
    var full: Bool = false
    
    @Flag(name: .long, help: "Show what would be synced without actually syncing")
    var dryRun: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output with transaction details")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Force sync even if recent sync detected")
    var force: Bool = false
    
    @Flag(name: .long, help: "Clean up failed transaction records before syncing")
    var cleanupFailed: Bool = false
    
    @Flag(name: .long, help: "Retry previously failed transactions")
    var retryFailed: Bool = false
    
    @Flag(name: .long, help: "Fix incorrectly marked transactions in database")
    var fixDatabase: Bool = false
    
    @Flag(name: .long, help: "Enable merchant categorization using learned rules")
    var categorize: Bool = false
    
    @Option(name: .long, help: "Specify budget profile to sync (defaults to active profile)")
    var budget: String?
    
    private var syncService: SyncService { SyncService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        // Handle database fixes first
        if fixDatabase {
            displayInfo("🔧 Fixing incorrectly marked transactions in database...")
            let fixedCount = try await syncService.fixIncorrectlyMarkedTransactions()
            if fixedCount > 0 {
                displaySuccess("Fixed \(fixedCount) incorrectly marked transactions")
            } else {
                displayInfo("No incorrectly marked transactions found")
            }
        }
        
        // Handle cleanup operations
        if cleanupFailed {
            displayInfo("🧹 Cleaning up failed transaction records...")
            let deletedCount = try await syncService.cleanupFailedTransactions()
            if deletedCount > 0 {
                displaySuccess("Cleaned up \(deletedCount) failed transaction records")
            } else {
                displayInfo("No failed transactions to clean up")
            }
            
            // If only cleanup was requested, exit here
            if !retryFailed && days == nil && !full && !fixDatabase {
                return
            }
        }
        
        // Handle retry operations
        if retryFailed {
            displayInfo("🔄 Retrying previously failed transactions...")
            let syncOptions = SyncOptions(dryRun: dryRun, verbose: verbose, enableCategorization: categorize)
            let result = try await syncService.retryFailedTransactions(options: syncOptions, budgetId: budget)
            try await displayResults(result: result)
            return
        }
        
        let syncOptions = try await buildSyncOptions()
        
        if dryRun {
            displayInfo("🧪 Dry run mode - no changes will be made")
        } else {
            displayInfo("🔄 Starting transaction sync...")
        }
        
        let result = try await performSync(options: syncOptions, budgetId: budget)
        
        try await displayResults(result: result)
        
        if !dryRun && result.summary.syncedTransactions > 0 {
            displaySuccess("Sync completed! \(result.summary.syncedTransactions) transactions synced across \(result.accountResults.count) accounts.")
            displayInfo("Run 'up-ynab-sync status' to see detailed sync status.")
        } else if dryRun {
            displayInfo("Dry run completed. Use 'up-ynab-sync sync' without --dry-run to perform actual sync.")
        } else {
            displayInfo("Sync completed - no new transactions to sync.")
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
        
        // Check configuration (budget profiles)
        guard configManager.hasAnyConfiguration() else {
            throw CLIError.prerequisiteNotMet("No budget profiles found. Please run 'up-ynab-sync budget add <name>' to create a budget profile first.")
        }
        
        // Validate budget profile configuration
        do {
            if let budgetName = budget {
                let profile = try configManager.getProfile(budgetName)
                if profile.accountMappings.isEmpty {
                    throw CLIError.prerequisiteNotMet("Budget profile '\(budgetName)' has no account mappings. Please run 'up-ynab-sync config --budget \(budgetName)' to configure account mappings.")
                }
            } else {
                let activeProfile = try configManager.getActiveProfile()
                if activeProfile.accountMappings.isEmpty {
                    throw CLIError.prerequisiteNotMet("Active budget profile '\(activeProfile.id)' has no account mappings. Please run 'up-ynab-sync config' to configure account mappings.")
                }
            }
        } catch {
            throw CLIError.prerequisiteNotMet("Invalid budget configuration: \(error.localizedDescription)")
        }
        
        displaySuccess("Prerequisites validated")
    }
    
    // MARK: - Sync Options
    
    private func buildSyncOptions() async throws -> SyncOptions {
        let dateRange = try await determineDateRange()
        
        return SyncOptions(
            fullSync: full,
            dateRange: dateRange,
            accountFilter: nil, // Use all configured accounts
            dryRun: dryRun,
            verbose: verbose,
            enableCategorization: categorize
        )
    }
    
    private func determineDateRange() async throws -> DateInterval {
        if full {
            return try await getCustomDateRange()
        } else if let daysCount = days {
            return getDateRangeForDays(daysCount)
        } else {
            // Default: last 24 hours
            return getDateRangeForDays(1)
        }
    }
    
    private func getDateRangeForDays(_ daysCount: Int) -> DateInterval {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysCount, to: endDate)!
        return DateInterval(start: startDate, end: endDate)
    }
    
    private func getCustomDateRange() async throws -> DateInterval {
        print("📅 Custom Date Range Selection")
        print("")
        
        // Get start date
        let startDate = try getDateFromUser(prompt: "Enter start date (YYYY-MM-DD):")
        
        // Get end date
        let endDate = try getDateFromUser(prompt: "Enter end date (YYYY-MM-DD):")
        
        // Validate date order
        guard startDate <= endDate else {
            throw CLIError.invalidInput("Start date must be before or equal to end date")
        }
        
        // Validate date range isn't too large (limit to 90 days)
        let daysBetween = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        guard daysBetween <= 90 else {
            throw CLIError.invalidInput("Date range too large. Please limit to 90 days or less.")
        }
        
        displayInfo("Selected date range: \(DateFormatter.dateOnly.string(from: startDate)) to \(DateFormatter.dateOnly.string(from: endDate))")
        
        return DateInterval(start: startDate, end: endDate)
    }
    
    private func getDateFromUser(prompt: String) throws -> Date {
        print("\(prompt): ", terminator: "")
        
        guard let input = readLine(), !input.isEmpty else {
            throw CLIError.invalidInput("Date cannot be empty")
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        
        guard let date = formatter.date(from: input) else {
            throw CLIError.invalidInput("Invalid date format. Please use YYYY-MM-DD (e.g., 2024-01-15)")
        }
        
        // Ensure date isn't in the future
        guard date <= Date() else {
            throw CLIError.invalidInput("Date cannot be in the future")
        }
        
        return date
    }
    
    // MARK: - Sync Execution
    
    private func performSync(options: SyncOptions, budgetId: String?) async throws -> SyncResult {
        do {
            if verbose, let dateRange = options.dateRange {
                let daysCount = Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 0
                displayInfo("Syncing \(daysCount) days of transactions from \(DateFormatter.dateOnly.string(from: dateRange.start)) to \(DateFormatter.dateOnly.string(from: dateRange.end))")
            }
            
            let result = try await syncService.syncTransactions(options: options, budgetId: budgetId)
            return result
            
        } catch {
            throw CLIError.syncError("Sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Results Display
    
    private func displayResults(result: SyncResult) async throws {
        print("")
        print("📊 Sync Results")
        print("=" * 50)
        print("")
        
        // Operation details
        print("🔄 Operation: \(result.operation.dateRange)")
        print("⏱️  Duration: \(String(format: "%.1f", result.summary.duration))s")
        
        if result.operation.options.dryRun {
            print("🧪 Mode: Dry Run (no changes made)")
        }
        print("")
        
        // Overall summary using the built-in display method
        print(result.summary.displaySummary)
        print("")
        
        // Per-account results
        if !result.accountResults.isEmpty {
            print("🏦 Account Results:")
            for accountResult in result.accountResults {
                displayAccountResult(accountResult)
            }
            print("")
        }
        
        // Display errors if any
        if !result.errors.isEmpty {
            print("⚠️  Errors Encountered:")
            for error in result.errors {
                displaySyncError(error)
            }
            print("")
        }
        
        // Verbose transaction details
        if verbose && !result.accountResults.isEmpty {
            displayTransactionDetails(result: result)
        }
    }
    
    private func displayAccountResult(_ accountResult: AccountSyncResult) {
        let typeIcon = accountResult.mapping.upAccountType == "TRANSACTIONAL" ? "💳" : "💰"
        
        print("   \(typeIcon) \(accountResult.mapping.upAccountName)")
        print("      → \(accountResult.mapping.ynabAccountName)")
        print(accountResult.summary.displaySummary.replacingOccurrences(of: "📱 ", with: "      "))
        
        if !accountResult.errors.isEmpty {
            print("      Errors: \(accountResult.errors.count)")
        }
        
        print("")
    }
    
    private func displaySyncError(_ error: SyncError) {
        let timestamp = DateFormatter.display.string(from: error.timestamp)
        
        print("   \(error.type.emoji) \(error.type.rawValue.capitalized) Error (\(timestamp)): \(error.message)")
        
        if let accountId = error.accountId {
            print("      Account: \(accountId)")
        }
        
        if let transactionId = error.transactionId {
            print("      Transaction: \(transactionId)")
        }
        
        if error.isCritical {
            print("      🚨 CRITICAL ERROR")
        }
    }
    
    private func displayTransactionDetails(result: SyncResult) {
        guard verbose else { return }
        
        print("📝 Transaction Details:")
        print("-" * 50)
        
        for accountResult in result.accountResults {
            if accountResult.summary.transactionsSynced > 0 {
                print("   \(accountResult.mapping.upAccountName):")
                
                // Show synced transactions if available
                for syncedTransaction in accountResult.syncedTransactions {
                    if syncedTransaction.status == .synced {
                        print("      \(syncedTransaction.status.emoji) \(syncedTransaction.upTransaction.description) (\(syncedTransaction.upTransaction.amount.formattedValue))")
                    }
                }
                
                if !accountResult.errors.isEmpty {
                    print("      Errors:")
                    for error in accountResult.errors {
                        print("        • \(error.displayMessage)")
                    }
                }
                print("")
            }
        }
    }
}

// MARK: - String Multiplication Extension

extension String {
    static func *(left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}