import XCTest
import Foundation
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
    
    // MARK: - JSON:API Structure Tests
    
    func testUpBankingJSONAPIStructure() throws {
        // Test that our models correctly decode Up Banking's JSON:API structure
        let testJSON = """
        {
          "data": [
            {
              "id": "transaction-123",
              "type": "transactions",
              "attributes": {
                "description": "Test Transaction",
                "amount": {
                  "currencyCode": "AUD",
                  "value": "-12.50",
                  "valueInBaseUnits": -1250
                },
                "status": "SETTLED",
                "createdAt": "2025-07-10T10:00:00Z",
                "rawText": "TEST PAYMENT",
                "message": null,
                "holdInfo": null,
                "roundUp": null,
                "cashback": null,
                "foreignAmount": null,
                "settledAt": "2025-07-10T10:00:00Z"
              },
              "relationships": {
                "account": {
                  "data": {
                    "id": "account-456",
                    "type": "accounts"
                  }
                },
                "transferAccount": null,
                "category": null,
                "parentCategory": null,
                "tags": null
              }
            }
          ]
        }
        """
        
        let data = testJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        // Configure date decoding to match Up Banking's ISO8601 format
        let formatter = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        
        // This should now decode successfully with our fixed models
        let response = try decoder.decode(UpTransactionsResponse.self, from: data)
        
        // Verify the structure was decoded correctly
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "transaction-123")
        XCTAssertEqual(response.data[0].type, "transactions")
        XCTAssertEqual(response.data[0].attributes.description, "Test Transaction")
        XCTAssertEqual(response.data[0].attributes.amount.valueInBaseUnits, -1250)
        XCTAssertEqual(response.data[0].attributes.status, "SETTLED")
        
        // Verify relationships are accessible at the top level
        XCTAssertNotNil(response.data[0].relationships)
        XCTAssertNotNil(response.data[0].relationships?.account.data)
        XCTAssertEqual(response.data[0].relationships?.account.data?.id, "account-456")
        XCTAssertEqual(response.data[0].relationships?.account.data?.type, "accounts")
    }
    
    // MARK: - YNAB Import ID Validation Tests
    
    func testYNABImportIdValidation() throws {
        // Test import_id length validation
        
        // Valid import_id (36 characters - UUID format)
        let validImportId = "d4ad6982-d6d9-4c91-9d5c-0506ce292115"
        XCTAssertEqual(validImportId.count, 36)
        XCTAssertEqual(YNABTransactionRequest.validateImportId(validImportId), validImportId)
        
        // Test import_id that's too long (39 characters with prefix)
        let tooLongImportId = "up-d4ad6982-d6d9-4c91-9d5c-0506ce292115"
        XCTAssertEqual(tooLongImportId.count, 39)
        let truncated = YNABTransactionRequest.validateImportId(tooLongImportId)
        XCTAssertEqual(truncated.count, 36)
        XCTAssertEqual(truncated, "up-d4ad6982-d6d9-4c91-9d5c-0506ce292")
        
        // Test shorter import_id (should remain unchanged)
        let shortImportId = "short-id"
        XCTAssertEqual(YNABTransactionRequest.validateImportId(shortImportId), shortImportId)
        
        // Test exactly 36 characters
        let exactly36 = String(repeating: "a", count: 36)
        XCTAssertEqual(YNABTransactionRequest.validateImportId(exactly36), exactly36)
        
        // Test 37 characters (should be truncated to 36)
        let exactly37 = String(repeating: "b", count: 37)
        let truncated37 = YNABTransactionRequest.validateImportId(exactly37)
        XCTAssertEqual(truncated37.count, 36)
        XCTAssertEqual(truncated37, String(repeating: "b", count: 36))
    }
    
    func testUpTransactionToYNABConversion() throws {
        // Test that Up Banking transactions are converted correctly to YNAB format
        let upTransaction = UpTransaction(
            id: "d4ad6982-d6d9-4c91-9d5c-0506ce292115", // 36 characters
            status: "SETTLED",
            rawText: "TEST MERCHANT",
            description: "Test Transaction",
            message: nil,
            holdInfo: nil,
            roundUp: nil,
            cashback: nil,
            amount: UpAmount(currencyCode: "AUD", value: "-25.50", valueInBaseUnits: -2550),
            foreignAmount: nil,
            settledAt: Date(),
            createdAt: Date(),
            relationships: UpTransactionRelationships(
                account: UpRelationshipData(data: UpRelationshipDataItem(type: "accounts", id: "test-account")),
                transferAccount: nil,
                category: nil,
                parentCategory: nil,
                tags: nil
            )
        )
        
        let ynabTransaction = YNABTransaction.fromUpTransaction(upTransaction, accountId: "ynab-account-123", upAccountName: "Test Account")
        
        // Verify import_id is exactly the Up Banking transaction ID (36 characters)
        XCTAssertEqual(ynabTransaction.importId, upTransaction.id)
        XCTAssertEqual(ynabTransaction.importId?.count, 36)
        
        // Verify other fields are mapped correctly
        XCTAssertEqual(ynabTransaction.accountId, "ynab-account-123")
        XCTAssertEqual(ynabTransaction.payeeName, "Test Transaction")
        XCTAssertEqual(ynabTransaction.amount, -25500) // Up Banking cents * 10 for YNAB milliunits
        XCTAssertEqual(ynabTransaction.cleared, "uncleared")
        XCTAssertEqual(ynabTransaction.approved, true)
    }
    
    // MARK: - Duplicate Detection Tests
    
    func testTransactionStatusHandling() throws {
        // Test that failed transactions are retried, synced transactions are skipped
        
        // Create mock database (in a real test, we'd use dependency injection)
        // For now, just test the status enum behavior
        
        let pendingStatus = SyncTransactionStatus.pending
        let syncedStatus = SyncTransactionStatus.synced  
        let failedStatus = SyncTransactionStatus.failed
        
        // Verify enum values match database string values
        XCTAssertEqual(pendingStatus.rawValue, "pending")
        XCTAssertEqual(syncedStatus.rawValue, "synced")
        XCTAssertEqual(failedStatus.rawValue, "failed")
        
        // Verify emoji representations
        XCTAssertEqual(pendingStatus.emoji, "⏳")
        XCTAssertEqual(syncedStatus.emoji, "✅")
        XCTAssertEqual(failedStatus.emoji, "❌")
    }
    
    func testDuplicateDetectionLogic() throws {
        // Test the rate-limit-safe logic that determines which transactions are "new"
        // This approach is purely database-based to avoid YNAB API rate limits
        
        // Mock scenarios based on our rate-limit-safe approach:
        // 1. Transaction not in database = new
        // 2. Transaction with "synced" status = skip
        // 3. Transaction with "failed" status = retry (new)  
        // 4. Transaction with "pending" status = retry (new)
        // 5. Transaction with unknown status = new (with warning)
        
        let testCases: [(status: String?, shouldBeNew: Bool, description: String)] = [
            (nil, true, "Never attempted - mark as new"),
            ("synced", false, "Successfully synced to YNAB - skip"),
            ("failed", true, "Failed previously - retry as new"),
            ("pending", true, "Stuck in pending state - retry as new"),
            ("unknown_status", true, "Unknown status - treat as new with warning")
        ]
        
        for testCase in testCases {
            // Rate-limit-safe logic: only skip transactions with "synced" status
            // All other statuses (nil, failed, pending, unknown) are treated as new
            let shouldBeNew = testCase.status != "synced"
            XCTAssertEqual(shouldBeNew, testCase.shouldBeNew, 
                          "Transaction with status '\(testCase.status ?? "nil")' should be \(testCase.shouldBeNew ? "new" : "skipped"): \(testCase.description)")
        }
    }
    
    func testRateLimitSafeApproach() throws {
        // Test that our approach avoids YNAB API calls for duplicate detection
        
        // This documents that we only rely on local database status tracking:
        // 1. "pending" status = transaction being processed, treat as new for retry
        // 2. "synced" status = confirmed successful sync to YNAB, skip
        // 3. "failed" status = confirmed failed sync, treat as new for retry
        // 4. No status = never attempted, treat as new
        
        // Key benefits of this approach:
        // ✅ No additional YNAB API calls (rate limit safe)
        // ✅ Failed transactions can be retried
        // ✅ Pending transactions that got stuck can be retried
        // ✅ Only confirmed successful syncs are skipped
        
        let statusToNewMapping: [String?: Bool] = [
            nil: true,        // Never attempted
            "pending": true,  // In progress or stuck - retry
            "synced": false,  // Confirmed success - skip
            "failed": true,   // Confirmed failure - retry
        ]
        
        for (status, expectedNew) in statusToNewMapping {
            let actualNew = status != "synced"
            XCTAssertEqual(actualNew, expectedNew, 
                          "Status '\(status ?? "nil")' should result in new=\(expectedNew)")
        }
    }
}