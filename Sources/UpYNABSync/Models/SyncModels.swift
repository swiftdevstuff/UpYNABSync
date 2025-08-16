import Foundation

// MARK: - Multi-Budget Configuration Models

struct BudgetProfile: Codable, Identifiable {
    let id: String
    let ynabBudgetId: String
    let ynabBudgetName: String
    let accountMappings: [BudgetAccountMapping]
    let categorizationSettings: BudgetCategorizationSettings?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case ynabBudgetId = "ynab_budget_id"
        case ynabBudgetName = "ynab_budget_name"
        case accountMappings = "account_mappings"
        case categorizationSettings = "categorization_settings"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    var displayName: String {
        return ynabBudgetName.isEmpty ? ynabBudgetId : ynabBudgetName
    }
    
    var isActive: Bool {
        return !accountMappings.isEmpty
    }
    
    init(id: String, ynabBudgetId: String, ynabBudgetName: String, accountMappings: [BudgetAccountMapping] = [], categorizationSettings: BudgetCategorizationSettings? = nil) {
        self.id = id
        self.ynabBudgetId = ynabBudgetId
        self.ynabBudgetName = ynabBudgetName
        self.accountMappings = accountMappings
        self.categorizationSettings = categorizationSettings
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Create from legacy ConfigManager.Configuration for migration
    static func fromLegacyConfiguration(_ legacyConfig: ConfigManager.Configuration, budgetName: String = "") -> BudgetProfile {
        let budgetMappings = legacyConfig.accountMappings.map { legacyMapping in
            BudgetAccountMapping(
                upAccountId: legacyMapping.upAccountId,
                upAccountName: legacyMapping.upAccountName,
                upAccountType: legacyMapping.upAccountType,
                ynabAccountId: legacyMapping.ynabAccountId,
                ynabAccountName: legacyMapping.ynabAccountName
            )
        }
        
        let budgetCategorizationSettings = legacyConfig.categorizationSettings.map { legacySettings in
            BudgetCategorizationSettings(
                enabled: legacySettings.enabled,
                autoApplyDuringSync: legacySettings.autoApplyDuringSync,
                minConfidenceThreshold: legacySettings.minConfidenceThreshold,
                suggestNewRules: legacySettings.suggestNewRules
            )
        }
        
        return BudgetProfile(
            id: "default",
            ynabBudgetId: legacyConfig.ynabBudgetId,
            ynabBudgetName: budgetName,
            accountMappings: budgetMappings,
            categorizationSettings: budgetCategorizationSettings
        )
    }
}

struct BudgetAccountMapping: Codable {
    let upAccountId: String
    let upAccountName: String
    let upAccountType: String
    let ynabAccountId: String
    let ynabAccountName: String
    
    enum CodingKeys: String, CodingKey {
        case upAccountId = "up_account_id"
        case upAccountName = "up_account_name"
        case upAccountType = "up_account_type"
        case ynabAccountId = "ynab_account_id"
        case ynabAccountName = "ynab_account_name"
    }
    
    var displayName: String {
        return "\(upAccountName) → \(ynabAccountName)"
    }
    
    var isTransactionAccount: Bool {
        return upAccountType.lowercased() == "transactional"
    }
    
    var isSaverAccount: Bool {
        return upAccountType.lowercased() == "saver"
    }
    
    // Convert to legacy ConfigManager.AccountMapping for compatibility
    func toLegacyAccountMapping() -> ConfigManager.AccountMapping {
        return ConfigManager.AccountMapping(
            upAccountId: upAccountId,
            upAccountName: upAccountName,
            upAccountType: upAccountType,
            ynabAccountId: ynabAccountId,
            ynabAccountName: ynabAccountName
        )
    }
}

struct BudgetCategorizationSettings: Codable {
    let enabled: Bool
    let autoApplyDuringSync: Bool
    let minConfidenceThreshold: Double
    let suggestNewRules: Bool
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case autoApplyDuringSync = "auto_apply_during_sync"
        case minConfidenceThreshold = "min_confidence_threshold"
        case suggestNewRules = "suggest_new_rules"
    }
    
