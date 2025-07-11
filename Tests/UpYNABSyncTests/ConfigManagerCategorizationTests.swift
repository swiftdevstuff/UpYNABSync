import XCTest
@testable import UpYNABSync

final class ConfigManagerCategorizationTests: XCTestCase {
    var configManager: ConfigManager!
    var testConfigPath: URL!
    
    override func setUp() {
        super.setUp()
        configManager = ConfigManager.shared
        
        let tempDir = FileManager.default.temporaryDirectory
        testConfigPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
    }
    
    override func tearDown() {
        super.tearDown()
        if FileManager.default.fileExists(atPath: testConfigPath.path) {
            try? FileManager.default.removeItem(at: testConfigPath)
        }
        configManager = nil
    }
    
    func testCategorizationSettingsDefault() {
        let defaultSettings = ConfigManager.CategorizationSettings.default
        
        XCTAssertFalse(defaultSettings.enabled)
        XCTAssertFalse(defaultSettings.autoApplyDuringSync)
        XCTAssertEqual(defaultSettings.minConfidenceThreshold, 0.7)
        XCTAssertTrue(defaultSettings.suggestNewRules)
    }
    
    func testCategorizationSettingsCustom() {
        let customSettings = ConfigManager.CategorizationSettings(
            enabled: true,
            autoApplyDuringSync: true,
            minConfidenceThreshold: 0.85,
            suggestNewRules: false
        )
        
        XCTAssertTrue(customSettings.enabled)
        XCTAssertTrue(customSettings.autoApplyDuringSync)
        XCTAssertEqual(customSettings.minConfidenceThreshold, 0.85)
        XCTAssertFalse(customSettings.suggestNewRules)
    }
    
    func testCategorizationSettingsEncoding() {
        let settings = ConfigManager.CategorizationSettings(
            enabled: true,
            autoApplyDuringSync: true,
            minConfidenceThreshold: 0.85,
            suggestNewRules: false
        )
        
        let encoder = JSONEncoder()
        XCTAssertNoThrow(try encoder.encode(settings))
        
        do {
            let data = try encoder.encode(settings)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            XCTAssertNotNil(json)
            XCTAssertEqual(json?["enabled"] as? Bool, true)
            XCTAssertEqual(json?["auto_apply_during_sync"] as? Bool, true)
            XCTAssertEqual(json?["min_confidence_threshold"] as? Double, 0.85)
            XCTAssertEqual(json?["suggest_new_rules"] as? Bool, false)
        } catch {
            XCTFail("Encoding failed: \(error)")
        }
    }
    
    func testCategorizationSettingsDecoding() {
        let json = """
        {
            "enabled": true,
            "auto_apply_during_sync": true,
            "min_confidence_threshold": 0.85,
            "suggest_new_rules": false
        }
        """
        
        let decoder = JSONDecoder()
        
        do {
            let data = json.data(using: .utf8)!
            let settings = try decoder.decode(ConfigManager.CategorizationSettings.self, from: data)
            
            XCTAssertTrue(settings.enabled)
            XCTAssertTrue(settings.autoApplyDuringSync)
            XCTAssertEqual(settings.minConfidenceThreshold, 0.85)
            XCTAssertFalse(settings.suggestNewRules)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
    
    func testConfigurationWithCategorizationSettings() {
        let settings = ConfigManager.CategorizationSettings(
            enabled: true,
            autoApplyDuringSync: true,
            minConfidenceThreshold: 0.85,
            suggestNewRules: false
        )
        
        let accountMapping = ConfigManager.AccountMapping(
            upAccountId: "up-account-id",
            upAccountName: "Up Account",
            upAccountType: "TRANSACTIONAL",
            ynabAccountId: "ynab-account-id",
            ynabAccountName: "YNAB Account"
        )
        
        let config = ConfigManager.Configuration(
            ynabBudgetId: "budget-id",
            accountMappings: [accountMapping],
            categorizationSettings: settings
        )
        
        XCTAssertEqual(config.ynabBudgetId, "budget-id")
        XCTAssertEqual(config.accountMappings.count, 1)
        XCTAssertNotNil(config.categorizationSettings)
        XCTAssertTrue(config.categorizationSettings?.enabled ?? false)
    }
    
    func testConfigurationWithoutCategorizationSettings() {
        let accountMapping = ConfigManager.AccountMapping(
            upAccountId: "up-account-id",
            upAccountName: "Up Account",
            upAccountType: "TRANSACTIONAL",
            ynabAccountId: "ynab-account-id",
            ynabAccountName: "YNAB Account"
        )
        
        let config = ConfigManager.Configuration(
            ynabBudgetId: "budget-id",
            accountMappings: [accountMapping],
            categorizationSettings: nil
        )
        
        XCTAssertEqual(config.ynabBudgetId, "budget-id")
        XCTAssertEqual(config.accountMappings.count, 1)
        XCTAssertNil(config.categorizationSettings)
    }
    
    func testConfigurationBackwardCompatibility() {
        let json = """
        {
            "ynab_budget_id": "budget-id",
            "account_mappings": [
                {
                    "up_account_id": "up-account-id",
                    "up_account_name": "Up Account",
                    "up_account_type": "TRANSACTIONAL",
                    "ynab_account_id": "ynab-account-id",
                    "ynab_account_name": "YNAB Account"
                }
            ]
        }
        """
        
        let decoder = JSONDecoder()
        
        do {
            let data = json.data(using: .utf8)!
            let config = try decoder.decode(ConfigManager.Configuration.self, from: data)
            
            XCTAssertEqual(config.ynabBudgetId, "budget-id")
            XCTAssertEqual(config.accountMappings.count, 1)
            XCTAssertNil(config.categorizationSettings)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
    
    func testConfigurationWithCategorizationSettingsJSON() {
        let json = """
        {
            "ynab_budget_id": "budget-id",
            "account_mappings": [
                {
                    "up_account_id": "up-account-id",
                    "up_account_name": "Up Account",
                    "up_account_type": "TRANSACTIONAL",
                    "ynab_account_id": "ynab-account-id",
                    "ynab_account_name": "YNAB Account"
                }
            ],
            "categorization_settings": {
                "enabled": true,
                "auto_apply_during_sync": true,
                "min_confidence_threshold": 0.85,
                "suggest_new_rules": false
            }
        }
        """
        
        let decoder = JSONDecoder()
        
        do {
            let data = json.data(using: .utf8)!
            let config = try decoder.decode(ConfigManager.Configuration.self, from: data)
            
            XCTAssertEqual(config.ynabBudgetId, "budget-id")
            XCTAssertEqual(config.accountMappings.count, 1)
            XCTAssertNotNil(config.categorizationSettings)
            XCTAssertTrue(config.categorizationSettings?.enabled ?? false)
            XCTAssertTrue(config.categorizationSettings?.autoApplyDuringSync ?? false)
            XCTAssertEqual(config.categorizationSettings?.minConfidenceThreshold, 0.85)
            XCTAssertFalse(config.categorizationSettings?.suggestNewRules ?? true)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
}