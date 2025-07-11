import Foundation

class ConfigManager: @unchecked Sendable {
    static let shared = ConfigManager()
    private init() {}
    
    private let configDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".up-ynab-sync")
    
    private let configFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".up-ynab-sync")
        .appendingPathComponent("config.json")
    
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