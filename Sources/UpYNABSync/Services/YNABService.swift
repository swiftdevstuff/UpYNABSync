import Foundation

class YNABService: @unchecked Sendable {
    static let shared = YNABService()
    private init() {}
    
    private let apiClient = APIClient.shared
    private let logger = Logger.shared
    private let keychain = KeychainManager.shared
    
    private let baseURL = "https://api.ynab.com/v1"
    
    enum YNABError: Error, LocalizedError {
        case tokenNotFound
        case invalidResponse
        case budgetNotFound
        case accountNotFound
        case transactionNotFound
        case rateLimited
        case serverError(String)
        case networkError(Error)
        case invalidBudgetId
        case invalidAccountId
        case transactionCreationFailed
        case duplicateImportId
        
        var errorDescription: String? {
            switch self {
            case .tokenNotFound:
                return "YNAB API token not found. Please run 'up-ynab-sync auth' first."
            case .invalidResponse:
                return "Invalid response from YNAB API"
            case .budgetNotFound:
                return "Budget not found in YNAB"
            case .accountNotFound:
                return "Account not found in YNAB"
            case .transactionNotFound:
                return "Transaction not found in YNAB"
            case .rateLimited:
                return "Rate limited by YNAB API. Please try again later."
            case .serverError(let message):
                return "YNAB server error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidBudgetId:
                return "Invalid budget ID"
            case .invalidAccountId:
                return "Invalid account ID"
            case .transactionCreationFailed:
                return "Failed to create transaction in YNAB"
            case .duplicateImportId:
                return "Transaction with this import ID already exists"
            }
        }
    }
    
    // MARK: - Authentication
    
