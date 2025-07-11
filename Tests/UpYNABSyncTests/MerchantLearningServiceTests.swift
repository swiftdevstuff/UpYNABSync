import XCTest
@testable import UpYNABSync

final class MerchantLearningServiceTests: XCTestCase {
    var merchantService: MerchantLearningService!
    var testDatabase: SyncDatabase!
    
    override func setUp() {
        super.setUp()
        merchantService = MerchantLearningService.shared
        testDatabase = SyncDatabase.shared
    }
    
    override func tearDown() {
        super.tearDown()
        merchantService = nil
        testDatabase = nil
    }
    
    func testMerchantPatternExtraction() {
        let testCases = [
            ("CARD PURCHASE COLES 1234 SYDNEY", "COLES"),
            ("EFTPOS WOOLWORTHS BONDI", "WOOLWORTHS"),
            ("VISA MCDONALD'S AUSTRALIA", "MCDONALD'S"),
            ("PAYPAL NETFLIX", "NETFLIX"),
            ("SHELL PETROL STATION 12345", "SHELL"),
            ("BUNNINGS WAREHOUSE 9876", "BUNNINGS"),
            ("Simple Description", "SIMPLE")
        ]
        
        for (input, expected) in testCases {
            let transaction = createMockTransaction(description: input)
            let pattern = merchantService.extractMerchantPattern(from: transaction)
            XCTAssertEqual(pattern, expected, "Pattern extraction failed for input: \(input)")
        }
    }
    
    func testMerchantPatternExtractionWithRawText() {
        let transaction = createMockTransaction(
            description: "CARD PURCHASE",
            rawText: "CARD PURCHASE COLES SUPERMARKET SYDNEY 1234"
        )
        let pattern = merchantService.extractMerchantPattern(from: transaction)
        XCTAssertEqual(pattern, "COLES")
    }
    
    func testCreateMerchantRule() {
        let pattern = "TESTMERCHANT"
        let categoryId = "test-category-id"
        let categoryName = "Test Category"
        let payeeName = "Test Merchant"
        
        XCTAssertNoThrow(try merchantService.createMerchantRule(
            pattern: pattern,
            categoryId: categoryId,
            categoryName: categoryName,
            payeeName: payeeName,
            confidence: 0.95
        ))
    }
    
    func testCreateMerchantRuleWithEmptyPattern() {
        let pattern = ""
        let categoryId = "test-category-id"
        let categoryName = "Test Category"
        let payeeName = "Test Merchant"
        
        XCTAssertThrowsError(try merchantService.createMerchantRule(
            pattern: pattern,
            categoryId: categoryId,
            categoryName: categoryName,
            payeeName: payeeName,
            confidence: 0.95
        )) { error in
            XCTAssertTrue(error is MerchantLearningService.MerchantLearningError)
        }
    }
    
    func testCreateMerchantRuleWithEmptyCategoryId() {
        let pattern = "TESTMERCHANT"
        let categoryId = ""
        let categoryName = "Test Category"
        let payeeName = "Test Merchant"
        
        XCTAssertThrowsError(try merchantService.createMerchantRule(
            pattern: pattern,
            categoryId: categoryId,
            categoryName: categoryName,
            payeeName: payeeName,
            confidence: 0.95
        )) { error in
            XCTAssertTrue(error is MerchantLearningService.MerchantLearningError)
        }
    }
    
    func testGetMerchantRuleExactMatch() {
        let pattern = "TESTMERCHANT"
        let categoryId = "test-category-id"
        let categoryName = "Test Category"
        let payeeName = "Test Merchant"
        
        do {
            try merchantService.createMerchantRule(
                pattern: pattern,
                categoryId: categoryId,
                categoryName: categoryName,
                payeeName: payeeName,
                confidence: 0.95
            )
            
            let transaction = createMockTransaction(description: pattern)
            let rule = try merchantService.getMerchantRule(for: transaction)
            
            XCTAssertNotNil(rule)
            XCTAssertEqual(rule?.merchantPattern, pattern.uppercased())
            XCTAssertEqual(rule?.categoryId, categoryId)
            XCTAssertEqual(rule?.categoryName, categoryName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetMerchantRuleNoMatch() {
        let transaction = createMockTransaction(description: "NONEXISTENTMERCHANT")
        
        do {
            let rule = try merchantService.getMerchantRule(for: transaction)
            XCTAssertNil(rule)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGetAllMerchantRules() {
        let pattern1 = "TESTMERCHANT1"
        let pattern2 = "TESTMERCHANT2"
        let categoryId = "test-category-id"
        let categoryName = "Test Category"
        let payeeName = "Test Merchant"
        
        do {
            try merchantService.createMerchantRule(
                pattern: pattern1,
                categoryId: categoryId,
                categoryName: categoryName,
                payeeName: payeeName,
                confidence: 0.95
            )
            
            try merchantService.createMerchantRule(
                pattern: pattern2,
                categoryId: categoryId,
                categoryName: categoryName,
                payeeName: payeeName,
                confidence: 0.85
            )
            
            let rules = try merchantService.getAllMerchantRules()
            XCTAssertGreaterThanOrEqual(rules.count, 2)
            
            let patterns = rules.map { $0.merchantPattern }
            XCTAssertTrue(patterns.contains(pattern1.uppercased()))
            XCTAssertTrue(patterns.contains(pattern2.uppercased()))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testMerchantRuleStats() {
        do {
            let stats = try merchantService.getMerchantRuleStats()
            XCTAssertNotNil(stats["total_rules"])
            XCTAssertNotNil(stats["used_rules"])
            XCTAssertNotNil(stats["total_usage"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRecordCategorizationHistory() {
        let transactionId = "test-transaction-id"
        let merchantPattern = "TESTMERCHANT"
        let suggestedCategoryId = "suggested-category-id"
        let appliedCategoryId = "applied-category-id"
        
        XCTAssertNoThrow(try merchantService.recordCategorizationHistory(
            transactionId: transactionId,
            merchantPattern: merchantPattern,
            suggestedCategoryId: suggestedCategoryId,
            appliedCategoryId: appliedCategoryId,
            userAccepted: true,
            confidence: 0.85
        ))
    }
    
    // MARK: - Helper Methods
    
    private func createMockTransaction(description: String, rawText: String? = nil) -> UpTransaction {
        return UpTransaction(
            id: UUID().uuidString,
            status: "SETTLED",
            rawText: rawText ?? description,
            description: description,
            message: nil,
            holdInfo: nil,
            roundUp: nil,
            cashback: nil,
            amount: UpAmount(
                currencyCode: "AUD",
                value: "10.00",
                valueInBaseUnits: 1000
            ),
            foreignAmount: nil,
            settledAt: Date(),
            createdAt: Date(),
            relationships: UpTransactionRelationships(
                account: UpRelationshipData(data: nil),
                transferAccount: nil,
                category: nil,
                parentCategory: nil,
                tags: nil
            )
        )
    }
}