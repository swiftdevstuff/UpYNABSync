import Foundation

class MerchantLearningService: @unchecked Sendable {
    static let shared = MerchantLearningService()
    private init() {}
    
    private let database = SyncDatabase.shared
    private let logger = Logger.shared
    
    enum MerchantLearningError: Error, LocalizedError {
        case patternExtractionFailed(String)
        case invalidCategory(String)
        case ruleCreationFailed(Error)
        case ruleNotFound(String)
        case databaseError(Error)
        
        var errorDescription: String? {
            switch self {
            case .patternExtractionFailed(let description):
                return "Failed to extract merchant pattern from: \(description)"
            case .invalidCategory(let categoryId):
                return "Invalid category ID: \(categoryId)"
            case .ruleCreationFailed(let error):
                return "Failed to create merchant rule: \(error.localizedDescription)"
            case .ruleNotFound(let pattern):
                return "Merchant rule not found for pattern: \(pattern)"
            case .databaseError(let error):
                return "Database error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Extracts a merchant pattern from a transaction description
    func extractMerchantPattern(from transaction: UpTransaction) -> String {
        let primaryDescription = transaction.displayDescription
        
        // Try to extract from rawText if available and more detailed
        if let rawText = transaction.rawText,
           rawText.count > primaryDescription.count,
           !rawText.isEmpty {
            return extractPatternFromText(rawText)
        }
        
        return extractPatternFromText(primaryDescription)
    }
    
    /// Creates a new merchant rule
    func createMerchantRule(
        pattern: String,
        categoryId: String,
        categoryName: String,
        payeeName: String,
        confidence: Double = 1.0
    ) throws {
        logger.debug("Creating merchant rule: \(pattern) → \(categoryName)")
        
        // Ensure database is initialized
        try ensureDatabaseInitialized()
        
        // Validate inputs
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MerchantLearningError.patternExtractionFailed("Empty pattern")
        }
        
        guard !categoryId.isEmpty else {
            throw MerchantLearningError.invalidCategory("Empty category ID")
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        let rule = MerchantRule(
            id: nil,
            merchantPattern: pattern.uppercased(),
            categoryId: categoryId,
            categoryName: categoryName,
            payeeName: payeeName,
            confidence: confidence,
            usageCount: 0,
            lastUsed: nil,
            createdAt: now,
            updatedAt: now
        )
        
        do {
            try database.insertMerchantRule(rule)
            logger.info("✅ Created merchant rule: \(pattern) → \(categoryName)")
        } catch {
            logger.error("❌ Failed to create merchant rule: \(error)")
            throw MerchantLearningError.ruleCreationFailed(error)
        }
    }
    
    /// Finds a merchant rule for a transaction
    func getMerchantRule(for transaction: UpTransaction) throws -> MerchantRule? {
        // Ensure database is initialized
        try ensureDatabaseInitialized()
        
        let pattern = extractMerchantPattern(from: transaction)
        let normalizedPattern = pattern.uppercased()
        
        do {
            // First try exact match
            if let rule = try database.getMerchantRule(normalizedPattern) {
                logger.debug("🎯 Found exact rule match: \(normalizedPattern) → \(rule.categoryName)")
                return rule
            }
            
            // Try partial matches from existing rules
            let allRules = try database.getAllMerchantRules()
            for rule in allRules {
                if normalizedPattern.contains(rule.merchantPattern) || 
                   rule.merchantPattern.contains(normalizedPattern) {
                    logger.debug("🎯 Found partial rule match: \(normalizedPattern) ≈ \(rule.merchantPattern) → \(rule.categoryName)")
                    return rule
                }
            }
            
            logger.debug("🔍 No rule found for pattern: \(normalizedPattern)")
            return nil
        } catch {
            logger.error("❌ Failed to get merchant rule: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Updates usage statistics for a merchant rule
    func updateRuleUsage(_ rule: MerchantRule) throws {
        do {
            try database.updateMerchantRuleUsage(rule.merchantPattern)
            logger.debug("📊 Updated usage for rule: \(rule.merchantPattern)")
        } catch {
            logger.error("❌ Failed to update rule usage: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Gets all merchant rules
    func getAllMerchantRules() throws -> [MerchantRule] {
        try ensureDatabaseInitialized()
        
        do {
            return try database.getAllMerchantRules()
        } catch {
            logger.error("❌ Failed to get all merchant rules: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Deletes a merchant rule
    func deleteMerchantRule(pattern: String) throws {
        do {
            try database.deleteMerchantRule(pattern.uppercased())
            logger.info("🗑️ Deleted merchant rule: \(pattern)")
        } catch {
            logger.error("❌ Failed to delete merchant rule: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Records categorization history
    func recordCategorizationHistory(
        transactionId: String,
        merchantPattern: String,
        suggestedCategoryId: String?,
        appliedCategoryId: String?,
        userAccepted: Bool,
        confidence: Double?
    ) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let history = CategorizationHistory(
            id: nil,
            transactionId: transactionId,
            merchantPattern: merchantPattern,
            suggestedCategoryId: suggestedCategoryId,
            appliedCategoryId: appliedCategoryId,
            userAccepted: userAccepted,
            confidence: confidence,
            createdAt: now
        )
        
        do {
            try database.insertCategorizationHistory(history)
            logger.debug("📝 Recorded categorization history for: \(transactionId)")
        } catch {
            logger.error("❌ Failed to record categorization history: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Gets merchant rule statistics
    func getMerchantRuleStats() throws -> [String: Any] {
        try ensureDatabaseInitialized()
        
        do {
            return try database.getMerchantRuleStats()
        } catch {
            logger.error("❌ Failed to get merchant rule stats: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    /// Analyzes recent transactions for potential rules
    func analyzeRecentTransactions(days: Int = 14, limit: Int = 50) throws -> [String: [UpTransaction]] {
        logger.info("🔍 Analyzing recent transactions for merchant patterns (last \(days) days)")
        
        // This method would need to be called from a context where we have access to transactions
        // For now, return empty dictionary - this will be implemented when integrated with sync command
        return [:]
    }
    
    // MARK: - Private Methods
    
    private func ensureDatabaseInitialized() throws {
        do {
            try database.initialize()
        } catch {
            logger.error("Failed to initialize database: \(error)")
            throw MerchantLearningError.databaseError(error)
        }
    }
    
    private func extractPatternFromText(_ text: String) -> String {
        let cleaned = text
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common transaction noise
        let withoutNoise = cleaned
            .replacingOccurrences(of: "CARD PURCHASE", with: "")
            .replacingOccurrences(of: "EFTPOS", with: "")
            .replacingOccurrences(of: "VISA", with: "")
            .replacingOccurrences(of: "MASTERCARD", with: "")
            .replacingOccurrences(of: "PAYPAL", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract the meaningful part (usually the first substantial word)
        let components = withoutNoise.components(separatedBy: .whitespaces)
        guard let firstComponent = components.first(where: { !$0.isEmpty }) else {
            return cleaned
        }
        
        // Remove location indicators, numbers, and dates
        let pattern = firstComponent
            .replacingOccurrences(of: #"\d{2}/\d{2}/\d{4}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{2}/\d{2}/\d{2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4}-\d{2}-\d{2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{8,}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\d+\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return the pattern or fall back to original if too short
        return pattern.count >= 3 ? pattern : firstComponent
    }
    
    private func normalizePayeeName(_ description: String) -> String {
        // Extract a clean payee name from the description
        let components = description.components(separatedBy: .whitespaces)
        let meaningful = components.filter { component in
            !component.isEmpty &&
            !component.contains(where: { $0.isNumber }) &&
            component.count > 2
        }
        
        return meaningful.first?.capitalized ?? description
    }
}