    func testConnection() async throws -> Bool {
        let url = URL(string: "\(baseURL)/user")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.get(
                url: url,
                headers: headers,
                responseType: YNABUserResponse.self,
                serviceName: "YNAB"
            )
            
            logger.info("YNAB connection test successful for user: \(response.data.user.id)")
            return true
        } catch {
            logger.error("YNAB connection test failed: \(error)")
            return false
        }
    }
    
    private func getAuthHeaders() throws -> [String: String] {
        let token = try keychain.getYNABToken()
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": "UpYNABSync/1.0"
        ]
    }
    
    // MARK: - Budgets
    
    func getBudgets() async throws -> [YNABBudget] {
        let url = URL(string: "\(baseURL)/budgets")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: YNABBudgetsResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            let budgets = response.data.budgets
            logger.info("Retrieved \(budgets.count) YNAB budgets")
            return budgets
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func getBudget(id: String) async throws -> YNABBudget {
        let url = URL(string: "\(baseURL)/budgets/\(id)")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: YNABBudgetResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            return response.data.budget
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func getDefaultBudget() async throws -> YNABBudget {
        let budgets = try await getBudgets()
        guard let defaultBudget = budgets.first else {
            throw YNABError.budgetNotFound
        }
        return defaultBudget
    }
    
    // MARK: - Accounts
    
    func getAccounts(budgetId: String) async throws -> [YNABAccount] {
        let url = URL(string: "\(baseURL)/budgets/\(budgetId)/accounts")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: YNABAccountsResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            let accounts = response.data.accounts.filter { $0.isActive }
            logger.info("Retrieved \(accounts.count) active YNAB accounts for budget \(budgetId)")
            return accounts
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func getAccount(budgetId: String, accountId: String) async throws -> YNABAccount {
        let accounts = try await getAccounts(budgetId: budgetId)
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            throw YNABError.accountNotFound
        }
        return account
    }
    
    func getAccountBalance(budgetId: String, accountId: String) async throws -> Int {
        let account = try await getAccount(budgetId: budgetId, accountId: accountId)
        return account.balance
    }
    
    // MARK: - Transactions
    
    func getTransactions(budgetId: String, accountId: String? = nil, since: Date? = nil) async throws -> [YNABTransaction] {
        var urlComponents = URLComponents(string: "\(baseURL)/budgets/\(budgetId)/transactions")!
        
        var queryItems: [URLQueryItem] = []
        
        if let accountId = accountId {
            queryItems.append(URLQueryItem(name: "account_id", value: accountId))
        }
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "since_date", value: formatter.string(from: since)))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw YNABError.invalidResponse
        }
        
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: YNABTransactionsResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            let transactions = response.data.transactions.filter { !$0.deleted }
            logger.info("Retrieved \(transactions.count) YNAB transactions")
            return transactions
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func createTransaction(budgetId: String, transaction: YNABTransactionRequest) async throws -> YNABTransaction {
        let url = URL(string: "\(baseURL)/budgets/\(budgetId)/transactions")!
        let headers = try getAuthHeaders()
        
        let requestBody = YNABTransactionsBulkRequest(transactions: [transaction])
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.post(
                    url: url,
                    headers: headers,
                    body: requestBody,
                    responseType: YNABTransactionCreateResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            if let duplicateIds = response.data.duplicateImportIds, !duplicateIds.isEmpty {
                logger.warning("Duplicate import IDs detected: \(duplicateIds)")
                throw YNABError.duplicateImportId
            }
            
            guard let createdTransaction = response.data.transaction ?? response.data.transactions?.first else {
                throw YNABError.transactionCreationFailed
            }
            
            logger.info("Created YNAB transaction: \(createdTransaction.id ?? "unknown")")
            return createdTransaction
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func createTransactions(budgetId: String, transactions: [YNABTransactionRequest]) async throws -> [YNABTransaction] {
        let url = URL(string: "\(baseURL)/budgets/\(budgetId)/transactions")!
        let headers = try getAuthHeaders()
        
        let requestBody = YNABTransactionsBulkRequest(transactions: transactions)
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.post(
                    url: url,
                    headers: headers,
                    body: requestBody,
                    responseType: YNABTransactionCreateResponse.self,
                    serviceName: "YNAB"
                )
            }
            
            if let duplicateIds = response.data.duplicateImportIds, !duplicateIds.isEmpty {
                logger.warning("Duplicate import IDs detected: \(duplicateIds)")
            }
            
            let createdTransactions = response.data.transactions ?? []
            logger.info("Created \(createdTransactions.count) YNAB transactions")
            return createdTransactions
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw YNABError.networkError(error)
        }
    }
    
    func syncUpTransaction(_ upTransaction: UpTransaction, toAccount accountId: String, budgetId: String) async throws -> YNABTransaction {
        let ynabTransaction = YNABTransaction.fromUpTransaction(upTransaction, accountId: accountId, upAccountName: "")
        
        // Validate amount conversion
        let expectedYNABAmount = upTransaction.amount.toYNABAmount()
        guard upTransaction.amount.validateYNABConversion(expectedYNABAmount) else {
            throw YNABError.serverError("Amount conversion validation failed")
        }
        
        logger.logAmountConversion(upAmount: upTransaction.amount.valueInBaseUnits, ynabAmount: expectedYNABAmount)
        
        return try await createTransaction(budgetId: budgetId, transaction: ynabTransaction)
    }
    
    // MARK: - Bulk Operations
    
    func syncUpTransactions(_ upTransactions: [UpTransaction], toAccount accountId: String, budgetId: String) async throws -> [YNABTransaction] {
        let ynabTransactions = upTransactions.map { upTransaction in
            YNABTransaction.fromUpTransaction(upTransaction, accountId: accountId, upAccountName: "")
        }
        
        // Validate all amount conversions
        for (index, upTransaction) in upTransactions.enumerated() {
            let expectedYNABAmount = upTransaction.amount.toYNABAmount()
            let actualYNABAmount = ynabTransactions[index].amount
            
            guard upTransaction.amount.validateYNABConversion(expectedYNABAmount) else {
                throw YNABError.serverError("Amount conversion validation failed for transaction \(upTransaction.id)")
            }
            
            logger.logAmountConversion(upAmount: upTransaction.amount.valueInBaseUnits, ynabAmount: actualYNABAmount)
        }
        
        return try await createTransactions(budgetId: budgetId, transactions: ynabTransactions)
    }
    
    // MARK: - Validation
    
    func validateBudget(budgetId: String) async throws -> Bool {
        do {
            _ = try await getBudget(id: budgetId)
            return true
        } catch {
            return false
        }
    }
    
    func validateAccount(budgetId: String, accountId: String) async throws -> Bool {
        do {
            _ = try await getAccount(budgetId: budgetId, accountId: accountId)
            return true
        } catch {
            return false
        }
    }
    
    func validateConfiguration(budgetId: String, accountMappings: [SyncAccountMapping]) async throws -> [String] {
        var errors: [String] = []
        
        // Validate budget
        if !(try await validateBudget(budgetId: budgetId)) {
            errors.append("Budget '\(budgetId)' not found or not accessible")
        }
        
        // Validate accounts
        for mapping in accountMappings {
            if !(try await validateAccount(budgetId: budgetId, accountId: mapping.ynabAccountId)) {
                errors.append("Account '\(mapping.ynabAccountName)' not found in budget")
            }
        }
        
        return errors
    }
    
    // MARK: - Health Check
    
    func getServiceHealth() async -> (isHealthy: Bool, details: String) {
        do {
            let isConnected = try await testConnection()
            if isConnected {
                let budgets = try await getBudgets()
                return (true, "✅ Connected to YNAB API with \(budgets.count) budgets")
            } else {
                return (false, "❌ Failed to connect to YNAB API")
            }
        } catch {
            return (false, "❌ YNAB API error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Utility Methods
    
    func getBudgetName(budgetId: String) async throws -> String {
        let budget = try await getBudget(id: budgetId)
        return budget.name
    }
    
    func getAccountName(budgetId: String, accountId: String) async throws -> String {
        let account = try await getAccount(budgetId: budgetId, accountId: accountId)
        return account.name
    }
    
    func getAccountsForBudget(budgetId: String) async throws -> [(id: String, name: String, balance: String)] {
        let accounts = try await getAccounts(budgetId: budgetId)
        return accounts.map { account in
            (id: account.id, name: account.name, balance: account.formattedBalance)
        }
    }
    
    func getBudgetSummary(budgetId: String) async throws -> String {
        let budget = try await getBudget(id: budgetId)
        let accounts = try await getAccounts(budgetId: budgetId)
        
        return """
        Budget: \(budget.name)
        Accounts: \(accounts.count)
        Last Modified: \(budget.lastModifiedOn?.description ?? "Unknown")
        """
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIError(_ error: APIClient.APIError) -> YNABError {
        switch error {
        case .unauthorized:
            return .tokenNotFound
        case .rateLimited:
            return .rateLimited
        case .notFound:
            return .budgetNotFound
        case .serverError(let statusCode):
            return .serverError("HTTP \(statusCode)")
        case .requestFailed(let statusCode, let message):
            return .serverError("HTTP \(statusCode): \(message ?? "Unknown error")")
        case .networkError(let underlyingError):
            return .networkError(underlyingError)
        default:
            return .invalidResponse
        }
    }
    
    // MARK: - Rate Limiting
    
    func checkRateLimit() async throws -> (remaining: Int, resetTime: Date?) {
        // YNAB API rate limiting info would need to be extracted from response headers
        // This is a placeholder for potential future implementation
        return (200, nil)
    }
}