import Foundation

// MARK: - YNAB API Models

struct YNABBudget: Codable {
    let id: String
    let name: String
    let lastModifiedOn: Date?
    let firstMonth: String?
    let lastMonth: String?
    let dateFormat: YNABDateFormat?
    let currencyFormat: YNABCurrencyFormat?
    let accounts: [YNABAccount]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case lastModifiedOn = "last_modified_on"
        case firstMonth = "first_month"
        case lastMonth = "last_month"
        case dateFormat = "date_format"
        case currencyFormat = "currency_format"
        case accounts
    }
}

struct YNABAccount: Codable {
    let id: String
    let name: String
    let type: String
    let onBudget: Bool
    let closed: Bool
    let note: String?
    let balance: Int
    let clearedBalance: Int
    let unclearedBalance: Int
    let transferPayeeId: String?
    let directImportLinked: Bool?
    let directImportInError: Bool?
    let lastReconciledAt: Date?
    let debtOriginalBalance: Int?
    let debtInterestRates: [String: Double]?
    let debtMinimumPayments: [String: Int]?
    let debtEscrowAmounts: [String: Int]?
    let deleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case onBudget = "on_budget"
        case closed
        case note
        case balance
        case clearedBalance = "cleared_balance"
        case unclearedBalance = "uncleared_balance"
        case transferPayeeId = "transfer_payee_id"
        case directImportLinked = "direct_import_linked"
        case directImportInError = "direct_import_in_error"
        case lastReconciledAt = "last_reconciled_at"
        case debtOriginalBalance = "debt_original_balance"
        case debtInterestRates = "debt_interest_rates"
        case debtMinimumPayments = "debt_minimum_payments"
        case debtEscrowAmounts = "debt_escrow_amounts"
        case deleted
    }
    
    var formattedBalance: String {
        let dollars = Double(balance) / 1000.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }
    
    var isActive: Bool {
        return !closed && !deleted
    }
}

struct YNABTransaction: Codable {
    let id: String?
    let date: String
    let amount: Int
    let memo: String?
    let payeeName: String?
    let payeeId: String?
    let categoryId: String?
    let categoryName: String?
    let accountId: String
    let accountName: String?
    let transferAccountId: String?
    let transferTransactionId: String?
    let matchedTransactionId: String?
    let importId: String?
    let importPayeeName: String?
    let importPayeeNameOriginal: String?
    let debtTransactionType: String?
    let deleted: Bool
    let approved: Bool
    let flagColor: String?
    let flagName: String?
    let cleared: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case date
        case amount
        case memo
        case payeeName = "payee_name"
        case payeeId = "payee_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case accountId = "account_id"
        case accountName = "account_name"
        case transferAccountId = "transfer_account_id"
        case transferTransactionId = "transfer_transaction_id"
        case matchedTransactionId = "matched_transaction_id"
        case importId = "import_id"
        case importPayeeName = "import_payee_name"
        case importPayeeNameOriginal = "import_payee_name_original"
        case debtTransactionType = "debt_transaction_type"
        case deleted
        case approved
        case flagColor = "flag_color"
        case flagName = "flag_name"
        case cleared
    }
    
    var formattedAmount: String {
        let dollars = Double(amount) / 1000.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }
    
    var displayPayeeName: String {
        return payeeName ?? importPayeeName ?? "Unknown Payee"
    }
    
    var displayMemo: String {
        return memo ?? ""
    }
}

struct YNABTransactionRequest: Codable {
    let accountId: String
    let payeeName: String?
    let categoryId: String?
    let memo: String?
    let amount: Int
    let date: String
    let cleared: String
    let approved: Bool
    let flagColor: String?
    let importId: String?
    
    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case payeeName = "payee_name"
        case categoryId = "category_id"
        case memo
        case amount
        case date
        case cleared
        case approved
        case flagColor = "flag_color"
        case importId = "import_id"
    }
    
    init(accountId: String, payeeName: String?, memo: String?, amount: Int, date: String, importId: String? = nil) {
        self.accountId = accountId
        self.payeeName = payeeName
        self.categoryId = nil
        self.memo = memo
        self.amount = amount
        self.date = date
        self.cleared = "uncleared"
        self.approved = true
        self.flagColor = nil
        
        // Validate and truncate import_id to YNAB's 36-character limit
        if let importId = importId {
            self.importId = YNABTransactionRequest.validateImportId(importId)
        } else {
            self.importId = nil
        }
    }
    
    init(accountId: String, payeeName: String?, categoryId: String?, memo: String?, amount: Int, date: String, cleared: String, approved: Bool, flagColor: String?, importId: String? = nil) {
        self.accountId = accountId
        self.payeeName = payeeName
        self.categoryId = categoryId
        self.memo = memo
        self.amount = amount
        self.date = date
        self.cleared = cleared
        self.approved = approved
        self.flagColor = flagColor
        
        // Validate and truncate import_id to YNAB's 36-character limit
        if let importId = importId {
            self.importId = YNABTransactionRequest.validateImportId(importId)
        } else {
            self.importId = nil
        }
    }
    
    static func validateImportId(_ importId: String) -> String {
        // YNAB import_id has a maximum length of 36 characters
        if importId.count <= 36 {
            return importId
        } else {
            // If too long, use the first 36 characters
            // For UUIDs, this should preserve uniqueness
            let truncated = String(importId.prefix(36))
            Logger.shared.warning("Import ID truncated from \(importId.count) to 36 characters: \(importId) -> \(truncated)")
            return truncated
        }
    }
}