    static let `default` = BudgetCategorizationSettings(
        enabled: false,
        autoApplyDuringSync: false,
        minConfidenceThreshold: 0.7,
        suggestNewRules: true
    )
    
    // Convert to legacy ConfigManager.CategorizationSettings for compatibility
    func toLegacyCategorizationSettings() -> ConfigManager.CategorizationSettings {
        return ConfigManager.CategorizationSettings(
            enabled: enabled,
            autoApplyDuringSync: autoApplyDuringSync,
            minConfidenceThreshold: minConfidenceThreshold,
            suggestNewRules: suggestNewRules
        )
    }
}

struct MultiBudgetConfiguration: Codable {
    let version: String
    var activeProfile: String
    var profiles: [String: BudgetProfile]
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case version
        case activeProfile = "active_profile"
        case profiles
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    static let currentVersion = "2.0"
    
    init(activeProfile: String, profiles: [String: BudgetProfile]) {
        self.version = Self.currentVersion
        self.activeProfile = activeProfile
        self.profiles = profiles
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func getActiveProfile() -> BudgetProfile? {
        return profiles[activeProfile]
    }
    
    func getAllProfiles() -> [BudgetProfile] {
        return Array(profiles.values).sorted { $0.displayName < $1.displayName }
    }
    
    func hasProfile(_ profileId: String) -> Bool {
        return profiles[profileId] != nil
    }
    
    mutating func setActiveProfile(_ profileId: String) throws {
        guard hasProfile(profileId) else {
            throw ConfigError.profileNotFound(profileId)
        }
        activeProfile = profileId
    }
    
    mutating func addProfile(_ profile: BudgetProfile) throws {
        guard !hasProfile(profile.id) else {
            throw ConfigError.profileAlreadyExists(profile.id)
        }
        profiles[profile.id] = profile
    }
    
    mutating func updateProfile(_ profile: BudgetProfile) throws {
        guard hasProfile(profile.id) else {
            throw ConfigError.profileNotFound(profile.id)
        }
        profiles[profile.id] = profile
    }
    
    mutating func removeProfile(_ profileId: String) throws {
        guard hasProfile(profileId) else {
            throw ConfigError.profileNotFound(profileId)
        }
        
        guard profileId != activeProfile else {
            throw ConfigError.cannotDeleteActiveProfile(profileId)
        }
        
        profiles.removeValue(forKey: profileId)
    }
}

enum ConfigError: Error, LocalizedError {
    case profileNotFound(String)
    case profileAlreadyExists(String)
    case cannotDeleteActiveProfile(String)
    case noActiveProfile
    case invalidConfiguration
    case migrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .profileNotFound(let profileId):
            return "Budget profile '\(profileId)' not found"
        case .profileAlreadyExists(let profileId):
            return "Budget profile '\(profileId)' already exists"
        case .cannotDeleteActiveProfile(let profileId):
            return "Cannot delete active budget profile '\(profileId)'. Switch to another profile first."
        case .noActiveProfile:
            return "No active budget profile configured"
        case .invalidConfiguration:
            return "Invalid configuration format"
        case .migrationFailed(let reason):
            return "Configuration migration failed: \(reason)"
        }
    }
}

// MARK: - Sync Configuration Models

struct SyncConfiguration: Codable {
    let ynabBudgetId: String
    let accountMappings: [SyncAccountMapping]
    let lastSyncDate: Date?
    let syncSettings: SyncSettings
    
    enum CodingKeys: String, CodingKey {
        case ynabBudgetId = "ynab_budget_id"
        case accountMappings = "account_mappings"
        case lastSyncDate = "last_sync_date"
        case syncSettings = "sync_settings"
    }
}

