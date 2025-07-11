import XCTest
@testable import UpYNABSync

final class YNABPatternAnalyzerTests: XCTestCase {
    var patternAnalyzer: YNABPatternAnalyzer!
    
    override func setUp() {
        super.setUp()
        patternAnalyzer = YNABPatternAnalyzer.shared
    }
    
    override func tearDown() {
        super.tearDown()
        patternAnalyzer = nil
    }
    
    func testSuggestMerchantRulesWithHighConfidence() {
        let patterns = [
            CategoryPattern(
                merchantPattern: "COLES",
                categoryId: "groceries-id",
                categoryName: "Groceries",
                confidence: 0.95,
                transactionCount: 10,
                isWorthSuggesting: true
            ),
            CategoryPattern(
                merchantPattern: "SHELL",
                categoryId: "fuel-id",
                categoryName: "Fuel",
                confidence: 0.85,
                transactionCount: 5,
                isWorthSuggesting: true
            ),
            CategoryPattern(
                merchantPattern: "LOWCONFIDENCE",
                categoryId: "misc-id",
                categoryName: "Miscellaneous",
                confidence: 0.50,
                transactionCount: 2,
                isWorthSuggesting: false
            )
        ]
        
        let suggestions = patternAnalyzer.suggestMerchantRules(
            from: patterns,
            confidenceThreshold: 0.7
        )
        
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions[0].pattern.merchantPattern, "COLES")
        XCTAssertEqual(suggestions[1].pattern.merchantPattern, "SHELL")
        XCTAssertTrue(suggestions[0].shouldAutoApprove)
        XCTAssertFalse(suggestions[1].shouldAutoApprove)
    }
    
    func testSuggestMerchantRulesWithLowConfidence() {
        let patterns = [
            CategoryPattern(
                merchantPattern: "UNKNOWN",
                categoryId: "misc-id",
                categoryName: "Miscellaneous",
                confidence: 0.45,
                transactionCount: 1,
                isWorthSuggesting: false
            )
        ]
        
        let suggestions = patternAnalyzer.suggestMerchantRules(
            from: patterns,
            confidenceThreshold: 0.7
        )
        
        XCTAssertEqual(suggestions.count, 0)
    }
    
    func testSuggestMerchantRulesEmpty() {
        let patterns: [CategoryPattern] = []
        
        let suggestions = patternAnalyzer.suggestMerchantRules(
            from: patterns,
            confidenceThreshold: 0.7
        )
        
        XCTAssertEqual(suggestions.count, 0)
    }
    
    func testSuggestMerchantRulesSorting() {
        let patterns = [
            CategoryPattern(
                merchantPattern: "MEDIUM",
                categoryId: "misc-id",
                categoryName: "Miscellaneous",
                confidence: 0.75,
                transactionCount: 3,
                isWorthSuggesting: true
            ),
            CategoryPattern(
                merchantPattern: "HIGH",
                categoryId: "groceries-id",
                categoryName: "Groceries",
                confidence: 0.95,
                transactionCount: 10,
                isWorthSuggesting: true
            ),
            CategoryPattern(
                merchantPattern: "LOW",
                categoryId: "fuel-id",
                categoryName: "Fuel",
                confidence: 0.72,
                transactionCount: 2,
                isWorthSuggesting: true
            )
        ]
        
        let suggestions = patternAnalyzer.suggestMerchantRules(
            from: patterns,
            confidenceThreshold: 0.7
        )
        
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions[0].pattern.merchantPattern, "HIGH")
        XCTAssertEqual(suggestions[1].pattern.merchantPattern, "MEDIUM")
        XCTAssertEqual(suggestions[2].pattern.merchantPattern, "LOW")
    }
    
    func testAutoApprovalLogic() {
        let highConfidenceHighCount = CategoryPattern(
            merchantPattern: "COLES",
            categoryId: "groceries-id",
            categoryName: "Groceries",
            confidence: 0.95,
            transactionCount: 5,
            isWorthSuggesting: true
        )
        
        let highConfidenceLowCount = CategoryPattern(
            merchantPattern: "SHELL",
            categoryId: "fuel-id",
            categoryName: "Fuel",
            confidence: 0.95,
            transactionCount: 2,
            isWorthSuggesting: true
        )
        
        let lowConfidenceHighCount = CategoryPattern(
            merchantPattern: "UNKNOWN",
            categoryId: "misc-id",
            categoryName: "Miscellaneous",
            confidence: 0.85,
            transactionCount: 5,
            isWorthSuggesting: true
        )
        
        let patterns = [highConfidenceHighCount, highConfidenceLowCount, lowConfidenceHighCount]
        
        let suggestions = patternAnalyzer.suggestMerchantRules(
            from: patterns,
            confidenceThreshold: 0.7
        )
        
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertTrue(suggestions[0].shouldAutoApprove)
        XCTAssertFalse(suggestions[1].shouldAutoApprove)
        XCTAssertFalse(suggestions[2].shouldAutoApprove)
    }
    
    func testCategoryPatternValidation() {
        let validPattern = CategoryPattern(
            merchantPattern: "COLES",
            categoryId: "groceries-id",
            categoryName: "Groceries",
            confidence: 0.95,
            transactionCount: 5,
            isWorthSuggesting: true
        )
        
        XCTAssertEqual(validPattern.merchantPattern, "COLES")
        XCTAssertEqual(validPattern.categoryId, "groceries-id")
        XCTAssertEqual(validPattern.categoryName, "Groceries")
        XCTAssertEqual(validPattern.confidence, 0.95)
        XCTAssertEqual(validPattern.transactionCount, 5)
        XCTAssertTrue(validPattern.isWorthSuggesting)
    }
    
    func testMerchantRuleSuggestionValidation() {
        let pattern = CategoryPattern(
            merchantPattern: "COLES",
            categoryId: "groceries-id",
            categoryName: "Groceries",
            confidence: 0.95,
            transactionCount: 5,
            isWorthSuggesting: true
        )
        
        let suggestion = MerchantRuleSuggestion(
            pattern: pattern,
            description: "Test description",
            shouldAutoApprove: true
        )
        
        XCTAssertEqual(suggestion.pattern.merchantPattern, "COLES")
        XCTAssertEqual(suggestion.description, "Test description")
        XCTAssertTrue(suggestion.shouldAutoApprove)
    }
}