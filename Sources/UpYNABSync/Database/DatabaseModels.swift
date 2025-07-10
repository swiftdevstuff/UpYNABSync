import Foundation
import SQLite

struct SyncedTransaction {
    let id: String
    let upAccountId: String
    let upAccountName: String
    let upAmount: Double
    let upDate: String
    let upDescription: String
    let upRawJson: String
    let ynabAccountId: String
    let ynabTransactionId: String?
    let ynabAmount: Int
    let syncTimestamp: String
    let status: String
}

struct AccountMapping {
    let id: Int64?
    let upAccountId: String
    let upAccountName: String
    let upAccountType: String
    let ynabBudgetId: String
    let ynabAccountId: String
    let ynabAccountName: String
    let createdAt: String
    let updatedAt: String
}

struct SyncLogEntry {
    let id: Int64?
    let syncDate: String
    let dateRangeStart: String
    let dateRangeEnd: String
    let accountsProcessed: Int
    let transactionsProcessed: Int
    let transactionsSynced: Int
    let transactionsSkipped: Int
    let transactionsFailed: Int
    let errors: String?
    let syncDurationSeconds: Double
}

// SQLite table definitions
class DatabaseTables {
    static let syncedTransactions = Table("synced_transactions")
    static let accountMappings = Table("account_mappings")
    static let syncLog = Table("sync_log")
    
    // synced_transactions columns
    static let syncedTransactionId = Expression<String>("id")
    static let syncedUpAccountId = Expression<String>("up_account_id")
    static let syncedUpAccountName = Expression<String>("up_account_name")
    static let syncedUpAmount = Expression<Double>("up_amount")
    static let syncedUpDate = Expression<String>("up_date")
    static let syncedUpDescription = Expression<String>("up_description")
    static let syncedUpRawJson = Expression<String>("up_raw_json")
    static let syncedYnabAccountId = Expression<String>("ynab_account_id")
    static let syncedYnabTransactionId = Expression<String?>("ynab_transaction_id")
    static let syncedYnabAmount = Expression<Int>("ynab_amount")
    static let syncedSyncTimestamp = Expression<String>("sync_timestamp")
    static let syncedStatus = Expression<String>("status")
    
    // account_mappings columns
    static let mappingId = Expression<Int64>("id")
    static let mappingUpAccountId = Expression<String>("up_account_id")
    static let mappingUpAccountName = Expression<String>("up_account_name")
    static let mappingUpAccountType = Expression<String>("up_account_type")
    static let mappingYnabBudgetId = Expression<String>("ynab_budget_id")
    static let mappingYnabAccountId = Expression<String>("ynab_account_id")
    static let mappingYnabAccountName = Expression<String>("ynab_account_name")
    static let mappingCreatedAt = Expression<String>("created_at")
    static let mappingUpdatedAt = Expression<String>("updated_at")
    
    // sync_log columns
    static let logId = Expression<Int64>("id")
    static let logSyncDate = Expression<String>("sync_date")
    static let logDateRangeStart = Expression<String>("date_range_start")
    static let logDateRangeEnd = Expression<String>("date_range_end")
    static let logAccountsProcessed = Expression<Int>("accounts_processed")
    static let logTransactionsProcessed = Expression<Int>("transactions_processed")
    static let logTransactionsSynced = Expression<Int>("transactions_synced")
    static let logTransactionsSkipped = Expression<Int>("transactions_skipped")
    static let logTransactionsFailed = Expression<Int>("transactions_failed")
    static let logErrors = Expression<String?>("errors")
    static let logSyncDurationSeconds = Expression<Double>("sync_duration_seconds")
}

// Row -> Model conversion extensions
extension Row {
    func toSyncedTransaction() -> SyncedTransaction {
        return SyncedTransaction(
            id: self[DatabaseTables.syncedTransactionId],
            upAccountId: self[DatabaseTables.syncedUpAccountId],
            upAccountName: self[DatabaseTables.syncedUpAccountName],
            upAmount: self[DatabaseTables.syncedUpAmount],
            upDate: self[DatabaseTables.syncedUpDate],
            upDescription: self[DatabaseTables.syncedUpDescription],
            upRawJson: self[DatabaseTables.syncedUpRawJson],
            ynabAccountId: self[DatabaseTables.syncedYnabAccountId],
            ynabTransactionId: self[DatabaseTables.syncedYnabTransactionId],
            ynabAmount: self[DatabaseTables.syncedYnabAmount],
            syncTimestamp: self[DatabaseTables.syncedSyncTimestamp],
            status: self[DatabaseTables.syncedStatus]
        )
    }
    
    func toAccountMapping() -> AccountMapping {
        return AccountMapping(
            id: self[DatabaseTables.mappingId],
            upAccountId: self[DatabaseTables.mappingUpAccountId],
            upAccountName: self[DatabaseTables.mappingUpAccountName],
            upAccountType: self[DatabaseTables.mappingUpAccountType],
            ynabBudgetId: self[DatabaseTables.mappingYnabBudgetId],
            ynabAccountId: self[DatabaseTables.mappingYnabAccountId],
            ynabAccountName: self[DatabaseTables.mappingYnabAccountName],
            createdAt: self[DatabaseTables.mappingCreatedAt],
            updatedAt: self[DatabaseTables.mappingUpdatedAt]
        )
    }
    
    func toSyncLogEntry() -> SyncLogEntry {
        return SyncLogEntry(
            id: self[DatabaseTables.logId],
            syncDate: self[DatabaseTables.logSyncDate],
            dateRangeStart: self[DatabaseTables.logDateRangeStart],
            dateRangeEnd: self[DatabaseTables.logDateRangeEnd],
            accountsProcessed: self[DatabaseTables.logAccountsProcessed],
            transactionsProcessed: self[DatabaseTables.logTransactionsProcessed],
            transactionsSynced: self[DatabaseTables.logTransactionsSynced],
            transactionsSkipped: self[DatabaseTables.logTransactionsSkipped],
            transactionsFailed: self[DatabaseTables.logTransactionsFailed],
            errors: self[DatabaseTables.logErrors],
            syncDurationSeconds: self[DatabaseTables.logSyncDurationSeconds]
        )
    }
}