struct SyncAccountMapping: Codable {
    let upAccountId: String
    let upAccountName: String
    let upAccountType: String
    let ynabAccountId: String
    let ynabAccountName: String
    let enabled: Bool
    let lastSyncDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case upAccountId = "up_account_id"
        case upAccountName = "up_account_name"
        case upAccountType = "up_account_type"
        case ynabAccountId = "ynab_account_id"
        case ynabAccountName = "ynab_account_name"
        case enabled
        case lastSyncDate = "last_sync_date"
    }
    
    var displayName: String {
        return "\(upAccountName) → \(ynabAccountName)"
    }
    
    var isTransactionAccount: Bool {
        return upAccountType.lowercased() == "transactional"
    }
    
    var isSaverAccount: Bool {
        return upAccountType.lowercased() == "saver"
    }
}

struct SyncSettings: Codable {
    let defaultSyncDays: Int
    let maxRetries: Int
    let retryDelay: TimeInterval
    let batchSize: Int
    let enabledAccountTypes: [String]
    let skipWeekends: Bool
    let notificationEnabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case defaultSyncDays = "default_sync_days"
        case maxRetries = "max_retries"
        case retryDelay = "retry_delay"
        case batchSize = "batch_size"
        case enabledAccountTypes = "enabled_account_types"
        case skipWeekends = "skip_weekends"
        case notificationEnabled = "notification_enabled"
    }
    
    static let `default` = SyncSettings(
        defaultSyncDays: 1,
        maxRetries: 1,
        retryDelay: 2.0,
        batchSize: 50,
        enabledAccountTypes: ["TRANSACTIONAL", "SAVER"],
        skipWeekends: false,
        notificationEnabled: true
    )
}

// MARK: - Sync Operation Models

struct SyncOperation {
    let id: String
    let startDate: Date
    let endDate: Date
    let accountMappings: [SyncAccountMapping]
    let options: SyncOptions
    
    var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
    }
    
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
}

struct SyncOptions {
    let fullSync: Bool
    let dateRange: DateInterval?
    let accountFilter: [String]?
    let dryRun: Bool
    let verbose: Bool
    let enableCategorization: Bool  // NEW: Enable merchant categorization
    
    init(fullSync: Bool = false, dateRange: DateInterval? = nil, accountFilter: [String]? = nil, dryRun: Bool = false, verbose: Bool = false, enableCategorization: Bool = false) {
        self.fullSync = fullSync
        self.dateRange = dateRange
        self.accountFilter = accountFilter
        self.dryRun = dryRun
        self.verbose = verbose
        self.enableCategorization = enableCategorization
    }
    
    static let `default` = SyncOptions()
}

struct SyncResult {
    let operation: SyncOperation
    let accountResults: [AccountSyncResult]
    let summary: SyncSummary
    let errors: [SyncError]
    
    var isSuccess: Bool {
        return errors.isEmpty || errors.allSatisfy { !$0.isCritical }
    }
    
    var hasWarnings: Bool {
        return errors.contains { !$0.isCritical }
    }
}

struct AccountSyncResult {
    let mapping: SyncAccountMapping
    let upTransactions: [UpTransaction]
    let ynabTransactions: [YNABTransaction]
    let syncedTransactions: [SyncedTransactionResult]
    let summary: AccountSyncSummary
    let errors: [SyncError]
    
    var isSuccess: Bool {
        return errors.isEmpty || errors.allSatisfy { !$0.isCritical }
    }
}

struct SyncedTransactionResult {
    let upTransaction: UpTransaction
    let ynabTransaction: YNABTransaction?
    let status: SyncTransactionStatus
    let error: SyncError?
    let amountValidated: Bool
    let syncTimestamp: Date
    
    var isSuccess: Bool {
        return status == .synced && amountValidated
    }
}

enum SyncTransactionStatus: String, CaseIterable {
    case pending = "pending"
    case synced = "synced"
    case failed = "failed"
    case skipped = "skipped"
    case duplicate = "duplicate"
    
    var emoji: String {
        switch self {
        case .pending: return "⏳"
        case .synced: return "✅"
        case .failed: return "❌"
        case .skipped: return "⏭️"
        case .duplicate: return "🔄"
        }
    }
}

struct SyncSummary {
    let totalAccounts: Int
    let totalTransactions: Int
    let syncedTransactions: Int
    let skippedTransactions: Int
    let failedTransactions: Int
    let duplicateTransactions: Int
    let duration: TimeInterval
    
