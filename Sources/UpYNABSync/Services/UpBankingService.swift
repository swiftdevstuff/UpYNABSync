import Foundation

class UpBankingService: @unchecked Sendable {
    static let shared = UpBankingService()
    private init() {}
    
    private let apiClient = APIClient.shared
    private let logger = Logger.shared
    private let keychain = KeychainManager.shared
    
    private let baseURL = "https://api.up.com.au/api/v1"
    
    enum UpBankingError: Error, LocalizedError {
        case tokenNotFound
        case invalidResponse
        case accountNotFound
        case transactionNotFound
        case rateLimited
        case serverError(String)
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .tokenNotFound:
                return "Up Banking API token not found. Please run 'up-ynab-sync auth' first."
            case .invalidResponse:
                return "Invalid response from Up Banking API"
            case .accountNotFound:
                return "Account not found in Up Banking"
            case .transactionNotFound:
                return "Transaction not found in Up Banking"
            case .rateLimited:
                return "Rate limited by Up Banking API. Please try again later."
            case .serverError(let message):
                return "Up Banking server error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Authentication
    
    func testConnection() async throws -> Bool {
        let url = URL(string: "\(baseURL)/util/ping")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.get(
                url: url,
                headers: headers,
                responseType: UpPingResponse.self,
                serviceName: "Up Banking"
            )
            
            logger.info("Up Banking connection test successful: \(response.meta.statusEmoji)")
            return true
        } catch {
            logger.error("Up Banking connection test failed: \(error)")
            return false
        }
    }
    
