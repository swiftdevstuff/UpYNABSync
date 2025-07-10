import Foundation
import Security

class KeychainManager: @unchecked Sendable {
    static let shared = KeychainManager()
    private init() {}
    
    private let serviceName = "com.upynabsync.api-tokens"
    
    enum KeychainError: Error, LocalizedError {
        case tokenNotFound
        case duplicateToken
        case invalidData
        case keychainError(OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .tokenNotFound:
                return "API token not found in Keychain"
            case .duplicateToken:
                return "Token already exists in Keychain"
            case .invalidData:
                return "Invalid token data"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    func saveToken(service: String, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecValueData as String: tokenData
        ]
        
        // Check if token already exists
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            // Update existing token
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: service
            ]
            
            let updateAttributes: [String: Any] = [
                kSecValueData as String: tokenData
            ]
            
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.keychainError(updateStatus)
            }
        } else {
            // Add new token
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.keychainError(addStatus)
            }
        }
    }
    
    func getToken(service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.tokenNotFound
            }
            throw KeychainError.keychainError(status)
        }
        
        guard let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return token
    }
    
    func deleteToken(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.keychainError(status)
        }
    }
    
    func hasToken(service: String) -> Bool {
        do {
            _ = try getToken(service: service)
            return true
        } catch {
            return false
        }
    }
}

extension KeychainManager {
    static let upBankingService = "up-banking-token"
    static let ynabService = "ynab-token"
    
    func saveUpBankingToken(_ token: String) throws {
        try saveToken(service: Self.upBankingService, token: token)
    }
    
    func getUpBankingToken() throws -> String {
        return try getToken(service: Self.upBankingService)
    }
    
    func saveYNABToken(_ token: String) throws {
        try saveToken(service: Self.ynabService, token: token)
    }
    
    func getYNABToken() throws -> String {
        return try getToken(service: Self.ynabService)
    }
    
    func hasAllTokens() -> Bool {
        return hasToken(service: Self.upBankingService) && hasToken(service: Self.ynabService)
    }
}