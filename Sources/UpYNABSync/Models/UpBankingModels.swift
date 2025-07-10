import Foundation

// MARK: - Up Banking API Models

struct UpAccount: Codable {
    let id: String
    let displayName: String
    let accountType: String
    let balance: UpAmount
    let createdAt: Date
    let ownershipType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case accountType
        case balance
        case createdAt
        case ownershipType
    }
    
    var isTransactionAccount: Bool {
        return accountType == "TRANSACTIONAL"
    }
    
    var isSaverAccount: Bool {
        return accountType == "SAVER"
    }
}

struct UpAccountAttributes: Codable {
    let accountType: String
    let balance: UpAmount
    let createdAt: Date
    let displayName: String
    let ownershipType: String?
    
    enum CodingKeys: String, CodingKey {
        case accountType
        case balance
        case createdAt
        case displayName
        case ownershipType
    }
}

struct UpTransaction: Codable {
    let id: String
    let status: String
    let rawText: String?
    let description: String
    let message: String?
    let holdInfo: UpHoldInfo?
    let roundUp: UpRoundUp?
    let cashback: UpCashback?
    let amount: UpAmount
    let foreignAmount: UpAmount?
    let settledAt: Date?
    let createdAt: Date
    let relationships: UpTransactionRelationships
    
    enum CodingKeys: String, CodingKey {
        case id
        case status
        case rawText
        case description
        case message
        case holdInfo
        case roundUp
        case cashback
        case amount
        case foreignAmount
        case settledAt
        case createdAt
        case relationships
    }
    
    var isSettled: Bool {
        return status == "SETTLED"
    }
    
    var displayDescription: String {
        return description.isEmpty ? (rawText ?? "Unknown transaction") : description
    }
}

struct UpTransactionAttributes: Codable {
    let status: String
    let rawText: String?
    let description: String
    let message: String?
    let holdInfo: UpHoldInfo?
    let roundUp: UpRoundUp?
    let cashback: UpCashback?
    let amount: UpAmount
    let foreignAmount: UpAmount?
    let settledAt: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case status
        case rawText
        case description
        case message
        case holdInfo
        case roundUp
        case cashback
        case amount
        case foreignAmount
        case settledAt
        case createdAt
    }
}

struct UpHoldInfo: Codable {
    let amount: UpAmount
    let foreignAmount: UpAmount?
}

struct UpRoundUp: Codable {
    let amount: UpAmount
    let boostPortion: UpAmount?
}

struct UpCashback: Codable {
    let amount: UpAmount
    let description: String
}

struct UpTransactionRelationships: Codable {
    let account: UpRelationshipData
    let transferAccount: UpRelationshipData?
    let category: UpRelationshipData?
    let parentCategory: UpRelationshipData?
    let tags: UpRelationshipDataArray?
    
    enum CodingKeys: String, CodingKey {
        case account
        case transferAccount
        case category
        case parentCategory
        case tags
    }
}

struct UpRelationshipData: Codable {
    let data: UpRelationshipDataItem?
}

struct UpRelationshipDataArray: Codable {
    let data: [UpRelationshipDataItem]?
}

struct UpRelationshipDataItem: Codable {
    let type: String
    let id: String
}

struct UpAmount: Codable {
    let currencyCode: String
    let value: String
    let valueInBaseUnits: Int
    
    enum CodingKeys: String, CodingKey {
        case currencyCode
        case value
        case valueInBaseUnits
    }
    
    var doubleValue: Double {
        return Double(valueInBaseUnits) / 100.0
    }
    
    var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: doubleValue)) ?? value
    }
}

// MARK: - Up Banking API Response Wrappers

struct UpAccountsResponse: Codable {
    let data: [UpAccountData]
    let links: UpLinks?
    
    struct UpAccountData: Codable {
        let type: String
        let id: String
        let attributes: UpAccountAttributes
    }
}

struct UpTransactionsResponse: Codable {
    let data: [UpTransactionData]
    let links: UpLinks?
    
    struct UpTransactionData: Codable {
        let type: String
        let id: String
        let attributes: UpTransactionAttributes
        let relationships: UpTransactionRelationships?
    }
}

struct UpLinks: Codable {
    let prev: String?
    let next: String?
}

struct UpPingResponse: Codable {
    let meta: UpPingMeta
    
    struct UpPingMeta: Codable {
        let id: String
        let statusEmoji: String
    }
}

struct UpErrorResponse: Codable {
    let errors: [UpError]
    
    struct UpError: Codable {
        let status: String
        let title: String
        let detail: String
        let source: UpErrorSource?
    }
    
    struct UpErrorSource: Codable {
        let parameter: String?
        let pointer: String?
    }
}

// MARK: - Amount Conversion Functions

extension UpAmount {
    func toYNABAmount() -> Int {
        return valueInBaseUnits * 10
    }
    
    func validateYNABConversion(_ ynabAmount: Int) -> Bool {
        return toYNABAmount() == ynabAmount
    }
}

// MARK: - Date Helpers

extension Date {
    func upBankingAPIString() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

extension String {
    func upBankingAPIDate() -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: self)
    }
}