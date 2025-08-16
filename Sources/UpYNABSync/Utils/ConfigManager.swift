import Foundation

class ConfigManager: @unchecked Sendable {
    static let shared = ConfigManager()
    private init() {}
    
    private let configDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".up-ynab-sync")
    
    private let configFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".up-ynab-sync")
        .appendingPathComponent("config.json")
    
    private let multiBudgetConfigFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".up-ynab-sync")
        .appendingPathComponent("multi-budget-config.json")
    
    struct Configuration: Codable {
        let ynabBudgetId: String
        let accountMappings: [AccountMapping]
        let categorizationSettings: CategorizationSettings?
        
        enum CodingKeys: String, CodingKey {
            case ynabBudgetId = "ynab_budget_id"
            case accountMappings = "account_mappings"
            case categorizationSettings = "categorization_settings"
        }
    }
    
    struct AccountMapping: Codable {
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
    }
    
    struct CategorizationSettings: Codable {
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
        
        static let `default` = CategorizationSettings(
            enabled: false,
            autoApplyDuringSync: false,
            minConfidenceThreshold: 0.7,
            suggestNewRules: true
        )
    }
    
    enum ConfigError: Error, LocalizedError {
        case configurationNotFound
        case invalidConfiguration
        case fileSystemError(Error)
        case encodingError(Error)
        case decodingError(Error)
        case profileNotFound(String)
        case profileAlreadyExists(String)
        case cannotDeleteActiveProfile(String)
        case noActiveProfile
        case migrationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .configurationNotFound:
                return "Configuration file not found. Run 'up-ynab-sync config' to set up account mappings."
            case .invalidConfiguration:
                return "Invalid configuration format"
            case .fileSystemError(let error):
                return "File system error: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Failed to encode configuration: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to decode configuration: \(error.localizedDescription)"
            case .profileNotFound(let profileId):
                return "Budget profile '\(profileId)' not found"
            case .profileAlreadyExists(let profileId):
                return "Budget profile '\(profileId)' already exists"
            case .cannotDeleteActiveProfile(let profileId):
                return "Cannot delete active budget profile '\(profileId)'. Switch to another profile first."
            case .noActiveProfile:
                return "No active budget profile configured"
            case .migrationFailed(let reason):
                return "Configuration migration failed: \(reason)"
            }
        }
    }
    
    func ensureConfigDirectory() throws {
        if !FileManager.default.fileExists(atPath: configDirectoryPath.path) {
            do {
                try FileManager.default.createDirectory(at: configDirectoryPath, withIntermediateDirectories: true)
            } catch {
                throw ConfigError.fileSystemError(error)
            }
        }
    }
    
    func saveConfiguration(_ configuration: Configuration) throws {
        try ensureConfigDirectory()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configuration)
            try data.write(to: configFilePath)
        } catch let error as EncodingError {
            throw ConfigError.encodingError(error)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func loadConfiguration() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configFilePath.path) else {
            throw ConfigError.configurationNotFound
        }
        
        do {
            let data = try Data(contentsOf: configFilePath)
            let decoder = JSONDecoder()
            return try decoder.decode(Configuration.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.decodingError(error)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func hasConfiguration() -> Bool {
        return FileManager.default.fileExists(atPath: configFilePath.path)
    }
    
    func validateConfiguration() throws -> Bool {
        let config = try loadConfiguration()
        return !config.ynabBudgetId.isEmpty && !config.accountMappings.isEmpty
    }
    
    func getAccountMapping(for upAccountId: String) throws -> AccountMapping? {
        let config = try loadConfiguration()
        return config.accountMappings.first { $0.upAccountId == upAccountId }
    }
    
    func getAllAccountMappings() throws -> [AccountMapping] {
        let config = try loadConfiguration()
        return config.accountMappings
    }
    
    func getYNABBudgetId() throws -> String {
        let config = try loadConfiguration()
        return config.ynabBudgetId
    }
    
    func addOrUpdateAccountMapping(upAccountId: String, upAccountName: String, upAccountType: String, ynabAccountId: String, ynabAccountName: String, ynabBudgetId: String) throws {
        var config: Configuration
        
        if hasConfiguration() {
            config = try loadConfiguration()
            
            // Remove existing mapping for this Up account if it exists
            let filteredMappings = config.accountMappings.filter { $0.upAccountId != upAccountId }
            
            // Add the new mapping
            let newMapping = AccountMapping(
                upAccountId: upAccountId,
                upAccountName: upAccountName,
                upAccountType: upAccountType,
                ynabAccountId: ynabAccountId,
                ynabAccountName: ynabAccountName
            )
            
            config = Configuration(
                ynabBudgetId: ynabBudgetId,
                accountMappings: filteredMappings + [newMapping],
                categorizationSettings: config.categorizationSettings
            )
        } else {
            // Create new configuration
            let newMapping = AccountMapping(
                upAccountId: upAccountId,
                upAccountName: upAccountName,
                upAccountType: upAccountType,
                ynabAccountId: ynabAccountId,
                ynabAccountName: ynabAccountName
            )
            
            config = Configuration(
                ynabBudgetId: ynabBudgetId,
                accountMappings: [newMapping],
                categorizationSettings: nil
            )
        }
        
        try saveConfiguration(config)
    }
    
    func removeAccountMapping(upAccountId: String) throws {
        guard hasConfiguration() else {
            throw ConfigError.configurationNotFound
        }
        
        let config = try loadConfiguration()
        let filteredMappings = config.accountMappings.filter { $0.upAccountId != upAccountId }
        
        let newConfig = Configuration(
            ynabBudgetId: config.ynabBudgetId,
            accountMappings: filteredMappings,
            categorizationSettings: config.categorizationSettings
        )
        
        try saveConfiguration(newConfig)
    }
    
    func clearConfiguration() throws {
        guard FileManager.default.fileExists(atPath: configFilePath.path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: configFilePath)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func removeAllData() throws {
        guard FileManager.default.fileExists(atPath: configDirectoryPath.path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: configDirectoryPath)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func getConfigDirectoryPath() -> URL {
        return configDirectoryPath
    }
    
    func updateCategorizationSettings(_ settings: CategorizationSettings) throws {
        var config = try loadConfiguration()
        config = Configuration(
            ynabBudgetId: config.ynabBudgetId,
            accountMappings: config.accountMappings,
            categorizationSettings: settings
        )
        try saveConfiguration(config)
    }
    
    func getCategorizationSettings() throws -> CategorizationSettings {
        let config = try loadConfiguration()
        return config.categorizationSettings ?? .default
    }
    
    // MARK: - Multi-Budget Configuration Support
    
    func hasMultiBudgetConfiguration() -> Bool {
        return FileManager.default.fileExists(atPath: multiBudgetConfigFilePath.path)
    }
    
    func loadMultiBudgetConfiguration() throws -> MultiBudgetConfiguration {
        guard FileManager.default.fileExists(atPath: multiBudgetConfigFilePath.path) else {
            throw ConfigError.configurationNotFound
        }
        
        do {
            let data = try Data(contentsOf: multiBudgetConfigFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MultiBudgetConfiguration.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.decodingError(error)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func saveMultiBudgetConfiguration(_ configuration: MultiBudgetConfiguration) throws {
        try ensureConfigDirectory()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(configuration)
            try data.write(to: multiBudgetConfigFilePath)
        } catch let error as EncodingError {
            throw ConfigError.encodingError(error)
        } catch {
            throw ConfigError.fileSystemError(error)
        }
    }
    
    func migrateToMultiBudgetConfiguration() throws -> MultiBudgetConfiguration {
        // Check if already migrated
        if hasMultiBudgetConfiguration() {
            return try loadMultiBudgetConfiguration()
        }
        
        // Check if there's a legacy configuration to migrate
        guard hasConfiguration() else {
            // No legacy configuration, create empty multi-budget config
            let emptyConfig = MultiBudgetConfiguration(activeProfile: "", profiles: [:])
            try saveMultiBudgetConfiguration(emptyConfig)
            return emptyConfig
        }
        
        // Load legacy configuration
        let legacyConfig = try loadConfiguration()
        
        // Create default profile from legacy configuration (budget name will be empty initially)
        let defaultProfile = BudgetProfile.fromLegacyConfiguration(legacyConfig, budgetName: "Default Budget")
        
        // Create multi-budget configuration with default profile
        let multiBudgetConfig = MultiBudgetConfiguration(
            activeProfile: "default",
            profiles: ["default": defaultProfile]
        )
        
        // Save the new configuration
        try saveMultiBudgetConfiguration(multiBudgetConfig)
        
        // Backup the legacy configuration
        let backupPath = configDirectoryPath.appendingPathComponent("config-legacy-backup.json")
        try? FileManager.default.copyItem(at: configFilePath, to: backupPath)
        
        return multiBudgetConfig
    }
    
    func migrateToMultiBudgetConfigurationAsync() async throws -> MultiBudgetConfiguration {
        // Check if already migrated
        if hasMultiBudgetConfiguration() {
            return try loadMultiBudgetConfiguration()
        }
        
        // Check if there's a legacy configuration to migrate
        guard hasConfiguration() else {
            // No legacy configuration, create empty multi-budget config
            let emptyConfig = MultiBudgetConfiguration(activeProfile: "", profiles: [:])
            try saveMultiBudgetConfiguration(emptyConfig)
            return emptyConfig
        }
        
        // Load legacy configuration
        let legacyConfig = try loadConfiguration()
        
        // Get budget name from YNAB if possible
        var budgetName = "Default Budget"
        do {
            budgetName = try await YNABService.shared.getBudgetName(budgetId: legacyConfig.ynabBudgetId)
        } catch {
            // If we can't get the budget name, use a default name
            budgetName = "Default Budget"
        }
        
        // Create default profile from legacy configuration
        let defaultProfile = BudgetProfile.fromLegacyConfiguration(legacyConfig, budgetName: budgetName)
        
        // Create multi-budget configuration with default profile
        let multiBudgetConfig = MultiBudgetConfiguration(
            activeProfile: "default",
            profiles: ["default": defaultProfile]
        )
        
        // Save the new configuration
        try saveMultiBudgetConfiguration(multiBudgetConfig)
        
        // Backup the legacy configuration
        let backupPath = configDirectoryPath.appendingPathComponent("config-legacy-backup.json")
        try? FileManager.default.copyItem(at: configFilePath, to: backupPath)
        
        return multiBudgetConfig
    }
    
    func getActiveProfile() throws -> BudgetProfile {
        let config = try getOrMigrateConfiguration()
        
        guard let activeProfile = config.getActiveProfile() else {
            throw ConfigError.noActiveProfile
        }
        
        return activeProfile
    }
    
    func setActiveProfile(_ profileId: String) throws {
        var config = try getOrMigrateConfiguration()
        try config.setActiveProfile(profileId)
        try saveMultiBudgetConfiguration(config)
    }
    
    func getAllProfiles() throws -> [BudgetProfile] {
        let config = try getOrMigrateConfiguration()
        return config.getAllProfiles()
    }
    
    func getProfile(_ profileId: String) throws -> BudgetProfile {
        let config = try getOrMigrateConfiguration()
        
        guard let profile = config.profiles[profileId] else {
            throw ConfigError.profileNotFound(profileId)
        }
        
        return profile
    }
    
    func addProfile(_ profile: BudgetProfile) throws {
        var config = try getOrMigrateConfiguration()
        try config.addProfile(profile)
        try saveMultiBudgetConfiguration(config)
    }
    
    func updateProfile(_ profile: BudgetProfile) throws {
        var config = try getOrMigrateConfiguration()
        try config.updateProfile(profile)
        try saveMultiBudgetConfiguration(config)
    }
    
    func removeProfile(_ profileId: String) throws {
        var config = try getOrMigrateConfiguration()
        try config.removeProfile(profileId)
        try saveMultiBudgetConfiguration(config)
    }
    
    func hasAnyConfiguration() -> Bool {
        return hasConfiguration() || hasMultiBudgetConfiguration()
    }
    
    private func getOrMigrateConfiguration() throws -> MultiBudgetConfiguration {
        if hasMultiBudgetConfiguration() {
            return try loadMultiBudgetConfiguration()
        } else {
            return try migrateToMultiBudgetConfiguration()
        }
    }
    
    // MARK: - Backward Compatibility Methods
    
    // These methods provide backward compatibility by operating on the active profile
    func getActiveBudgetId() throws -> String {
        let activeProfile = try getActiveProfile()
        return activeProfile.ynabBudgetId
    }
    
    func getActiveAccountMappings() throws -> [AccountMapping] {
        let activeProfile = try getActiveProfile()
        return activeProfile.accountMappings.map { $0.toLegacyAccountMapping() }
    }
    
    func getActiveCategorizationSettings() throws -> CategorizationSettings {
        let activeProfile = try getActiveProfile()
        return activeProfile.categorizationSettings?.toLegacyCategorizationSettings() ?? .default
    }
    
    func addOrUpdateAccountMappingForActiveProfile(upAccountId: String, upAccountName: String, upAccountType: String, ynabAccountId: String, ynabAccountName: String) throws {
        var activeProfile = try getActiveProfile()
        
        // Remove existing mapping for this Up account if it exists
        let filteredMappings = activeProfile.accountMappings.filter { $0.upAccountId != upAccountId }
        
        // Add the new mapping
        let newMapping = BudgetAccountMapping(
            upAccountId: upAccountId,
            upAccountName: upAccountName,
            upAccountType: upAccountType,
            ynabAccountId: ynabAccountId,
            ynabAccountName: ynabAccountName
        )
        
        let updatedProfile = BudgetProfile(
            id: activeProfile.id,
            ynabBudgetId: activeProfile.ynabBudgetId,
            ynabBudgetName: activeProfile.ynabBudgetName,
            accountMappings: filteredMappings + [newMapping],
            categorizationSettings: activeProfile.categorizationSettings
        )
        
        try updateProfile(updatedProfile)
    }
    
    func updateCategorizationSettingsForActiveProfile(_ settings: CategorizationSettings) throws {
        var activeProfile = try getActiveProfile()
        
        let budgetSettings = BudgetCategorizationSettings(
            enabled: settings.enabled,
            autoApplyDuringSync: settings.autoApplyDuringSync,
            minConfidenceThreshold: settings.minConfidenceThreshold,
            suggestNewRules: settings.suggestNewRules
        )
        
        let updatedProfile = BudgetProfile(
            id: activeProfile.id,
            ynabBudgetId: activeProfile.ynabBudgetId,
            ynabBudgetName: activeProfile.ynabBudgetName,
            accountMappings: activeProfile.accountMappings,
            categorizationSettings: budgetSettings
        )
        
        try updateProfile(updatedProfile)
    }
}

extension ConfigManager {
    func getLogsDirectory() -> URL {
        return configDirectoryPath.appendingPathComponent("logs")
    }
    
    func getDatabasePath() -> URL {
        return configDirectoryPath.appendingPathComponent("sync.db")
    }
    
    func ensureLogsDirectory() throws {
        let logsDir = getLogsDirectory()
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            do {
                try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            } catch {
                throw ConfigError.fileSystemError(error)
            }
        }
    }
}