struct YNABDateFormat: Codable {
    let format: String
}

struct YNABCurrencyFormat: Codable {
    let isoCode: String
    let exampleFormat: String
    let decimalDigits: Int
    let decimalSeparator: String
    let symbolFirst: Bool
    let groupSeparator: String
    let currencySymbol: String
    let displaySymbol: Bool
    
    enum CodingKeys: String, CodingKey {
        case isoCode = "iso_code"
        case exampleFormat = "example_format"
        case decimalDigits = "decimal_digits"
        case decimalSeparator = "decimal_separator"
        case symbolFirst = "symbol_first"
        case groupSeparator = "group_separator"
        case currencySymbol = "currency_symbol"
        case displaySymbol = "display_symbol"
    }
}

// MARK: - YNAB API Response Wrappers

struct YNABBudgetsResponse: Codable {
    let data: YNABBudgetsData
    
    struct YNABBudgetsData: Codable {
        let budgets: [YNABBudget]
        let defaultBudget: YNABBudget?
        
        enum CodingKeys: String, CodingKey {
            case budgets
            case defaultBudget = "default_budget"
        }
    }
}

struct YNABBudgetResponse: Codable {
    let data: YNABBudgetData
    
    struct YNABBudgetData: Codable {
        let budget: YNABBudget
        let serverKnowledge: Int
        
        enum CodingKeys: String, CodingKey {
            case budget
            case serverKnowledge = "server_knowledge"
        }
    }
}

struct YNABAccountsResponse: Codable {
    let data: YNABAccountsData
    
    struct YNABAccountsData: Codable {
        let accounts: [YNABAccount]
        let serverKnowledge: Int
        
        enum CodingKeys: String, CodingKey {
            case accounts
            case serverKnowledge = "server_knowledge"
        }
    }
}

struct YNABTransactionsResponse: Codable {
    let data: YNABTransactionsData
    
    struct YNABTransactionsData: Codable {
        let transactions: [YNABTransaction]
        let serverKnowledge: Int
        
        enum CodingKeys: String, CodingKey {
            case transactions
            case serverKnowledge = "server_knowledge"
        }
    }
}

struct YNABTransactionCreateResponse: Codable {
    let data: YNABTransactionCreateData
    
    struct YNABTransactionCreateData: Codable {
        let transaction: YNABTransaction?
        let transactions: [YNABTransaction]?
        let duplicateImportIds: [String]?
        let serverKnowledge: Int
        
        enum CodingKeys: String, CodingKey {
            case transaction
            case transactions
            case duplicateImportIds = "duplicate_import_ids"
            case serverKnowledge = "server_knowledge"
        }
    }
}

struct YNABTransactionsBulkRequest: Codable {
    let transactions: [YNABTransactionRequest]
}

struct YNABErrorResponse: Codable {
    let error: YNABErrorDetail
    
    struct YNABErrorDetail: Codable {
        let id: String
        let name: String
        let description: String
        let detail: String?
    }
}

struct YNABUserResponse: Codable {
    let data: YNABUserData
    
    struct YNABUserData: Codable {
        let user: YNABUser
    }
}

struct YNABUser: Codable {
    let id: String
}

