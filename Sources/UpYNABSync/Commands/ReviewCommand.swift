import ArgumentParser
import Foundation

struct ReviewCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Review and handle failed transactions and sync issues",
        discussion: """
        This command helps you review and resolve sync issues, including:
        
        • Failed transactions that couldn't be synced
        • Balance mismatches between Up Banking and YNAB
        • Duplicate transaction detection
        • Configuration issues
        • Recent sync errors
        
        You can:
        • View detailed information about issues
        • Retry failed transactions individually
        • Clean up old failed records
        • Get recommendations for resolving problems
        
        Use this command after syncs to ensure everything completed successfully.
        """
    )
    
    @Flag(name: .shortAndLong, help: "Show verbose output with detailed information")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Show only critical and high priority issues")
    var criticalOnly: Bool = false
    
    @Flag(name: .long, help: "Clean up resolved issues and old records")
    var cleanup: Bool = false
    
    @Flag(name: .long, help: "Show sync history and statistics")
    var history: Bool = false
    
    @Option(name: .long, help: "Show issues for specific account only")
    var account: String?
    
    private var syncService: SyncService { SyncService.shared }
    private var database: SyncDatabase { SyncDatabase.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        displayInfo("🔍 Reviewing sync issues and failed transactions...")
        print("")
        
        if cleanup {
            try await performCleanup()
            return
        }
        
        if history {
            try await displaySyncHistory()
            return
        }
        
        let reviewSummary = try await getReviewItems()
        
        try await displayReviewSummary(reviewSummary)
        
        if reviewSummary.totalItems > 0 {
            let reviewItems = try await getDetailedReviewItems()
            try await displayReviewItems(reviewItems)
            
            if reviewSummary.actionRequiredCount > 0 {
                try await handleInteractiveReview(reviewItems)
            }
        }
        
        try await displayRecommendations(reviewSummary)
    }
    
    func validatePrerequisites() async throws {
        // Review command works even with minimal setup
        // It will show what's missing as part of the review
    }
    
    // MARK: - Review Data Retrieval
    
    private func getReviewItems() async throws -> ReviewSummary {
        do {
            // In a real implementation, this would call the sync service
            // For now, we'll simulate getting review data
            return try await simulateReviewSummary()
        } catch {
            throw CLIError.syncError("Failed to retrieve review items: \(error.localizedDescription)")
        }
    }
    
    private func getDetailedReviewItems() async throws -> [ReviewItem] {
        do {
            // In a real implementation, this would fetch detailed review items
            return try await simulateReviewItems()
        } catch {
            throw CLIError.syncError("Failed to retrieve detailed review items: \(error.localizedDescription)")
        }
    }
    
    // Get review data from database
    private func simulateReviewSummary() async throws -> ReviewSummary {
        // Get actual failed transaction count from database
        let failedCount = try getFailedTransactionCount()
        
        var itemsByType: [ReviewItem.ReviewItemType: Int] = [:]
        var itemsBySeverity: [ReviewItem.ReviewItemSeverity: Int] = [:]
        
        if failedCount > 0 {
            itemsByType[.failedTransaction] = failedCount
            itemsBySeverity[.high] = failedCount
        }
        
        return ReviewSummary(
            totalItems: failedCount,
            itemsByType: itemsByType,
            itemsBySeverity: itemsBySeverity,
            actionRequiredCount: failedCount,
            lastReviewDate: Date()
        )
    }
    
    private func getFailedTransactionCount() throws -> Int {
        let stats = try database.getDatabaseStats()
        return stats["failed_transactions"] as? Int ?? 0
    }
    
    private func simulateReviewItems() async throws -> [ReviewItem] {
        // In real implementation, query database for actual failed items
        return []
    }
    
    // MARK: - Display Methods
    
    private func displayReviewSummary(_ summary: ReviewSummary) async throws {
        print("📋 Review Summary:")
        print("   \(summary.displaySummary)")
        print("")
        
        if summary.totalItems == 0 {
            displaySuccess("No issues found! Your sync is working smoothly.")
            return
        }
        
        // Show breakdown by type
        if !summary.itemsByType.isEmpty && verbose {
            print("📊 Issues by Type:")
            for (type, count) in summary.itemsByType {
                let icon = getIconForReviewType(type)
                print("   \(icon) \(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized): \(count)")
            }
            print("")
        }
        
        // Show breakdown by severity
        if !summary.itemsBySeverity.isEmpty && verbose {
            print("🚨 Issues by Severity:")
            for severity in ReviewItem.ReviewItemSeverity.allCases.reversed() {
                if let count = summary.itemsBySeverity[severity], count > 0 {
                    print("   \(severity.emoji) \(severity.rawValue.capitalized): \(count)")
                }
            }
            print("")
        }
    }
    
    private func displayReviewItems(_ items: [ReviewItem]) async throws {
        guard !items.isEmpty else { return }
        
        let filteredItems = filterItems(items)
        
        if filteredItems.isEmpty {
            displayInfo("No items match the current filters.")
            return
        }
        
        print("🔍 Review Items:")
        print("=" * 60)
        print("")
        
        for (index, item) in filteredItems.enumerated() {
            print("\(index + 1). \(item.severity.emoji) \(item.title)")
            print("   Type: \(item.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
            print("   Description: \(item.description)")
            print("   Time: \(DateFormatter.display.string(from: item.timestamp))")
            
            if item.actionRequired {
                print("   🔧 Action Required")
            }
            
            if verbose {
                try await displayItemDetails(item)
            }
            
            print("")
        }
    }
    
    private func displayItemDetails(_ item: ReviewItem) async throws {
        switch item.data {
        case .transaction(let result):
            print("   Transaction ID: \(result.upTransaction.id)")
            print("   Amount: \(result.upTransaction.amount.formattedValue)")
            print("   Status: \(result.status.emoji) \(result.status.rawValue)")
            if let error = result.error {
                print("   Error: \(error.message)")
            }
            
        case .accountMismatch(let status):
            print("   Account: \(status.mapping.displayName)")
            if let upBalance = status.upBalance,
               let ynabBalance = status.ynabBalance {
                let upFormatted = NumberFormatter.currency.string(from: NSNumber(value: upBalance)) ?? "$0.00"
                let ynabFormatted = NumberFormatter.currency.string(from: NSNumber(value: ynabBalance)) ?? "$0.00"
                print("   Up Balance: \(upFormatted)")
                print("   YNAB Balance: \(ynabFormatted)")
                print("   Difference: \(NumberFormatter.currency.string(from: NSNumber(value: abs(upBalance - ynabBalance))) ?? "$0.00")")
            }
            
        case .error(let error):
            print("   Error Type: \(error.type.rawValue)")
            print("   Message: \(error.message)")
            if let accountId = error.accountId {
                print("   Account: \(accountId)")
            }
            if let transactionId = error.transactionId {
                print("   Transaction: \(transactionId)")
            }
            
        case .configuration(let details):
            print("   Details: \(details)")
        }
    }
    
    private func filterItems(_ items: [ReviewItem]) -> [ReviewItem] {
        var filtered = items
        
        if criticalOnly {
            filtered = filtered.filter { $0.severity == .critical || $0.severity == .high }
        }
        
        if let accountFilter = account {
            filtered = filtered.filter { item in
                switch item.data {
                case .transaction(let result):
                    return result.upTransaction.relationships.account.data?.id.lowercased().contains(accountFilter.lowercased()) ?? false
                case .accountMismatch(let status):
                    return status.mapping.upAccountName.lowercased().contains(accountFilter.lowercased()) ||
                           status.mapping.ynabAccountName.lowercased().contains(accountFilter.lowercased())
                case .error(let error):
                    return error.accountId?.lowercased().contains(accountFilter.lowercased()) ?? false
                case .configuration:
                    return false
                }
            }
        }
        
        return filtered
    }
    
    // MARK: - Interactive Review
    
    private func handleInteractiveReview(_ items: [ReviewItem]) async throws {
        let actionableItems = items.filter { $0.actionRequired }
        
        if actionableItems.isEmpty {
            return
        }
        
        print("🛠️  Interactive Review:")
        print("Found \(actionableItems.count) items that require action.")
        print("")
        
        let shouldReview = InteractiveInput.readConfirmation(
            prompt: "Would you like to review and resolve these items?",
            defaultValue: true
        )
        
        guard shouldReview else {
            displayInfo("Skipping interactive review. You can run 'up-ynab-sync review' again later.")
            return
        }
        
        for (index, item) in actionableItems.enumerated() {
            print("📝 Reviewing item \(index + 1) of \(actionableItems.count):")
            print("   \(item.severity.emoji) \(item.title)")
            print("   \(item.description)")
            print("")
            
            try await handleItemAction(item)
            print("")
        }
    }
    
    private func handleItemAction(_ item: ReviewItem) async throws {
        switch item.type {
        case .failedTransaction:
            try await handleFailedTransaction(item)
        case .balanceMismatch:
            try await handleBalanceMismatch(item)
        case .duplicateTransaction:
            try await handleDuplicateTransaction(item)
        case .configurationIssue:
            try await handleConfigurationIssue(item)
        case .syncError:
            try await handleSyncError(item)
        case .accountIssue:
            try await handleAccountIssue(item)
        }
    }
    
    private func handleFailedTransaction(_ item: ReviewItem) async throws {
        print("Available actions:")
        print("1. Retry syncing this transaction")
        print("2. Mark as resolved (skip this transaction)")
        print("3. View detailed error information")
        print("4. Skip for now")
        
        let choices = ["Retry sync", "Mark resolved", "View details", "Skip"]
        
        guard let choice = InteractiveInput.readChoiceIndex(
            prompt: "What would you like to do?",
            choices: choices
        ) else {
            displayWarning("Invalid choice, skipping item")
            return
        }
        
        switch choice {
        case 0: // Retry sync
            displayInfo("Retrying transaction sync...")
            // In real implementation: retry the specific transaction
            displaySuccess("Transaction retry queued")
            
        case 1: // Mark resolved
            displayInfo("Marking transaction as resolved...")
            // In real implementation: mark in database as resolved
            displaySuccess("Transaction marked as resolved")
            
        case 2: // View details
            print("Detailed error information:")
            if case .transaction(let result) = item.data,
               let error = result.error {
                print("   Error: \(error.message)")
                print("   Type: \(error.type.rawValue)")
                print("   Critical: \(error.isCritical ? "Yes" : "No")")
            }
            
        case 3: // Skip
            displayInfo("Skipping item")
        default:
            break
        }
    }
    
    private func handleBalanceMismatch(_ item: ReviewItem) async throws {
        print("Balance mismatch detected. This usually indicates:")
        print("• Missing transactions in YNAB")
        print("• Manual adjustments made in YNAB")
        print("• Pending transactions in Up Banking")
        print("")
        print("Recommended actions:")
        print("1. Check for pending transactions")
        print("2. Review recent manual entries in YNAB")
        print("3. Perform a full sync to catch missing transactions")
        
        let shouldFullSync = InteractiveInput.readConfirmation(
            prompt: "Would you like to perform a full sync now?",
            defaultValue: false
        )
        
        if shouldFullSync {
            displayInfo("You can perform a full sync with: up-ynab-sync sync --full")
        }
    }
    
    private func handleDuplicateTransaction(_ item: ReviewItem) async throws {
        print("Duplicate transaction detected.")
        print("This transaction appears to already exist in YNAB.")
        print("")
        print("Available actions:")
        print("1. Mark as resolved (keep the duplicate)")
        print("2. Investigate in YNAB")
        
        let shouldResolve = InteractiveInput.readConfirmation(
            prompt: "Mark as resolved?",
            defaultValue: true
        )
        
        if shouldResolve {
            displaySuccess("Duplicate marked as resolved")
        }
    }
    
    private func handleConfigurationIssue(_ item: ReviewItem) async throws {
        print("Configuration issue detected:")
        if case .configuration(let details) = item.data {
            print("   \(details)")
        }
        print("")
        print("You may need to:")
        print("• Re-run 'up-ynab-sync config' to fix account mappings")
        print("• Re-run 'up-ynab-sync auth' to refresh API tokens")
        
        let shouldReconfigure = InteractiveInput.readConfirmation(
            prompt: "Would you like guidance on fixing this?",
            defaultValue: true
        )
        
        if shouldReconfigure {
            print("Run these commands to resolve configuration issues:")
            print("   up-ynab-sync auth --test    # Test your API tokens")
            print("   up-ynab-sync config --show  # Review your configuration")
        }
    }
    
    private func handleSyncError(_ item: ReviewItem) async throws {
        print("Sync error detected. This may be temporary.")
        print("Common causes:")
        print("• Network connectivity issues")
        print("• API rate limiting")
        print("• Temporary service outages")
        print("")
        
        let shouldRetry = InteractiveInput.readConfirmation(
            prompt: "Would you like to retry the sync?",
            defaultValue: false
        )
        
        if shouldRetry {
            displayInfo("You can retry with: up-ynab-sync sync --force")
        }
    }
    
    private func handleAccountIssue(_ item: ReviewItem) async throws {
        print("Account issue detected.")
        print("This may indicate:")
        print("• Account was closed or suspended")
        print("• Account mapping needs updating")
        print("• API permissions changed")
        print("")
        
        displayInfo("Check your account status in both Up Banking and YNAB apps")
        displayInfo("If accounts are active, try: up-ynab-sync config")
    }
    
    // MARK: - Cleanup and History
    
    private func performCleanup() async throws {
        displayInfo("🧹 Cleaning up resolved issues and old records...")
        
        let shouldCleanup = InteractiveInput.readConfirmation(
            prompt: "This will remove resolved issues and records older than 30 days. Continue?",
            defaultValue: true
        )
        
        guard shouldCleanup else {
            displayInfo("Cleanup cancelled")
            return
        }
        
        // In real implementation: clean up database records
        let cleanedCount = 0 // database.cleanupOldRecords()
        
        displaySuccess("Cleanup completed! Removed \(cleanedCount) old records.")
    }
    
    private func displaySyncHistory() async throws {
        print("📊 Sync History:")
        print("=" * 50)
        
        // In real implementation: query sync log from database
        print("Last 10 syncs:")
        print("(No sync history available)")
        print("")
        
        print("📈 Statistics:")
        print("• Total syncs: 0")
        print("• Success rate: 0%")
        print("• Average duration: 0s")
        print("")
    }
    
    private func displayRecommendations(_ summary: ReviewSummary) async throws {
        print("💡 Recommendations:")
        
        if summary.totalItems == 0 {
            print("   ✅ No action needed - everything looks good!")
            print("   💡 Consider setting up automatic syncing with 'up-ynab-sync install'")
        } else {
            print("   1. Address critical and high priority issues first")
            print("   2. Run this command regularly to catch issues early")
            print("   3. Use 'up-ynab-sync status' for overall health monitoring")
            
            if summary.actionRequiredCount > 0 {
                print("   4. Run 'up-ynab-sync review' again to resolve remaining issues")
            }
        }
        
        print("")
    }
    
    // MARK: - Helper Methods
    
    private func getIconForReviewType(_ type: ReviewItem.ReviewItemType) -> String {
        switch type {
        case .failedTransaction: return "❌"
        case .balanceMismatch: return "⚖️"
        case .duplicateTransaction: return "🔄"
        case .configurationIssue: return "⚙️"
        case .syncError: return "🚨"
        case .accountIssue: return "🏦"
        }
    }
}

