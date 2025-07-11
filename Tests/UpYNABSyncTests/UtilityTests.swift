import XCTest
@testable import UpYNABSync

final class UtilityTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clean up any test data before each test
        cleanupTestData()
    }
    
    override func tearDown() {
        // Clean up test data after each test
        cleanupTestData()
        super.tearDown()
    }
    
    private func cleanupTestData() {
        // Clean up test keychain items and config files
        let testKeychainManager = KeychainManager.shared
        try? testKeychainManager.deleteToken(service: "test-service")
        
        // Clean up test config if it exists
        let testConfigPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-up-ynab-sync-config.json")
        try? FileManager.default.removeItem(at: testConfigPath)
    }
    
    // MARK: - KeychainManager Tests
    
    func testKeychainTokenStorage() throws {
        let keychain = KeychainManager.shared
        let testService = "test-service"
        let testToken = "test-token-12345"
        
        // Test saving token
        XCTAssertNoThrow(try keychain.saveToken(service: testService, token: testToken))
        
        // Test retrieving token
        let retrievedToken = try keychain.getToken(service: testService)
        XCTAssertEqual(retrievedToken, testToken, "Retrieved token should match saved token")
        
        // Test token exists check
        XCTAssertTrue(keychain.hasToken(service: testService), "Should detect that token exists")
        
        // Test deleting token
        XCTAssertNoThrow(try keychain.deleteToken(service: testService))
        
        // Test token no longer exists
        XCTAssertFalse(keychain.hasToken(service: testService), "Should detect that token no longer exists")
        
        // Test retrieving deleted token throws error
        XCTAssertThrowsError(try keychain.getToken(service: testService)) { error in
            XCTAssertTrue(error is KeychainManager.KeychainError, "Should throw KeychainError")
        }
    }
    
    func testKeychainTokenUpdate() throws {
        let keychain = KeychainManager.shared
        let testService = "test-service"
        let originalToken = "original-token"
        let updatedToken = "updated-token"
        
        // Save original token
        try keychain.saveToken(service: testService, token: originalToken)
        
        // Update token
        try keychain.saveToken(service: testService, token: updatedToken)
        
        // Verify updated token is retrieved
        let retrievedToken = try keychain.getToken(service: testService)
        XCTAssertEqual(retrievedToken, updatedToken, "Should retrieve updated token")
        XCTAssertNotEqual(retrievedToken, originalToken, "Should not retrieve original token")
        
        // Clean up
        try keychain.deleteToken(service: testService)
    }
    
    func testKeychainConvenienceMethods() throws {
        let keychain = KeychainManager.shared
        let upToken = "up:yeah:test-token"
        let ynabToken = "ynab-test-token"
        
        // Test Up Banking token methods
        try keychain.saveUpBankingToken(upToken)
        let retrievedUpToken = try keychain.getUpBankingToken()
        XCTAssertEqual(retrievedUpToken, upToken)
        
        // Test YNAB token methods
        try keychain.saveYNABToken(ynabToken)
        let retrievedYnabToken = try keychain.getYNABToken()
        XCTAssertEqual(retrievedYnabToken, ynabToken)
        
        // Test hasAllTokens
        XCTAssertTrue(keychain.hasAllTokens(), "Should have all tokens")
        
        // Clean up
        try keychain.deleteToken(service: KeychainManager.upBankingService)
        try keychain.deleteToken(service: KeychainManager.ynabService)
        
        XCTAssertFalse(keychain.hasAllTokens(), "Should not have all tokens after cleanup")
    }
    
    // MARK: - ConfigManager Tests
    
    func testConfigurationSaveAndLoad() throws {
        let configManager = ConfigManager.shared
        
        // Create test configuration
        let testMapping = ConfigManager.AccountMapping(
            upAccountId: "test-up-account",
            upAccountName: "Test Up Account",
            upAccountType: "transactional",
            ynabAccountId: "test-ynab-account",
            ynabAccountName: "Test YNAB Account"
        )
        
        let testConfig = ConfigManager.Configuration(
            ynabBudgetId: "test-budget-id",
            accountMappings: [testMapping],
            categorizationSettings: nil
        )
        
        // Test saving configuration
        XCTAssertNoThrow(try configManager.saveConfiguration(testConfig))
        
        // Test loading configuration
        let loadedConfig = try configManager.loadConfiguration()
        XCTAssertEqual(loadedConfig.ynabBudgetId, testConfig.ynabBudgetId)
        XCTAssertEqual(loadedConfig.accountMappings.count, 1)
        XCTAssertEqual(loadedConfig.accountMappings.first?.upAccountId, testMapping.upAccountId)
        
        // Test hasConfiguration
        XCTAssertTrue(configManager.hasConfiguration())
        
        // Test validateConfiguration
        XCTAssertTrue(try configManager.validateConfiguration())
        
        // Clean up
        try configManager.clearConfiguration()
        XCTAssertFalse(configManager.hasConfiguration())
    }
    
    func testConfigurationAccountMappingOperations() throws {
        let configManager = ConfigManager.shared
        
        // Create initial configuration
        try configManager.addOrUpdateAccountMapping(
            upAccountId: "up-1",
            upAccountName: "Up Account 1",
            upAccountType: "transactional",
            ynabAccountId: "ynab-1",
            ynabAccountName: "YNAB Account 1",
            ynabBudgetId: "test-budget"
        )
        
        // Test getting account mapping
        let mapping = try configManager.getAccountMapping(for: "up-1")
        XCTAssertNotNil(mapping)
        XCTAssertEqual(mapping?.upAccountName, "Up Account 1")
        
        // Test getting all account mappings
        let allMappings = try configManager.getAllAccountMappings()
        XCTAssertEqual(allMappings.count, 1)
        
        // Test updating account mapping
        try configManager.addOrUpdateAccountMapping(
            upAccountId: "up-1",
            upAccountName: "Updated Up Account 1",
            upAccountType: "transactional",
            ynabAccountId: "ynab-1",
            ynabAccountName: "Updated YNAB Account 1",
            ynabBudgetId: "test-budget"
        )
        
        let updatedMapping = try configManager.getAccountMapping(for: "up-1")
        XCTAssertEqual(updatedMapping?.upAccountName, "Updated Up Account 1")
        
        // Test removing account mapping
        try configManager.removeAccountMapping(upAccountId: "up-1")
        let removedMapping = try configManager.getAccountMapping(for: "up-1")
        XCTAssertNil(removedMapping)
        
        // Clean up
        try configManager.clearConfiguration()
    }
    
    // MARK: - Logger Tests
    
    func testLoggerLevels() throws {
        let logger = Logger.shared
        
        // Test that logging methods don't throw
        XCTAssertNoThrow(logger.debug("Debug message"))
        XCTAssertNoThrow(logger.info("Info message"))
        XCTAssertNoThrow(logger.warning("Warning message"))
        XCTAssertNoThrow(logger.error("Error message"))
        
        // Test convenience logging methods
        XCTAssertNoThrow(logger.logSyncStart(dateRange: "2024-01-01 to 2024-01-02"))
        XCTAssertNoThrow(logger.logSyncComplete(summary: "Test summary"))
        XCTAssertNoThrow(logger.logAPICall(service: "Test", endpoint: "/test"))
        XCTAssertNoThrow(logger.logDatabaseOperation("INSERT", table: "test_table"))
        XCTAssertNoThrow(logger.logAmountConversion(upAmount: 1234, ynabAmount: 12340))
    }
    
    // MARK: - Date and Formatting Tests
    
    func testDateFormatting() throws {
        let testDate = Date(timeIntervalSince1970: 1640995200) // 2022-01-01 00:00:00 UTC
        
        // Test Up Banking API string formatting
        let upString = testDate.upBankingAPIString()
        XCTAssertFalse(upString.isEmpty, "Up Banking API string should not be empty")
        
        // Test parsing Up Banking API string
        let parsedDate = upString.upBankingAPIDate()
        XCTAssertNotNil(parsedDate, "Should be able to parse Up Banking API date string")
        
        // Test that parsed date is close to original (allowing for timezone differences)
        if let parsedDate = parsedDate {
            let timeDifference = abs(testDate.timeIntervalSince(parsedDate))
            XCTAssertLessThan(timeDifference, 1.0, "Parsed date should be within 1 second of original")
        }
    }
    
    func testNumberFormatting() throws {
        let currencyFormatter = NumberFormatter.currency
        
        // Test currency formatting
        let testAmount = NSNumber(value: 123.45)
        let formattedAmount = currencyFormatter.string(from: testAmount)
        XCTAssertNotNil(formattedAmount, "Should format currency amount")
        XCTAssertTrue(formattedAmount?.contains("123") == true, "Should contain amount")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorTypes() throws {
        // Test KeychainManager errors
        let keychainError = KeychainManager.KeychainError.tokenNotFound
        XCTAssertNotNil(keychainError.errorDescription)
        
        // Test ConfigManager errors
        let configError = ConfigManager.ConfigError.configurationNotFound
        XCTAssertNotNil(configError.errorDescription)
        
        // Test CLI errors
        let cliError = CLIError.invalidInput("test")
        XCTAssertNotNil(cliError.errorDescription)
    }
    
    // MARK: - Performance Tests
    
    func testConfigurationPerformance() throws {
        let configManager = ConfigManager.shared
        
        // Create a configuration with multiple mappings
        let mappings = (1...10).map { index in
            ConfigManager.AccountMapping(
                upAccountId: "up-\(index)",
                upAccountName: "Up Account \(index)",
                upAccountType: "transactional",
                ynabAccountId: "ynab-\(index)",
                ynabAccountName: "YNAB Account \(index)"
            )
        }
        
        let config = ConfigManager.Configuration(
            ynabBudgetId: "test-budget",
            accountMappings: mappings,
            categorizationSettings: nil
        )
        
        // Test save/load performance
        measure {
            try! configManager.saveConfiguration(config)
            let _ = try! configManager.loadConfiguration()
        }
        
        // Clean up
        try configManager.clearConfiguration()
    }
}