    var successRate: Double {
        guard totalTransactions > 0 else { return 0.0 }
        return Double(syncedTransactions) / Double(totalTransactions)
    }
    
    var displaySummary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        
        let successRateString = formatter.string(from: NSNumber(value: successRate)) ?? "0%"
        
        return """
        📊 Sync Summary:
        • Accounts: \(totalAccounts)
        • Transactions: \(totalTransactions)
        • ✅ Synced: \(syncedTransactions)
        • ⏭️ Skipped: \(skippedTransactions)
        • ❌ Failed: \(failedTransactions)
        • 🔄 Duplicates: \(duplicateTransactions)
        • 🎯 Success Rate: \(successRateString)
        • ⏱️ Duration: \(String(format: "%.1f", duration))s
        """
    }
}

struct AccountSyncSummary {
    let accountName: String
    let transactionsProcessed: Int
    let transactionsSynced: Int
    let transactionsSkipped: Int
    let transactionsFailed: Int
    let transactionsDuplicate: Int
    let amountsSynced: Double
    let errors: [String]
    
    var displaySummary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let amountString = formatter.string(from: NSNumber(value: amountsSynced)) ?? "$0.00"
        
        return """
        📱 \(accountName):
        • Processed: \(transactionsProcessed)
        • Synced: \(transactionsSynced) (\(amountString))
        • Skipped: \(transactionsSkipped)
        • Failed: \(transactionsFailed)
        • Duplicates: \(transactionsDuplicate)
        """
    }
}

// MARK: - Error Models

struct SyncError: Error, LocalizedError {
    let id: String
    let type: SyncErrorType
    let accountId: String?
    let transactionId: String?
    let message: String
    let underlyingError: Error?
    let timestamp: Date
    let isCritical: Bool
    
    enum SyncErrorType: String, CaseIterable {
        case authentication = "authentication"
        case network = "network"
        case apiError = "api_error"
        case dataValidation = "data_validation"
        case amountConversion = "amount_conversion"
        case duplicateTransaction = "duplicate_transaction"
        case accountMapping = "account_mapping"
        case databaseError = "database_error"
        case configurationError = "configuration_error"
        case rateLimited = "rate_limited"
        case unknown = "unknown"
        
        var emoji: String {
            switch self {
            case .authentication: return "🔒"
            case .network: return "🌐"
            case .apiError: return "🔌"
            case .dataValidation: return "📋"
            case .amountConversion: return "💰"
            case .duplicateTransaction: return "🔄"
            case .accountMapping: return "🔗"
            case .databaseError: return "💾"
            case .configurationError: return "⚙️"
            case .rateLimited: return "⏱️"
            case .unknown: return "❓"
            }
        }
    }
    
    var errorDescription: String? {
        return "\(type.emoji) \(message)"
    }
    
    var displayMessage: String {
        var components = [type.emoji, message]
        
        if let accountId = accountId {
            components.append("(Account: \(accountId))")
        }
        
        if let transactionId = transactionId {
            components.append("(Transaction: \(transactionId))")
        }
        
        return components.joined(separator: " ")
    }
    
    init(type: SyncErrorType, message: String, accountId: String? = nil, transactionId: String? = nil, underlyingError: Error? = nil, isCritical: Bool = false) {
        self.id = UUID().uuidString
        self.type = type
        self.message = message
        self.accountId = accountId
        self.transactionId = transactionId
        self.underlyingError = underlyingError
        self.isCritical = isCritical
        self.timestamp = Date()
    }
}

// MARK: - Status Models

struct SyncStatus {
    let isConfigured: Bool
    let hasValidTokens: Bool
    let lastSyncDate: Date?
    let lastSyncStatus: SyncTransactionStatus?
    let nextScheduledSync: Date?
    let accountStatuses: [AccountStatus]
    let launchAgentStatus: LaunchAgentStatus
    let databaseHealth: DatabaseHealth
    
