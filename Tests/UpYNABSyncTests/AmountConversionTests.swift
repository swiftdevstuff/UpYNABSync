import XCTest
@testable import UpYNABSync

final class AmountConversionTests: XCTestCase {
    
    // MARK: - Critical Amount Conversion Tests
    // These tests are essential as per PDS: "money errors are unacceptable"
    
    func testUpAmountToYNABConversion() throws {
        // Test various amounts to ensure accurate conversion
        let testCases: [(cents: Int, expected: Int, description: String)] = [
            (1234, 12340, "$12.34"),
            (100, 1000, "$1.00"),
            (1, 10, "$0.01"),
            (0, 0, "$0.00"),
            (999999, 9999990, "$9999.99"),
            (50, 500, "$0.50"),
            (123456, 1234560, "$1234.56")
        ]
        
        for testCase in testCases {
            let upAmount = UpAmount(
                currencyCode: "AUD",
                value: String(format: "%.2f", Double(testCase.cents) / 100.0),
                valueInBaseUnits: testCase.cents
            )
            
            let ynabAmount = upAmount.toYNABAmount()
            
            XCTAssertEqual(
                ynabAmount,
                testCase.expected,
                "Failed conversion for \(testCase.description): \(testCase.cents) cents should convert to \(testCase.expected) milliunits, got \(ynabAmount)"
            )
        }
    }
    
    func testAmountConversionValidation() throws {
        // Test the validation function that ensures conversions are correct
        let testCases: [(cents: Int, milliunits: Int, shouldBeValid: Bool)] = [
            (1234, 12340, true),   // Correct conversion
            (1234, 12341, false),  // Incorrect conversion
            (100, 1000, true),     // Correct conversion
            (100, 999, false),     // Incorrect conversion
            (0, 0, true),          // Zero case
            (1, 10, true),         // Minimum positive amount
            (1, 11, false)         // Incorrect minimum amount
        ]
        
        for testCase in testCases {
            let upAmount = UpAmount(
                currencyCode: "AUD",
                value: String(format: "%.2f", Double(testCase.cents) / 100.0),
                valueInBaseUnits: testCase.cents
            )
            
            let isValid = upAmount.validateYNABConversion(testCase.milliunits)
            
            XCTAssertEqual(
                isValid,
                testCase.shouldBeValid,
                "Validation failed for \(testCase.cents) cents vs \(testCase.milliunits) milliunits"
            )
        }
    }
    
    func testNegativeAmounts() throws {
        // Test negative amounts (for refunds, credits, etc.)
        let testCases: [(cents: Int, expected: Int)] = [
            (-1234, -12340),
            (-100, -1000),
            (-1, -10)
        ]
        
        for testCase in testCases {
            let upAmount = UpAmount(
                currencyCode: "AUD",
                value: String(format: "%.2f", Double(testCase.cents) / 100.0),
                valueInBaseUnits: testCase.cents
            )
            
            let ynabAmount = upAmount.toYNABAmount()
            
            XCTAssertEqual(
                ynabAmount,
                testCase.expected,
                "Failed negative amount conversion: \(testCase.cents) cents should convert to \(testCase.expected) milliunits, got \(ynabAmount)"
            )
        }
    }
    
    func testLargeAmounts() throws {
        // Test large amounts to ensure no overflow issues
        let testCases: [(cents: Int, expected: Int)] = [
            (1000000, 10000000),     // $10,000
            (10000000, 100000000),   // $100,000
            (100000000, 1000000000)  // $1,000,000
        ]
        
        for testCase in testCases {
            let upAmount = UpAmount(
                currencyCode: "AUD",
                value: String(format: "%.2f", Double(testCase.cents) / 100.0),
                valueInBaseUnits: testCase.cents
            )
            
            let ynabAmount = upAmount.toYNABAmount()
            
            XCTAssertEqual(
                ynabAmount,
                testCase.expected,
                "Failed large amount conversion: \(testCase.cents) cents should convert to \(testCase.expected) milliunits, got \(ynabAmount)"
            )
        }
    }
    
    func testDoubleValueConversion() throws {
        // Test the doubleValue property for display purposes
        let testCases: [(cents: Int, expectedDouble: Double)] = [
            (1234, 12.34),
            (100, 1.00),
            (1, 0.01),
            (0, 0.00),
            (50, 0.50)
        ]
        
        for testCase in testCases {
            let upAmount = UpAmount(
                currencyCode: "AUD",
                value: String(format: "%.2f", Double(testCase.cents) / 100.0),
                valueInBaseUnits: testCase.cents
            )
            
            XCTAssertEqual(
                upAmount.doubleValue,
                testCase.expectedDouble,
                accuracy: 0.001,
                "Failed double value conversion: \(testCase.cents) cents should convert to \(testCase.expectedDouble), got \(upAmount.doubleValue)"
            )
        }
    }
    
    // MARK: - Edge Cases
    
    func testEdgeCases() throws {
        // Test edge cases that could cause issues
        
        // Test zero amount
        let zeroAmount = UpAmount(currencyCode: "AUD", value: "0.00", valueInBaseUnits: 0)
        XCTAssertEqual(zeroAmount.toYNABAmount(), 0)
        XCTAssertTrue(zeroAmount.validateYNABConversion(0))
        
        // Test one cent
        let oneCent = UpAmount(currencyCode: "AUD", value: "0.01", valueInBaseUnits: 1)
        XCTAssertEqual(oneCent.toYNABAmount(), 10)
        XCTAssertTrue(oneCent.validateYNABConversion(10))
    }
    
    // MARK: - Performance Tests
    
    func testConversionPerformance() throws {
        // Ensure conversion is fast enough for bulk operations
        let amount = UpAmount(currencyCode: "AUD", value: "123.45", valueInBaseUnits: 12345)
        
        measure {
            for _ in 0..<10000 {
                let _ = amount.toYNABAmount()
            }
        }
    }
    
    func testValidationPerformance() throws {
        // Ensure validation is fast enough for bulk operations
        let amount = UpAmount(currencyCode: "AUD", value: "123.45", valueInBaseUnits: 12345)
        let ynabAmount = 123450
        
        measure {
            for _ in 0..<10000 {
                let _ = amount.validateYNABConversion(ynabAmount)
            }
        }
    }
}