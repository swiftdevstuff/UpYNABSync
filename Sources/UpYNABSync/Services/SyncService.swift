import Foundation

class SyncService: @unchecked Sendable {
    static let shared = SyncService()
    private init() {}
    
    private let upBankingService = UpBankingService.shared
    private let ynabService = YNABService.shared
    private let database = SyncDatabase.shared
    private let configManager = ConfigManager.shared
    private let logger = Logger.shared
    private let merchantLearningService = MerchantLearningService.shared
    
    enum SyncServiceError: Error, LocalizedError {
        case configurationMissing
        case accountMappingMissing
        case databaseNotInitialized
        case noTransactionsFound
        case partialSyncFailure([SyncError])
        case criticalSyncFailure(SyncError)
        
        var errorDescription: String? {
            switch self {
            case .configurationMissing:
                return "Sync configuration missing. Please run 'up-ynab-sync config' first."
            case .accountMappingMissing:
                return "Account mapping configuration missing."
            case .databaseNotInitialized:
                return "Database not initialized. Please check database connection."
            case .noTransactionsFound:
                return "No transactions found for the specified date range."
            case .partialSyncFailure(let errors):
                return "Partial sync failure: \(errors.count) errors occurred."
            case .criticalSyncFailure(let error):
                return "Critical sync failure: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Main Sync Operations
    
    func syncTransactions(options: SyncOptions = .default, budgetId: String? = nil) async throws -> SyncResult {
        logger.info("🔄 Starting sync operation")
        let startTime = Date()
        
        // Initialize database if needed
        try await initializeDatabaseIfNeeded()
        
        // Load configuration
        let configuration = try loadConfiguration(budgetId: budgetId)
        
        // Determine date range
        let dateRange = try determineDateRange(options: options)
        logger.logSyncStart(dateRange: formatDateRange(dateRange))
        
        // Create sync operation
        let operation = SyncOperation(
            id: UUID().uuidString,
            startDate: startTime,
            endDate: Date(),
            accountMappings: configuration.accountMappings,
            options: options
        )
        
        var accountResults: [AccountSyncResult] = []
        var allErrors: [SyncError] = []
        
        // Process each account mapping
        for mapping in configuration.accountMappings {
            guard mapping.enabled else {
                logger.info("⏭️ Skipping disabled account: \(mapping.displayName)")
                continue
            }
            
            logger.info("🔄 Processing account: \(mapping.displayName)")
            
            do {
                let accountResult = try await syncAccount(
                    mapping: mapping,
                    budgetId: configuration.ynabBudgetId,
                    dateRange: dateRange,
                    options: options
                )
                accountResults.append(accountResult)
                
                if !accountResult.errors.isEmpty {
                    allErrors.append(contentsOf: accountResult.errors)
                }
            } catch {
                let syncError = SyncError(
                    type: .accountMapping,
                    message: "Failed to sync account \(mapping.displayName): \(error.localizedDescription)",
                    accountId: mapping.upAccountId,
                    underlyingError: error,
                    isCritical: false
                )
                allErrors.append(syncError)
                logger.error("❌ Failed to sync account \(mapping.displayName): \(error)")
            }
        }
        
        // Calculate summary
        let endTime = Date()
        let summary = calculateSyncSummary(accountResults: accountResults, duration: endTime.timeIntervalSince(startTime))
        
        // Log sync completion
        let syncResult = SyncResult(
            operation: operation,
            accountResults: accountResults,
            summary: summary,
            errors: allErrors
        )
        
        try await logSyncOperation(result: syncResult, dateRange: dateRange, budgetId: configuration.ynabBudgetId)
        
        logger.logSyncComplete(summary: summary.displaySummary)
        
        return syncResult
    }
    
    private func syncAccount(mapping: SyncAccountMapping, budgetId: String, dateRange: DateInterval, options: SyncOptions) async throws -> AccountSyncResult {
        logger.info("📱 Syncing account: \(mapping.displayName)")
        
        var errors: [SyncError] = []
        var syncedResults: [SyncedTransactionResult] = []
        
        do {
            // Fetch Up Banking transactions
            let upTransactions = try await upBankingService.getTransactionsForDateRange(
                accountId: mapping.upAccountId,
                startDate: dateRange.start,
                endDate: dateRange.end
            )
            
            logger.info("📥 Found \(upTransactions.count) Up Banking transactions")
            
            // Filter out already synced transactions
            let newTransactions = try await filterAlreadySyncedTransactions(upTransactions, budgetId: budgetId)
            logger.info("🆕 \(newTransactions.count) new transactions to sync")
            
            if newTransactions.isEmpty {
                logger.info("✅ No new transactions to sync for \(mapping.displayName)")
            } else {
                // Process transactions in batches
                let batchSize = 10
                for batch in newTransactions.chunked(into: batchSize) {
                    let batchResults = try await processBatch(
                        transactions: batch,
                        mapping: mapping,
                        budgetId: budgetId,
                        options: options
                    )
                    syncedResults.append(contentsOf: batchResults)
                    
                    // Small delay between batches to avoid rate limiting
                    if batch.count == batchSize {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    }
                }
            }
            
            // Calculate summary
            let summary = calculateAccountSummary(mapping: mapping, results: syncedResults)
            
            return AccountSyncResult(
                mapping: mapping,
                upTransactions: upTransactions,
                ynabTransactions: [], // Would be populated if we fetched YNAB transactions
                syncedTransactions: syncedResults,
                summary: summary,
                errors: errors
            )
            
        } catch {
            let syncError = SyncError(
                type: .accountMapping,
                message: "Failed to sync account \(mapping.displayName): \(error.localizedDescription)",
                accountId: mapping.upAccountId,
                underlyingError: error,
                isCritical: true
            )
            errors.append(syncError)
            throw error
        }
    }
    
    private func processBatch(transactions: [UpTransaction], mapping: SyncAccountMapping, budgetId: String, options: SyncOptions) async throws -> [SyncedTransactionResult] {
        var results: [SyncedTransactionResult] = []
        
        for transaction in transactions {
            let result = try await processTransaction(
                transaction: transaction,
                mapping: mapping,
                budgetId: budgetId,
                options: options
            )
            results.append(result)
        }
        
        return results
    }
    
    private func processTransaction(transaction: UpTransaction, mapping: SyncAccountMapping, budgetId: String, options: SyncOptions) async throws -> SyncedTransactionResult {
        let syncTimestamp = Date()
        
        // Validate amount conversion before attempting sync
        let expectedYNABAmount = transaction.amount.toYNABAmount()
        let amountValidated = transaction.amount.validateYNABConversion(expectedYNABAmount)
        
        if !amountValidated {
            let error = SyncError(
                type: .amountConversion,
                message: "Amount conversion validation failed for transaction \(transaction.id)",
                accountId: mapping.upAccountId,
                transactionId: transaction.id,
                isCritical: true
            )
            
            return SyncedTransactionResult(
                upTransaction: transaction,
                ynabTransaction: nil,
                status: .failed,
                error: error,
                amountValidated: false,
                syncTimestamp: syncTimestamp
            )
        }
        
        // Perform dry run check
        if options.dryRun {
            logger.info("🔍 [DRY RUN] Would sync transaction: \(transaction.displayDescription) (\(transaction.amount.formattedValue))")
            return SyncedTransactionResult(
                upTransaction: transaction,
                ynabTransaction: nil,
                status: .synced,
                error: nil,
                amountValidated: true,
                syncTimestamp: syncTimestamp
            )
        }
        
        // Mark transaction as pending before attempting sync
        try await saveSyncedTransaction(
            upTransaction: transaction,
            ynabTransaction: nil,
            mapping: mapping,
            status: .pending,
            budgetId: budgetId
        )
        
        do {
            // Apply merchant categorization if enabled
            var merchantRule: MerchantRule? = nil
            if options.enableCategorization {
                do {
                    merchantRule = try merchantLearningService.getMerchantRule(for: transaction)
                    if let rule = merchantRule {
                        logger.info("🎯 Applying merchant rule: \(rule.merchantPattern) → \(rule.categoryName)")
                        // Update usage statistics
                        try merchantLearningService.updateRuleUsage(rule)
                    }
                } catch {
                    logger.warning("⚠️ Failed to get merchant rule: \(error.localizedDescription)")
                    // Continue without categorization
                }
            }
            
            // Sync to YNAB
            let ynabTransaction = try await ynabService.syncUpTransaction(
                transaction,
                toAccount: mapping.ynabAccountId,
                budgetId: budgetId,
                merchantRule: merchantRule
            )
            
            // Update database with successful sync
            try await saveSyncedTransaction(
                upTransaction: transaction,
                ynabTransaction: ynabTransaction,
                mapping: mapping,
                status: .synced,
                budgetId: budgetId
            )
            
            if let rule = merchantRule {
                logger.info("✅ Synced transaction with categorization: \(transaction.displayDescription) (\(transaction.amount.formattedValue)) → \(rule.categoryName)")
            } else {
                logger.info("✅ Synced transaction: \(transaction.displayDescription) (\(transaction.amount.formattedValue))")
            }
            
            return SyncedTransactionResult(
                upTransaction: transaction,
                ynabTransaction: ynabTransaction,
                status: .synced,
                error: nil,
                amountValidated: true,
                syncTimestamp: syncTimestamp
            )
            
        } catch {
            let syncError = SyncError(
                type: .apiError,
                message: "Failed to sync transaction: \(error.localizedDescription)",
                accountId: mapping.upAccountId,
                transactionId: transaction.id,
                underlyingError: error,
                isCritical: false
            )
            
            // Save failed transaction to database
            try await saveSyncedTransaction(
                upTransaction: transaction,
                ynabTransaction: nil,
                mapping: mapping,
                status: .failed,
                budgetId: budgetId
            )
            
            logger.error("❌ Failed to sync transaction \(transaction.id): \(error)")
            
            return SyncedTransactionResult(
                upTransaction: transaction,
                ynabTransaction: nil,
                status: .failed,
                error: syncError,
                amountValidated: amountValidated,
                syncTimestamp: syncTimestamp
            )
        }
    }
    
    // MARK: - Database Operations
    
    private func initializeDatabaseIfNeeded() async throws {
        do {
            try database.initialize()
        } catch {
            logger.error("Failed to initialize database: \(error)")
            throw SyncServiceError.databaseNotInitialized
        }
    }
    
    private func filterAlreadySyncedTransactions(_ transactions: [UpTransaction], budgetId: String) async throws -> [UpTransaction] {
        var newTransactions: [UpTransaction] = []
        
        for transaction in transactions {
            let status = try database.getTransactionStatus(transaction.id, budgetId: budgetId)
            
            switch status {
            case nil, "pending", "failed":
                // Transaction never attempted, pending, or failed previously - treat as new
                newTransactions.append(transaction)
                if let status = status {
                    logger.info("Transaction \(transaction.id) has status '\(status)' - treating as new")
                } else {
                    logger.debug("Transaction \(transaction.id) not found in database - marking as new")
                }
                
            case "synced":
                // Transaction successfully synced to YNAB - skip
                logger.debug("Transaction \(transaction.id) already synced - skipping")
                
            default:
                // Unknown status - treat as new and log warning
                newTransactions.append(transaction)
                logger.warning("Transaction \(transaction.id) has unknown status '\(status!)' - treating as new")
            }
        }
        
        return newTransactions
    }
    
    private func saveSyncedTransaction(upTransaction: UpTransaction, ynabTransaction: YNABTransaction?, mapping: SyncAccountMapping, status: SyncTransactionStatus, budgetId: String) async throws {
        let syncTimestamp = ISO8601DateFormatter().string(from: Date())
        
        let syncedTransaction = SyncedTransaction(
            id: upTransaction.id,
            upAccountId: mapping.upAccountId,
            upAccountName: mapping.upAccountName,
            upAmount: upTransaction.amount.doubleValue,
            upDate: upTransaction.createdAt.upBankingAPIString(),
            upDescription: upTransaction.displayDescription,
            upRawJson: (try? JSONEncoder().encode(upTransaction))?.base64EncodedString() ?? "",
            ynabAccountId: mapping.ynabAccountId,
            ynabTransactionId: ynabTransaction?.id,
            ynabAmount: upTransaction.amount.toYNABAmount(),
            syncTimestamp: syncTimestamp,
            status: status.rawValue,
            budgetId: budgetId
        )
        
        try database.insertSyncedTransaction(syncedTransaction)
    }
    
    private func logSyncOperation(result: SyncResult, dateRange: DateInterval, budgetId: String) async throws {
        let syncLogEntry = SyncLogEntry(
            id: nil,
            syncDate: ISO8601DateFormatter().string(from: Date()),
            dateRangeStart: ISO8601DateFormatter().string(from: dateRange.start),
            dateRangeEnd: ISO8601DateFormatter().string(from: dateRange.end),
            accountsProcessed: result.accountResults.count,
            transactionsProcessed: result.summary.totalTransactions,
            transactionsSynced: result.summary.syncedTransactions,
            transactionsSkipped: result.summary.skippedTransactions,
            transactionsFailed: result.summary.failedTransactions,
            errors: result.errors.isEmpty ? nil : result.errors.map { $0.displayMessage }.joined(separator: "; "),
            syncDurationSeconds: result.summary.duration,
            budgetId: budgetId
        )
        
        try database.insertSyncLogEntry(syncLogEntry)
    }
    
    // MARK: - Configuration Management
    
    private func loadConfiguration(budgetId: String? = nil) throws -> SyncConfiguration {
        let profile: BudgetProfile
        
        if let budgetId = budgetId {
            // Use specific budget profile
            profile = try configManager.getProfile(budgetId)
        } else {
            // Use active budget profile
            guard configManager.hasAnyConfiguration() else {
                throw SyncServiceError.configurationMissing
            }
            profile = try configManager.getActiveProfile()
        }
        
        let accountMappings = profile.accountMappings.map { budgetMapping in
            SyncAccountMapping(
                upAccountId: budgetMapping.upAccountId,
                upAccountName: budgetMapping.upAccountName,
                upAccountType: budgetMapping.upAccountType,
                ynabAccountId: budgetMapping.ynabAccountId,
                ynabAccountName: budgetMapping.ynabAccountName,
                enabled: true,
                lastSyncDate: nil
            )
        }
        
        return SyncConfiguration(
            ynabBudgetId: profile.ynabBudgetId,
            accountMappings: accountMappings,
            lastSyncDate: nil,
            syncSettings: .default
        )
    }
    
    private func determineDateRange(options: SyncOptions) throws -> DateInterval {
        if let customRange = options.dateRange {
            return customRange
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        
        return DateInterval(start: startDate, end: endDate)
    }
    
    // MARK: - Summary Calculations
    
    private func calculateSyncSummary(accountResults: [AccountSyncResult], duration: TimeInterval) -> SyncSummary {
        let totalTransactions = accountResults.reduce(0) { $0 + $1.syncedTransactions.count }
        let syncedCount = accountResults.reduce(0) { $0 + $1.syncedTransactions.filter { $0.status == .synced }.count }
        let skippedCount = accountResults.reduce(0) { $0 + $1.syncedTransactions.filter { $0.status == .skipped }.count }
        let failedCount = accountResults.reduce(0) { $0 + $1.syncedTransactions.filter { $0.status == .failed }.count }
        let duplicateCount = accountResults.reduce(0) { $0 + $1.syncedTransactions.filter { $0.status == .duplicate }.count }
        
        return SyncSummary(
            totalAccounts: accountResults.count,
            totalTransactions: totalTransactions,
            syncedTransactions: syncedCount,
            skippedTransactions: skippedCount,
            failedTransactions: failedCount,
            duplicateTransactions: duplicateCount,
            duration: duration
        )
    }
    
    private func calculateAccountSummary(mapping: SyncAccountMapping, results: [SyncedTransactionResult]) -> AccountSyncSummary {
        let syncedResults = results.filter { $0.status == .synced }
        let skippedResults = results.filter { $0.status == .skipped }
        let failedResults = results.filter { $0.status == .failed }
        let duplicateResults = results.filter { $0.status == .duplicate }
        
        let totalAmount = syncedResults.reduce(0.0) { $0 + $1.upTransaction.amount.doubleValue }
        let errors = results.compactMap { $0.error?.displayMessage }
        
        return AccountSyncSummary(
            accountName: mapping.displayName,
            transactionsProcessed: results.count,
            transactionsSynced: syncedResults.count,
            transactionsSkipped: skippedResults.count,
            transactionsFailed: failedResults.count,
            transactionsDuplicate: duplicateResults.count,
            amountsSynced: totalAmount,
            errors: errors
        )
    }
    
    // MARK: - Utility Methods
    
    private func formatDateRange(_ dateRange: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: dateRange.start)) to \(formatter.string(from: dateRange.end))"
    }
    
    // MARK: - Failed Transaction Management
    
    func cleanupFailedTransactions() async throws -> Int {
        logger.info("🧹 Cleaning up failed transaction records...")
        
        let deletedCount = try database.cleanupFailedTransactions()
        
        if deletedCount > 0 {
            logger.info("✅ Cleaned up \(deletedCount) failed transaction records")
        } else {
            logger.info("✅ No failed transactions to clean up")
        }
        
        return deletedCount
    }
    
    func fixIncorrectlyMarkedTransactions() async throws -> Int {
        logger.info("🔧 Fixing incorrectly marked transactions...")
        
        // Fix transactions marked as synced but without YNAB transaction ID
        let fixedCount = try database.cleanupIncorrectlyMarkedTransactions()
        
        // Reset any pending transactions that got stuck
        let resetCount = try database.resetPendingTransactions()
        
        let totalFixed = fixedCount + resetCount
        
        if totalFixed > 0 {
            logger.info("✅ Fixed \(fixedCount) incorrectly marked and reset \(resetCount) pending transactions")
        } else {
            logger.info("✅ No incorrectly marked transactions found")
        }
        
        return totalFixed
    }
    
    func getFailedTransactionsForRetry() async throws -> [SyncedTransaction] {
        logger.info("🔍 Finding failed transactions for retry...")
        
        let failedTransactions = try database.getFailedTransactions(limit: 100)
        
        logger.info("📋 Found \(failedTransactions.count) failed transactions")
        
        return failedTransactions
    }
    
    func retryFailedTransactions(options: SyncOptions = .default, budgetId: String? = nil) async throws -> SyncResult {
        logger.info("🔄 Starting retry of failed transactions")
        
        // Get failed transactions
        let failedTransactions = try await getFailedTransactionsForRetry()
        
        if failedTransactions.isEmpty {
            logger.info("✅ No failed transactions to retry")
            throw SyncServiceError.noTransactionsFound
        }
        
        // Group by account
        let transactionsByAccount = Dictionary(grouping: failedTransactions) { $0.upAccountId }
        
        // Load configuration to get account mappings
        let configuration = try loadConfiguration(budgetId: budgetId)
        
        for (upAccountId, transactions) in transactionsByAccount {
            guard let mapping = configuration.accountMappings.first(where: { $0.upAccountId == upAccountId }) else {
                logger.warning("⚠️ No account mapping found for \(upAccountId), skipping \(transactions.count) transactions")
                continue
            }
            
            logger.info("🔄 Retrying \(transactions.count) failed transactions for \(mapping.displayName)")
            
            // Delete failed records so they can be re-attempted
            for transaction in transactions {
                try database.deleteFailedTransaction(transaction.id)
                logger.debug("🗑️ Deleted failed record for transaction \(transaction.id)")
            }
        }
        
        // Now run a normal sync which will pick up these "new" transactions
        return try await syncTransactions(options: options, budgetId: budgetId)
    }
    
    // MARK: - Status and Health
    
    func getSyncStatus(budgetId: String? = nil) async throws -> SyncStatus {
        // Determine which budget profile to use
        let profile: BudgetProfile
        
        if let budgetId = budgetId {
            profile = try configManager.getProfile(budgetId)
        } else {
            guard configManager.hasAnyConfiguration() else {
                // Return basic status when no configuration exists
                return SyncStatus(
                    isConfigured: false,
                    hasValidTokens: KeychainManager.shared.hasAllTokens(),
                    lastSyncDate: nil,
                    lastSyncStatus: nil,
                    nextScheduledSync: nil,
                    accountStatuses: [],
                    launchAgentStatus: LaunchAgentStatus(isInstalled: false, isLoaded: false, nextRunTime: nil, lastRunTime: nil, lastRunStatus: nil),
                    databaseHealth: DatabaseHealth(isAccessible: true, totalRecords: 0, failedTransactions: 0, oldestRecord: nil, lastCleanup: nil, integrityCheck: true)
                )
            }
            profile = try configManager.getActiveProfile()
        }
        
        // Check configuration
        let isConfigured = !profile.accountMappings.isEmpty
        let hasValidTokens = KeychainManager.shared.hasAllTokens()
        
        // Get last sync info for this budget
        let lastSyncEntry = try database.getLastSyncLogEntry(budgetId: profile.ynabBudgetId)
        let lastSyncDate = lastSyncEntry?.syncDate.upBankingAPIDate()
        let lastSyncStatus: SyncTransactionStatus? = lastSyncEntry?.transactionsFailed ?? 0 > 0 ? .failed : .synced
        
        // Get account statuses
        var accountStatuses: [AccountStatus] = []
        if isConfigured {
            do {
                for mapping in profile.accountMappings {
                    let legacyMapping = mapping.toLegacyAccountMapping()
                    let accountStatus = try await getAccountStatus(mapping: legacyMapping, budgetId: profile.ynabBudgetId)
                    accountStatuses.append(accountStatus)
                }
            } catch {
                logger.error("Failed to get account statuses: \(error)")
            }
        }
        
        // Get Launch Agent status
        let launchAgentHelper = LaunchAgentHelper.shared
        let launchAgentStatus = LaunchAgentStatus(
            isInstalled: launchAgentHelper.isLaunchAgentInstalled(),
            isLoaded: launchAgentHelper.getLaunchAgentStatus().contains("loaded"),
            nextRunTime: launchAgentHelper.getNextRunTime().flatMap { DateFormatter().date(from: $0) },
            lastRunTime: nil,
            lastRunStatus: nil
        )
        
        // Get database health
        let databaseHealth = try await getDatabaseHealth(budgetId: profile.ynabBudgetId)
        
        return SyncStatus(
            isConfigured: isConfigured,
            hasValidTokens: hasValidTokens,
            lastSyncDate: lastSyncDate,
            lastSyncStatus: lastSyncStatus,
            nextScheduledSync: launchAgentStatus.nextRunTime,
            accountStatuses: accountStatuses,
            launchAgentStatus: launchAgentStatus,
            databaseHealth: databaseHealth
        )
    }
    
    private func getAccountStatus(mapping: ConfigManager.AccountMapping, budgetId: String) async throws -> AccountStatus {
        let syncMapping = SyncAccountMapping(
            upAccountId: mapping.upAccountId,
            upAccountName: mapping.upAccountName,
            upAccountType: mapping.upAccountType,
            ynabAccountId: mapping.ynabAccountId,
            ynabAccountName: mapping.ynabAccountName,
            enabled: true,
            lastSyncDate: nil
        )
        
        // Get Up Banking balance
        let upBalance = try? await upBankingService.getAccountBalance(accountId: mapping.upAccountId).doubleValue
        
        // Get YNAB balance
        let ynabBalance = try? await ynabService.getAccountBalance(budgetId: budgetId, accountId: mapping.ynabAccountId)
        let ynabBalanceDouble = ynabBalance.map { Double($0) / 1000.0 }
        
        // Get recent transactions
        let recentTransactions = try database.getSyncedTransactionsForAccount(mapping.upAccountId, budgetId: budgetId, limit: 50)
        
        // Get recent errors
        let recentErrors = try database.getFailedTransactions(budgetId: budgetId, limit: 10)
            .filter { $0.upAccountId == mapping.upAccountId }
            .map { transaction in
                SyncError(
                    type: .apiError,
                    message: "Failed transaction: \(transaction.upDescription)",
                    accountId: transaction.upAccountId,
                    transactionId: transaction.id
                )
            }
        
        return AccountStatus(
            mapping: syncMapping,
            upBalance: upBalance,
            ynabBalance: ynabBalanceDouble,
            lastSyncDate: nil,
            transactionCount: recentTransactions.count,
            recentErrors: recentErrors
        )
    }
    
    private func getDatabaseHealth(budgetId: String) async throws -> DatabaseHealth {
        let stats = try database.getDatabaseStats(budgetId: budgetId)
        let totalRecords = stats["total_transactions"] as? Int ?? 0
        let failedTransactions = stats["failed_transactions"] as? Int ?? 0
        let integrityCheck = try database.validateDatabaseIntegrity()
        
        return DatabaseHealth(
            isAccessible: true,
            totalRecords: totalRecords,
            failedTransactions: failedTransactions,
            oldestRecord: nil,
            lastCleanup: nil,
            integrityCheck: integrityCheck
        )
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}