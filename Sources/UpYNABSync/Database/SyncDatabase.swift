import Foundation
@preconcurrency import SQLite

class SyncDatabase: @unchecked Sendable {
    static let shared = SyncDatabase()
    private init() {}
    
    private let logger = Logger.shared
    private var db: Connection?
    
    enum DatabaseError: Error, LocalizedError {
        case connectionFailed
        case migrationFailed(Error)
        case queryFailed(Error)
        case transactionNotFound
        case duplicateTransaction
        case invalidData
        case ruleAlreadyExists(String)
        case ruleNotFound(String)
        case invalidPattern(String)
        case categoryNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .connectionFailed:
                return "Failed to connect to database"
            case .migrationFailed(let error):
                return "Database migration failed: \(error.localizedDescription)"
            case .queryFailed(let error):
                return "Database query failed: \(error.localizedDescription)"
            case .transactionNotFound:
                return "Transaction not found in database"
            case .duplicateTransaction:
                return "Transaction already exists in database"
            case .invalidData:
                return "Invalid data provided to database"
            case .ruleAlreadyExists(let pattern):
                return "Merchant rule already exists for pattern: \(pattern)"
            case .ruleNotFound(let pattern):
                return "Merchant rule not found for pattern: \(pattern)"
            case .invalidPattern(let pattern):
                return "Invalid merchant pattern: \(pattern)"
            case .categoryNotFound(let categoryId):
                return "Category not found: \(categoryId)"
            }
        }
    }
    
    func initialize() throws {
        let dbPath = ConfigManager.shared.getDatabasePath()
        
        do {
            try ConfigManager.shared.ensureConfigDirectory()
            db = try Connection(dbPath.path)
            try createTables()
            try migrateDatabase()
            logger.info("Database initialized at: \(dbPath.path)")
        } catch {
            logger.error("Failed to initialize database: \(error)")
            throw DatabaseError.connectionFailed
        }
    }
    
    private func createTables() throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Create synced_transactions table
            try db.run(DatabaseTables.syncedTransactions.create(ifNotExists: true) { t in
                t.column(DatabaseTables.syncedTransactionId, primaryKey: true)
                t.column(DatabaseTables.syncedUpAccountId)
                t.column(DatabaseTables.syncedUpAccountName)
                t.column(DatabaseTables.syncedUpAmount)
                t.column(DatabaseTables.syncedUpDate)
                t.column(DatabaseTables.syncedUpDescription)
                t.column(DatabaseTables.syncedUpRawJson)
                t.column(DatabaseTables.syncedYnabAccountId)
                t.column(DatabaseTables.syncedYnabTransactionId)
                t.column(DatabaseTables.syncedYnabAmount)
                t.column(DatabaseTables.syncedSyncTimestamp)
                t.column(DatabaseTables.syncedStatus)
            })
            
            // Create account_mappings table
            try db.run(DatabaseTables.accountMappings.create(ifNotExists: true) { t in
                t.column(DatabaseTables.mappingId, primaryKey: .autoincrement)
                t.column(DatabaseTables.mappingUpAccountId, unique: true)
                t.column(DatabaseTables.mappingUpAccountName)
                t.column(DatabaseTables.mappingUpAccountType)
                t.column(DatabaseTables.mappingYnabBudgetId)
                t.column(DatabaseTables.mappingYnabAccountId)
                t.column(DatabaseTables.mappingYnabAccountName)
                t.column(DatabaseTables.mappingCreatedAt)
                t.column(DatabaseTables.mappingUpdatedAt)
            })
            
            // Create sync_log table
            try db.run(DatabaseTables.syncLog.create(ifNotExists: true) { t in
                t.column(DatabaseTables.logId, primaryKey: .autoincrement)
                t.column(DatabaseTables.logSyncDate)
                t.column(DatabaseTables.logDateRangeStart)
                t.column(DatabaseTables.logDateRangeEnd)
                t.column(DatabaseTables.logAccountsProcessed)
                t.column(DatabaseTables.logTransactionsProcessed)
                t.column(DatabaseTables.logTransactionsSynced)
                t.column(DatabaseTables.logTransactionsSkipped)
                t.column(DatabaseTables.logTransactionsFailed)
                t.column(DatabaseTables.logErrors)
                t.column(DatabaseTables.logSyncDurationSeconds)
            })
            
            logger.logDatabaseOperation("Created", table: "all tables")
        } catch {
            logger.error("Failed to create database tables: \(error)")
            throw DatabaseError.migrationFailed(error)
        }
    }
    
    private func migrateDatabase() throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let currentVersion = try getCurrentDatabaseVersion()
            let targetVersion = 2
            
            if currentVersion < targetVersion {
                logger.info("Migrating database from version \(currentVersion) to \(targetVersion)")
                
                if currentVersion < 2 {
                    try migrateToVersion2()
                }
                
                try setDatabaseVersion(targetVersion)
                logger.info("Database migration completed successfully")
            }
        } catch {
            logger.error("Failed to migrate database: \(error)")
            throw DatabaseError.migrationFailed(error)
        }
    }
    
    private func getCurrentDatabaseVersion() throws -> Int {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Check if database_version table exists
            let tableExists = try db.scalar(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='database_version'"
            ) as! Int64
            
            if tableExists == 0 {
                // Create database_version table
                try db.run(DatabaseTables.databaseVersion.create { t in
                    t.column(DatabaseTables.versionId, primaryKey: .autoincrement)
                    t.column(DatabaseTables.versionNumber)
                    t.column(DatabaseTables.versionUpdatedAt)
                })
                
                // Insert initial version
                try db.run(DatabaseTables.databaseVersion.insert(
                    DatabaseTables.versionNumber <- 1,
                    DatabaseTables.versionUpdatedAt <- ISO8601DateFormatter().string(from: Date())
                ))
                
                return 1
            }
            
            // Get current version
            if let row = try db.pluck(DatabaseTables.databaseVersion.order(DatabaseTables.versionId.desc).limit(1)) {
                return row[DatabaseTables.versionNumber]
            }
            
            return 1
        } catch {
            logger.error("Failed to get database version: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    private func setDatabaseVersion(_ version: Int) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.databaseVersion.insert(
                DatabaseTables.versionNumber <- version,
                DatabaseTables.versionUpdatedAt <- ISO8601DateFormatter().string(from: Date())
            ))
        } catch {
            logger.error("Failed to set database version: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    private func migrateToVersion2() throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Create merchant_rules table
            try db.run(DatabaseTables.merchantRules.create(ifNotExists: true) { t in
                t.column(DatabaseTables.merchantRuleId, primaryKey: .autoincrement)
                t.column(DatabaseTables.merchantRulePattern, unique: true)
                t.column(DatabaseTables.merchantRuleCategoryId)
                t.column(DatabaseTables.merchantRuleCategoryName)
                t.column(DatabaseTables.merchantRulePayeeName)
                t.column(DatabaseTables.merchantRuleConfidence, defaultValue: 1.0)
                t.column(DatabaseTables.merchantRuleUsageCount, defaultValue: 0)
                t.column(DatabaseTables.merchantRuleLastUsed)
                t.column(DatabaseTables.merchantRuleCreatedAt)
                t.column(DatabaseTables.merchantRuleUpdatedAt)
            })
            
            // Create categorization_history table
            try db.run(DatabaseTables.categorizationHistory.create(ifNotExists: true) { t in
                t.column(DatabaseTables.historyId, primaryKey: .autoincrement)
                t.column(DatabaseTables.historyTransactionId)
                t.column(DatabaseTables.historyMerchantPattern)
                t.column(DatabaseTables.historySuggestedCategoryId)
                t.column(DatabaseTables.historyAppliedCategoryId)
                t.column(DatabaseTables.historyUserAccepted, defaultValue: false)
                t.column(DatabaseTables.historyConfidence)
                t.column(DatabaseTables.historyCreatedAt)
            })
            
            logger.info("Successfully migrated database to version 2 - added merchant learning tables")
        } catch {
            logger.error("Failed to migrate to version 2: \(error)")
            throw DatabaseError.migrationFailed(error)
        }
    }
    
    // MARK: - Synced Transactions
    
    func insertSyncedTransaction(_ transaction: SyncedTransaction) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.syncedTransactions.insert(or: .replace,
                DatabaseTables.syncedTransactionId <- transaction.id,
                DatabaseTables.syncedUpAccountId <- transaction.upAccountId,
                DatabaseTables.syncedUpAccountName <- transaction.upAccountName,
                DatabaseTables.syncedUpAmount <- transaction.upAmount,
                DatabaseTables.syncedUpDate <- transaction.upDate,
                DatabaseTables.syncedUpDescription <- transaction.upDescription,
                DatabaseTables.syncedUpRawJson <- transaction.upRawJson,
                DatabaseTables.syncedYnabAccountId <- transaction.ynabAccountId,
                DatabaseTables.syncedYnabTransactionId <- transaction.ynabTransactionId,
                DatabaseTables.syncedYnabAmount <- transaction.ynabAmount,
                DatabaseTables.syncedSyncTimestamp <- transaction.syncTimestamp,
                DatabaseTables.syncedStatus <- transaction.status
            ))
            
            logger.logDatabaseOperation("Inserted/Updated", table: "synced_transactions")
        } catch {
            logger.error("Failed to insert/update synced transaction: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func isTransactionSynced(_ transactionId: String) throws -> Bool {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let count = try db.scalar(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedTransactionId == transactionId)
                .filter(DatabaseTables.syncedStatus == "synced")
                .count)
            return count > 0
        } catch {
            logger.error("Failed to check if transaction is synced: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getFailedTransactions(limit: Int = 50) throws -> [SyncedTransaction] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedStatus == "failed")
                .order(DatabaseTables.syncedSyncTimestamp.desc)
                .limit(limit))
            
            return rows.map { $0.toSyncedTransaction() }
        } catch {
            logger.error("Failed to get failed transactions: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getTransactionStatus(_ transactionId: String) throws -> String? {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            if let row = try db.pluck(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedTransactionId == transactionId)) {
                return row[DatabaseTables.syncedStatus]
            }
            return nil
        } catch {
            logger.error("Failed to get transaction status: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func deleteFailedTransaction(_ transactionId: String) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let transaction = DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedTransactionId == transactionId)
                .filter(DatabaseTables.syncedStatus == "failed")
            
            let deleted = try db.run(transaction.delete())
            if deleted > 0 {
                logger.logDatabaseOperation("Deleted failed transaction", table: "synced_transactions")
            }
        } catch {
            logger.error("Failed to delete failed transaction: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func cleanupFailedTransactions() throws -> Int {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let deleted = try db.run(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedStatus == "failed")
                .delete())
            
            if deleted > 0 {
                logger.info("Cleaned up \(deleted) failed transaction records")
            }
            return deleted
        } catch {
            logger.error("Failed to cleanup failed transactions: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func resetPendingTransactions() throws -> Int {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Reset pending transactions to allow retry
            let updated = try db.run(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedStatus == "pending")
                .update(DatabaseTables.syncedStatus <- "failed"))
            
            if updated > 0 {
                logger.info("Reset \(updated) pending transactions to failed status for retry")
            }
            return updated
        } catch {
            logger.error("Failed to reset pending transactions: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func cleanupIncorrectlyMarkedTransactions() throws -> Int {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Find transactions that were marked as synced but have no YNAB transaction ID
            // These are likely transactions that failed but were incorrectly marked
            let updated = try db.run(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedStatus == "synced")
                .filter(DatabaseTables.syncedYnabTransactionId == nil)
                .update(DatabaseTables.syncedStatus <- "failed"))
            
            if updated > 0 {
                logger.info("Fixed \(updated) incorrectly marked transactions (synced without YNAB ID)")
            }
            return updated
        } catch {
            logger.error("Failed to cleanup incorrectly marked transactions: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getSyncedTransactionsForAccount(_ upAccountId: String, limit: Int = 100) throws -> [SyncedTransaction] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedUpAccountId == upAccountId)
                .order(DatabaseTables.syncedSyncTimestamp.desc)
                .limit(limit))
            
            return rows.map { $0.toSyncedTransaction() }
        } catch {
            logger.error("Failed to get synced transactions for account: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func updateTransactionStatus(_ transactionId: String, status: String, ynabTransactionId: String? = nil) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let transaction = DatabaseTables.syncedTransactions.filter(DatabaseTables.syncedTransactionId == transactionId)
            let updateValues: [Setter] = [
                DatabaseTables.syncedStatus <- status,
                DatabaseTables.syncedYnabTransactionId <- ynabTransactionId
            ]
            
            let updated = try db.run(transaction.update(updateValues))
            if updated == 0 {
                throw DatabaseError.transactionNotFound
            }
            
            logger.logDatabaseOperation("Updated", table: "synced_transactions")
        } catch {
            logger.error("Failed to update transaction status: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    // MARK: - Account Mappings
    
    func insertAccountMapping(_ mapping: AccountMapping) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.accountMappings.insert(or: .replace,
                DatabaseTables.mappingUpAccountId <- mapping.upAccountId,
                DatabaseTables.mappingUpAccountName <- mapping.upAccountName,
                DatabaseTables.mappingUpAccountType <- mapping.upAccountType,
                DatabaseTables.mappingYnabBudgetId <- mapping.ynabBudgetId,
                DatabaseTables.mappingYnabAccountId <- mapping.ynabAccountId,
                DatabaseTables.mappingYnabAccountName <- mapping.ynabAccountName,
                DatabaseTables.mappingCreatedAt <- mapping.createdAt,
                DatabaseTables.mappingUpdatedAt <- mapping.updatedAt
            ))
            
            logger.logDatabaseOperation("Inserted/Updated", table: "account_mappings")
        } catch {
            logger.error("Failed to insert account mapping: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getAccountMapping(_ upAccountId: String) throws -> AccountMapping? {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            if let row = try db.pluck(DatabaseTables.accountMappings
                .filter(DatabaseTables.mappingUpAccountId == upAccountId)) {
                return row.toAccountMapping()
            }
            return nil
        } catch {
            logger.error("Failed to get account mapping: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getAllAccountMappings() throws -> [AccountMapping] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.accountMappings
                .order(DatabaseTables.mappingCreatedAt))
            
            return rows.map { $0.toAccountMapping() }
        } catch {
            logger.error("Failed to get all account mappings: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func deleteAccountMapping(_ upAccountId: String) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let mapping = DatabaseTables.accountMappings.filter(DatabaseTables.mappingUpAccountId == upAccountId)
            try db.run(mapping.delete())
            
            logger.logDatabaseOperation("Deleted", table: "account_mappings")
        } catch {
            logger.error("Failed to delete account mapping: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    // MARK: - Sync Log
    
    func insertSyncLogEntry(_ entry: SyncLogEntry) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.syncLog.insert(
                DatabaseTables.logSyncDate <- entry.syncDate,
                DatabaseTables.logDateRangeStart <- entry.dateRangeStart,
                DatabaseTables.logDateRangeEnd <- entry.dateRangeEnd,
                DatabaseTables.logAccountsProcessed <- entry.accountsProcessed,
                DatabaseTables.logTransactionsProcessed <- entry.transactionsProcessed,
                DatabaseTables.logTransactionsSynced <- entry.transactionsSynced,
                DatabaseTables.logTransactionsSkipped <- entry.transactionsSkipped,
                DatabaseTables.logTransactionsFailed <- entry.transactionsFailed,
                DatabaseTables.logErrors <- entry.errors,
                DatabaseTables.logSyncDurationSeconds <- entry.syncDurationSeconds
            ))
            
            logger.logDatabaseOperation("Inserted", table: "sync_log")
        } catch {
            logger.error("Failed to insert sync log entry: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getLastSyncLogEntry() throws -> SyncLogEntry? {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            if let row = try db.pluck(DatabaseTables.syncLog
                .order(DatabaseTables.logSyncDate.desc)
                .limit(1)) {
                return row.toSyncLogEntry()
            }
            return nil
        } catch {
            logger.error("Failed to get last sync log entry: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getSyncLogEntries(limit: Int = 10) throws -> [SyncLogEntry] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.syncLog
                .order(DatabaseTables.logSyncDate.desc)
                .limit(limit))
            
            return rows.map { $0.toSyncLogEntry() }
        } catch {
            logger.error("Failed to get sync log entries: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    // MARK: - Maintenance
    
    func cleanupOldRecords() throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        let cutoffDate = dateFormatter.string(from: thirtyDaysAgo)
        
        do {
            // Clean up old synced transactions
            let deletedTransactions = try db.run(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedSyncTimestamp < cutoffDate)
                .delete())
            
            // Clean up old sync log entries
            let deletedLogs = try db.run(DatabaseTables.syncLog
                .filter(DatabaseTables.logSyncDate < cutoffDate)
                .delete())
            
            logger.info("Cleaned up \(deletedTransactions) old transactions and \(deletedLogs) old log entries")
        } catch {
            logger.error("Failed to cleanup old records: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getDatabaseStats() throws -> [String: Any] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let transactionCount = try db.scalar(DatabaseTables.syncedTransactions.count)
            let mappingCount = try db.scalar(DatabaseTables.accountMappings.count)
            let logCount = try db.scalar(DatabaseTables.syncLog.count)
            let failedCount = try db.scalar(DatabaseTables.syncedTransactions
                .filter(DatabaseTables.syncedStatus == "failed").count)
            
            return [
                "total_transactions": transactionCount,
                "account_mappings": mappingCount,
                "sync_logs": logCount,
                "failed_transactions": failedCount
            ]
        } catch {
            logger.error("Failed to get database stats: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func validateDatabaseIntegrity() throws -> Bool {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            // Check for transactions with invalid amount conversions
            // Note: Complex type comparison skipped for now - could be implemented with raw SQL if needed
            let transactionCount = try db.scalar(DatabaseTables.syncedTransactions.count)
            logger.debug("Database contains \(transactionCount) synced transactions")
            
            // Check for orphaned transactions (no corresponding account mapping)
            let orphanedTransactions = try db.prepare("""
                SELECT COUNT(*) FROM synced_transactions st
                LEFT JOIN account_mappings am ON st.up_account_id = am.up_account_id
                WHERE am.up_account_id IS NULL
                """)
            
            if let row = orphanedTransactions.makeIterator().next(),
               let count = row[0] as? Int64, count > 0 {
                logger.warning("Found \(count) orphaned transactions without account mappings")
                return false
            }
            
            logger.info("Database integrity check passed")
            return true
        } catch {
            logger.error("Failed to validate database integrity: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    // MARK: - Merchant Learning
    
    func insertMerchantRule(_ rule: MerchantRule) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.merchantRules.insert(or: .replace,
                DatabaseTables.merchantRulePattern <- rule.merchantPattern,
                DatabaseTables.merchantRuleCategoryId <- rule.categoryId,
                DatabaseTables.merchantRuleCategoryName <- rule.categoryName,
                DatabaseTables.merchantRulePayeeName <- rule.payeeName,
                DatabaseTables.merchantRuleConfidence <- rule.confidence,
                DatabaseTables.merchantRuleUsageCount <- rule.usageCount,
                DatabaseTables.merchantRuleLastUsed <- rule.lastUsed,
                DatabaseTables.merchantRuleCreatedAt <- rule.createdAt,
                DatabaseTables.merchantRuleUpdatedAt <- rule.updatedAt
            ))
            
            logger.logDatabaseOperation("Inserted/Updated", table: "merchant_rules")
        } catch {
            logger.error("Failed to insert merchant rule: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getMerchantRule(_ pattern: String) throws -> MerchantRule? {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            if let row = try db.pluck(DatabaseTables.merchantRules
                .filter(DatabaseTables.merchantRulePattern == pattern)) {
                return row.toMerchantRule()
            }
            return nil
        } catch {
            logger.error("Failed to get merchant rule: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getAllMerchantRules() throws -> [MerchantRule] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.merchantRules
                .order(DatabaseTables.merchantRuleUsageCount.desc))
            
            return rows.map { $0.toMerchantRule() }
        } catch {
            logger.error("Failed to get all merchant rules: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func updateMerchantRuleUsage(_ pattern: String) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rule = DatabaseTables.merchantRules.filter(DatabaseTables.merchantRulePattern == pattern)
            let now = ISO8601DateFormatter().string(from: Date())
            
            let updated = try db.run(rule.update(
                DatabaseTables.merchantRuleUsageCount <- DatabaseTables.merchantRuleUsageCount + 1,
                DatabaseTables.merchantRuleLastUsed <- now,
                DatabaseTables.merchantRuleUpdatedAt <- now
            ))
            
            if updated == 0 {
                throw DatabaseError.ruleNotFound(pattern)
            }
            
            logger.logDatabaseOperation("Updated usage", table: "merchant_rules")
        } catch {
            logger.error("Failed to update merchant rule usage: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func deleteMerchantRule(_ pattern: String) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rule = DatabaseTables.merchantRules.filter(DatabaseTables.merchantRulePattern == pattern)
            let deleted = try db.run(rule.delete())
            
            if deleted == 0 {
                throw DatabaseError.ruleNotFound(pattern)
            }
            
            logger.logDatabaseOperation("Deleted", table: "merchant_rules")
        } catch {
            logger.error("Failed to delete merchant rule: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func insertCategorizationHistory(_ history: CategorizationHistory) throws {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            try db.run(DatabaseTables.categorizationHistory.insert(
                DatabaseTables.historyTransactionId <- history.transactionId,
                DatabaseTables.historyMerchantPattern <- history.merchantPattern,
                DatabaseTables.historySuggestedCategoryId <- history.suggestedCategoryId,
                DatabaseTables.historyAppliedCategoryId <- history.appliedCategoryId,
                DatabaseTables.historyUserAccepted <- history.userAccepted,
                DatabaseTables.historyConfidence <- history.confidence,
                DatabaseTables.historyCreatedAt <- history.createdAt
            ))
            
            logger.logDatabaseOperation("Inserted", table: "categorization_history")
        } catch {
            logger.error("Failed to insert categorization history: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getCategorizationHistory(limit: Int = 100) throws -> [CategorizationHistory] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let rows = try db.prepare(DatabaseTables.categorizationHistory
                .order(DatabaseTables.historyCreatedAt.desc)
                .limit(limit))
            
            return rows.map { $0.toCategorizationHistory() }
        } catch {
            logger.error("Failed to get categorization history: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
    
    func getMerchantRuleStats() throws -> [String: Any] {
        guard let db = db else {
            throw DatabaseError.connectionFailed
        }
        
        do {
            let totalRules = try db.scalar(DatabaseTables.merchantRules.count)
            let usedRules = try db.scalar(DatabaseTables.merchantRules
                .filter(DatabaseTables.merchantRuleUsageCount > 0).count)
            let totalUsage = try db.scalar(DatabaseTables.merchantRules
                .select(DatabaseTables.merchantRuleUsageCount.sum)) ?? 0
            
            return [
                "total_rules": totalRules,
                "used_rules": usedRules,
                "total_usage": totalUsage
            ]
        } catch {
            logger.error("Failed to get merchant rule stats: \(error)")
            throw DatabaseError.queryFailed(error)
        }
    }
}