struct YNABCategory: Codable {
    let id: String
    let name: String
    let categoryGroupId: String
    let categoryGroupName: String?
    let hidden: Bool
    let originalCategoryGroupId: String?
    let note: String?
    let budgeted: Int
    let activity: Int
    let balance: Int
    let goalType: String?
    let goalDay: Int?
    let goalCadence: Int?
    let goalCadenceFrequency: Int?
    let goalCreationMonth: String?
    let goalTarget: Int?
    let goalTargetMonth: String?
    let goalPercentageComplete: Int?
    let goalMonthsToBudget: Int?
    let goalUnderFunded: Int?
    let goalOverallFunded: Int?
    let goalOverallLeft: Int?
    let deleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case categoryGroupId = "category_group_id"
        case categoryGroupName = "category_group_name"
        case hidden
        case originalCategoryGroupId = "original_category_group_id"
        case note
        case budgeted
        case activity
        case balance
        case goalType = "goal_type"
        case goalDay = "goal_day"
        case goalCadence = "goal_cadence"
        case goalCadenceFrequency = "goal_cadence_frequency"
        case goalCreationMonth = "goal_creation_month"
        case goalTarget = "goal_target"
        case goalTargetMonth = "goal_target_month"
        case goalPercentageComplete = "goal_percentage_complete"
        case goalMonthsToBudget = "goal_months_to_budget"
        case goalUnderFunded = "goal_under_funded"
        case goalOverallFunded = "goal_overall_funded"
        case goalOverallLeft = "goal_overall_left"
        case deleted
    }
    
    var isActive: Bool {
        return !hidden && !deleted
    }
    
    var displayName: String {
        if let groupName = categoryGroupName {
            return "\(groupName): \(name)"
        }
        return name
    }
}

struct YNABCategoryGroup: Codable {
    let id: String
    let name: String
    let hidden: Bool
    let deleted: Bool
    let categories: [YNABCategory]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hidden
        case deleted
        case categories
    }
    
    var isActive: Bool {
        return !hidden && !deleted
    }
}

struct YNABCategoriesResponse: Codable {
    let data: YNABCategoriesData
    
    struct YNABCategoriesData: Codable {
        let categoryGroups: [YNABCategoryGroup]
        let serverKnowledge: Int
        
        enum CodingKeys: String, CodingKey {
            case categoryGroups = "category_groups"
            case serverKnowledge = "server_knowledge"
        }
    }
}

// MARK: - Helper Functions

extension YNABTransaction {
    static func fromUpTransaction(_ upTransaction: UpTransaction, accountId: String, upAccountName: String) -> YNABTransactionRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let date = upTransaction.settledAt ?? upTransaction.createdAt
        let dateString = dateFormatter.string(from: date)
        
        let memo = [
            upTransaction.displayDescription,
            upTransaction.message.map { "Note: \($0)" }
        ].compactMap { $0 }.joined(separator: " | ")
        
        let payeeName = upTransaction.displayDescription
        let amount = upTransaction.amount.toYNABAmount()
        // Use Up Banking transaction ID directly (already 36 characters)
        let importId = YNABTransactionRequest.validateImportId(upTransaction.id)
        
        return YNABTransactionRequest(
            accountId: accountId,
            payeeName: payeeName,
            memo: memo.isEmpty ? nil : memo,
            amount: amount,
            date: dateString,
            importId: importId
        )
    }
    
    static func fromUpTransaction(
        _ upTransaction: UpTransaction,
        accountId: String,
        upAccountName: String,
        merchantRule: MerchantRule?
    ) -> YNABTransactionRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let date = upTransaction.settledAt ?? upTransaction.createdAt
        let dateString = dateFormatter.string(from: date)
        
        let memo = [
            upTransaction.displayDescription,
            upTransaction.message.map { "Note: \($0)" }
        ].compactMap { $0 }.joined(separator: " | ")
        
        // Use merchant rule payee name if available, otherwise use transaction description
        let payeeName = merchantRule?.payeeName ?? upTransaction.displayDescription
        let amount = upTransaction.amount.toYNABAmount()
        let importId = YNABTransactionRequest.validateImportId(upTransaction.id)
        
        // Create base request
        var request = YNABTransactionRequest(
            accountId: accountId,
            payeeName: payeeName,
            memo: memo.isEmpty ? nil : memo,
            amount: amount,
            date: dateString,
            importId: importId
        )
        
        // Apply merchant rule categorization if available
        if let merchantRule = merchantRule {
            request = YNABTransactionRequest(
                accountId: accountId,
                payeeName: merchantRule.payeeName,
                categoryId: merchantRule.categoryId,
                memo: memo.isEmpty ? nil : memo,
                amount: amount,
                date: dateString,
                cleared: "uncleared",
                approved: true,
                flagColor: nil,
                importId: importId
            )
        }
        
        return request
    }
}