    private func getAuthHeaders() throws -> [String: String] {
        let token = try keychain.getUpBankingToken()
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": "UpYNABSync/1.0"
        ]
    }
    
    // MARK: - Accounts
    
    func getAccounts() async throws -> [UpAccount] {
        let url = URL(string: "\(baseURL)/accounts")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: UpAccountsResponse.self,
                    serviceName: "Up Banking"
                )
            }
            
            let accounts = response.data.map { $0.attributes }
            logger.info("Retrieved \(accounts.count) Up Banking accounts")
            return accounts
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw UpBankingError.networkError(error)
        }
    }
    
    func getAccount(id: String) async throws -> UpAccount {
        let url = URL(string: "\(baseURL)/accounts/\(id)")!
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: UpAccountsResponse.self,
                    serviceName: "Up Banking"
                )
            }
            
            guard let account = response.data.first?.attributes else {
                throw UpBankingError.accountNotFound
            }
            
            return account
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw UpBankingError.networkError(error)
        }
    }
    
    func getTransactionAccount() async throws -> UpAccount? {
        let accounts = try await getAccounts()
        return accounts.first { $0.isTransactionAccount }
    }
    
    func getSaverAccounts() async throws -> [UpAccount] {
        let accounts = try await getAccounts()
        return accounts.filter { $0.isSaverAccount }
    }
    
    func getActiveAccounts() async throws -> [UpAccount] {
        let accounts = try await getAccounts()
        return accounts.filter { $0.isTransactionAccount || $0.isSaverAccount }
    }
    
    // MARK: - Transactions
    
    func getTransactions(accountId: String, since: Date? = nil, until: Date? = nil, pageSize: Int = 20) async throws -> [UpTransaction] {
        var urlComponents = URLComponents(string: "\(baseURL)/accounts/\(accountId)/transactions")!
        
        var queryItems: [URLQueryItem] = []
        
        if let pageSize = pageSize as Int?, pageSize > 0 {
            queryItems.append(URLQueryItem(name: "page[size]", value: String(pageSize)))
        }
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "filter[since]", value: formatter.string(from: since)))
        }
        
        if let until = until {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "filter[until]", value: formatter.string(from: until)))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw UpBankingError.invalidResponse
        }
        
        let headers = try getAuthHeaders()
        
        do {
            let response = try await apiClient.withRetry {
                try await self.apiClient.get(
                    url: url,
                    headers: headers,
                    responseType: UpTransactionsResponse.self,
                    serviceName: "Up Banking"
                )
            }
            
            let transactions = response.data.map { $0.attributes }
            logger.info("Retrieved \(transactions.count) transactions for account \(accountId)")
            return transactions
        } catch let error as APIClient.APIError {
            throw mapAPIError(error)
        } catch {
            throw UpBankingError.networkError(error)
        }
    }
    
    func getRecentTransactions(accountId: String, days: Int = 1) async throws -> [UpTransaction] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try await getTransactions(accountId: accountId, since: since)
    }
    
    func getTransactionsForAllAccounts(since: Date? = nil, until: Date? = nil) async throws -> [String: [UpTransaction]] {
        let accounts = try await getActiveAccounts()
        var allTransactions: [String: [UpTransaction]] = [:]
        
        logger.info("Fetching transactions for \(accounts.count) accounts")
        
        for account in accounts {
            do {
                let transactions = try await getTransactions(
                    accountId: account.id,
                    since: since,
                    until: until
                )
                allTransactions[account.id] = transactions
                logger.info("Retrieved \(transactions.count) transactions for \(account.displayName)")
            } catch {
                logger.error("Failed to get transactions for account \(account.displayName): \(error)")
                allTransactions[account.id] = []
            }
        }
        
        return allTransactions
    }
    
    func getTransactionsForDateRange(accountId: String, startDate: Date, endDate: Date) async throws -> [UpTransaction] {
        return try await getTransactions(accountId: accountId, since: startDate, until: endDate)
    }
    
    // MARK: - Pagination Support
    
    func getAllTransactions(accountId: String, since: Date? = nil, until: Date? = nil, maxPages: Int = 10) async throws -> [UpTransaction] {
        var allTransactions: [UpTransaction] = []
        var currentPage = 1
        var hasNextPage = true
        
        while hasNextPage && currentPage <= maxPages {
            let pageTransactions = try await getTransactions(
                accountId: accountId,
                since: since,
                until: until,
                pageSize: 100
            )
            
            allTransactions.append(contentsOf: pageTransactions)
            
            // Up Banking API returns less than requested page size when there are no more pages
            hasNextPage = pageTransactions.count == 100
            currentPage += 1
            
            logger.debug("Retrieved page \(currentPage - 1) with \(pageTransactions.count) transactions")
        }
        
        logger.info("Retrieved total of \(allTransactions.count) transactions for account \(accountId)")
        return allTransactions
    }
    
    // MARK: - Account Balance
    
    func getAccountBalance(accountId: String) async throws -> UpAmount {
        let account = try await getAccount(id: accountId)
        return account.balance
    }
    
    func getAllAccountBalances() async throws -> [String: UpAmount] {
        let accounts = try await getActiveAccounts()
        var balances: [String: UpAmount] = [:]
        
        for account in accounts {
            balances[account.id] = account.balance
        }
        
        return balances
    }
    
    // MARK: - Utility Methods
    
    func getAccountDisplayName(accountId: String) async throws -> String {
        let account = try await getAccount(id: accountId)
        return account.displayName
    }
    
    func validateAccount(accountId: String) async throws -> Bool {
        do {
            _ = try await getAccount(id: accountId)
            return true
        } catch {
            return false
        }
    }
    
    func getAccountType(accountId: String) async throws -> String {
        let account = try await getAccount(id: accountId)
        return account.accountType
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIError(_ error: APIClient.APIError) -> UpBankingError {
        switch error {
        case .unauthorized:
            return .tokenNotFound
        case .rateLimited:
            return .rateLimited
        case .notFound:
            return .accountNotFound
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
    
    // MARK: - Health Check
    
    func getServiceHealth() async -> (isHealthy: Bool, details: String) {
        do {
            let isConnected = try await testConnection()
            if isConnected {
                let accounts = try await getAccounts()
                return (true, "✅ Connected to Up Banking API with \(accounts.count) accounts")
            } else {
                return (false, "❌ Failed to connect to Up Banking API")
            }
        } catch {
            return (false, "❌ Up Banking API error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rate Limiting Support
    
    func checkRateLimit() async throws -> (remaining: Int, resetTime: Date?) {
        // Up Banking doesn't provide rate limit headers in ping endpoint
        // This is a placeholder for potential future rate limit checking
        return (100, nil)
    }
}