    var overallStatus: String {
        if !isConfigured {
            return "⚠️ Not configured"
        }
        
        if !hasValidTokens {
            return "🔒 Authentication required"
        }
        
        if let lastStatus = lastSyncStatus {
            switch lastStatus {
            case .synced:
                return "✅ Healthy"
            case .failed:
                return "❌ Last sync failed"
            case .pending:
                return "⏳ Sync in progress"
            case .skipped:
                return "⏭️ Last sync skipped"
            case .duplicate:
                return "🔄 Duplicate detected"
            }
        }
        
        return "❓ Unknown status"
    }
}

struct AccountStatus {
    let mapping: SyncAccountMapping
    let upBalance: Double?
    let ynabBalance: Double?
    let lastSyncDate: Date?
    let transactionCount: Int
    let recentErrors: [SyncError]
    
    var balanceMatch: Bool {
        guard let upBalance = upBalance, let ynabBalance = ynabBalance else {
            return false
        }
        return abs(upBalance - ynabBalance) < 0.01
    }
    
    var healthStatus: String {
        if !recentErrors.isEmpty {
            return "❌ Errors"
        }
        
        if balanceMatch {
            return "✅ Healthy"
        }
        
        return "⚠️ Balance mismatch"
    }
}

struct LaunchAgentStatus {
    let isInstalled: Bool
    let isLoaded: Bool
    let nextRunTime: Date?
    let lastRunTime: Date?
    let lastRunStatus: String?
    
    var displayStatus: String {
        if !isInstalled {
            return "❌ Not installed"
        }
        
        if !isLoaded {
            return "⚠️ Not loaded"
        }
        
        if let nextRun = nextRunTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "⏰ Next run: \(formatter.string(from: nextRun))"
        }
        
        return "✅ Active"
    }
}

struct DatabaseHealth {
    let isAccessible: Bool
    let totalRecords: Int
    let failedTransactions: Int
    let oldestRecord: Date?
    let lastCleanup: Date?
    let integrityCheck: Bool
    
    var status: String {
        if !isAccessible {
            return "❌ Database not accessible"
        }
        
        if !integrityCheck {
            return "⚠️ Integrity issues found"
        }
        
        if failedTransactions > 0 {
            return "⚠️ \(failedTransactions) failed transactions"
        }
        
        return "✅ Healthy (\(totalRecords) records)"
    }
}

// MARK: - Review Models

struct ReviewItem {
    let id: String
    let type: ReviewItemType
    let title: String
    let description: String
    let data: ReviewItemData
    let severity: ReviewItemSeverity
    let actionRequired: Bool
    let timestamp: Date
    
    enum ReviewItemType: String, CaseIterable {
        case failedTransaction = "failed_transaction"
        case balanceMismatch = "balance_mismatch"
        case duplicateTransaction = "duplicate_transaction"
        case configurationIssue = "configuration_issue"
        case syncError = "sync_error"
        case accountIssue = "account_issue"
    }
    
    enum ReviewItemSeverity: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var emoji: String {
            switch self {
            case .low: return "🔵"
            case .medium: return "🟡"
            case .high: return "🟠"
            case .critical: return "🔴"
            }
        }
    }
    
    enum ReviewItemData {
        case transaction(SyncedTransactionResult)
        case accountMismatch(AccountStatus)
        case error(SyncError)
        case configuration(String)
    }
}

struct ReviewSummary {
    let totalItems: Int
    let itemsByType: [ReviewItem.ReviewItemType: Int]
    let itemsBySeverity: [ReviewItem.ReviewItemSeverity: Int]
    let actionRequiredCount: Int
    let lastReviewDate: Date?
    
    var needsAttention: Bool {
        return actionRequiredCount > 0
    }
    
    var displaySummary: String {
        let criticalCount = itemsBySeverity[.critical] ?? 0
        let highCount = itemsBySeverity[.high] ?? 0
        
        if criticalCount > 0 {
            return "🔴 \(criticalCount) critical issues require immediate attention"
        }
        
        if highCount > 0 {
            return "🟠 \(highCount) high priority issues need review"
        }
        
        if totalItems > 0 {
            return "🟡 \(totalItems) items for review"
        }
        
        return "✅ No issues found"
    }
}