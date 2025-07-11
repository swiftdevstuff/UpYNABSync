import Foundation

class YNABPatternAnalyzer: @unchecked Sendable {
    static let shared = YNABPatternAnalyzer()
    private init() {}
    
    private let ynabService = YNABService.shared
    private let merchantService = MerchantLearningService.shared
    private let logger = Logger.shared
    
    enum PatternAnalysisError: Error, LocalizedError {
        case insufficientData
        case budgetNotFound
        case analysisError(Error)
        case noPatterns
        
        var errorDescription: String? {
            switch self {
            case .insufficientData:
                return "Insufficient transaction data to analyze patterns"
            case .budgetNotFound:
                return "Budget not found in YNAB"
            case .analysisError(let error):
                return "Pattern analysis failed: \(error.localizedDescription)"
            case .noPatterns:
                return "No meaningful patterns found in transaction data"
            }
        }
    }
    
    func analyzeCategorizationPatterns(
        budgetId: String,
        days: Int = 30
    ) async throws -> [CategoryPattern] {
        logger.info("🔍 Analyzing YNAB categorization patterns for last \(days) days")
        
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let transactions = try await ynabService.getTransactions(budgetId: budgetId, since: cutoffDate)
            
            if transactions.isEmpty {
                throw PatternAnalysisError.insufficientData
            }
            
            logger.info("Found \(transactions.count) transactions to analyze")
            
            let patterns = extractPatternsFromTransactions(transactions)
            let validPatterns = patterns.filter { $0.isWorthSuggesting }
            
            logger.info("Extracted \(validPatterns.count) valid patterns from \(patterns.count) total patterns")
            
            return validPatterns
        } catch let error as YNABService.YNABError {
            logger.error("YNAB API error during pattern analysis: \(error)")
            throw PatternAnalysisError.analysisError(error)
        } catch {
            logger.error("Pattern analysis error: \(error)")
            throw PatternAnalysisError.analysisError(error)
        }
    }
    
    func suggestMerchantRules(
        from patterns: [CategoryPattern],
        confidenceThreshold: Double = 0.7
    ) -> [MerchantRuleSuggestion] {
        logger.info("🎯 Generating merchant rule suggestions from \(patterns.count) patterns")
        
        let highConfidencePatterns = patterns.filter { $0.confidence >= confidenceThreshold }
        
        let suggestions = highConfidencePatterns.compactMap { pattern -> MerchantRuleSuggestion? in
            let shouldAutoApprove = pattern.confidence >= 0.9 && pattern.transactionCount >= 3
            
            return MerchantRuleSuggestion(
                pattern: pattern,
                description: generateSuggestionDescription(pattern),
                shouldAutoApprove: shouldAutoApprove
            )
        }
        
        logger.info("Generated \(suggestions.count) rule suggestions from \(highConfidencePatterns.count) high-confidence patterns")
        
        return suggestions.sorted { $0.pattern.confidence > $1.pattern.confidence }
    }
    
    private func extractPatternsFromTransactions(_ transactions: [YNABTransaction]) -> [CategoryPattern] {
        var patternGroups: [String: [YNABTransaction]] = [:]
        
        for transaction in transactions {
            guard let payeeName = transaction.payeeName,
                  let categoryId = transaction.categoryId,
                  let categoryName = transaction.categoryName,
                  !payeeName.isEmpty,
                  !categoryId.isEmpty,
                  !categoryName.isEmpty else {
                continue
            }
            
            let normalizedPayee = normalizePayeeName(payeeName)
            let pattern = extractPatternFromPayee(normalizedPayee)
            
            if pattern.count >= 3 {
                patternGroups[pattern, default: []].append(transaction)
            }
        }
        
        let patterns = patternGroups.compactMap { (pattern, transactions) -> CategoryPattern? in
            guard transactions.count >= 2 else { return nil }
            
            let categoryVotes = Dictionary(grouping: transactions) { $0.categoryId ?? "" }
            guard let (mostCommonCategoryId, categoryTransactions) = categoryVotes.max(by: { $0.value.count < $1.value.count }),
                  let categoryName = categoryTransactions.first?.categoryName else {
                return nil
            }
            
            let consistency = Double(categoryTransactions.count) / Double(transactions.count)
            let confidence = calculateConfidence(
                consistency: consistency,
                transactionCount: transactions.count,
                pattern: pattern
            )
            
            return CategoryPattern(
                merchantPattern: pattern,
                categoryId: mostCommonCategoryId,
                categoryName: categoryName,
                confidence: confidence,
                transactionCount: transactions.count,
                isWorthSuggesting: shouldSuggestPattern(
                    pattern: pattern,
                    confidence: confidence,
                    transactionCount: transactions.count
                )
            )
        }
        
        return patterns
    }
    
    private func normalizePayeeName(_ payeeName: String) -> String {
        return payeeName
            .uppercased()
            .replacingOccurrences(of: "CARD PURCHASE", with: "")
            .replacingOccurrences(of: "EFTPOS", with: "")
            .replacingOccurrences(of: "VISA", with: "")
            .replacingOccurrences(of: "MASTERCARD", with: "")
            .replacingOccurrences(of: "PAYPAL", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractPatternFromPayee(_ payee: String) -> String {
        let components = payee.components(separatedBy: .whitespaces)
        guard let firstComponent = components.first(where: { !$0.isEmpty }) else {
            return payee
        }
        
        let pattern = firstComponent
            .replacingOccurrences(of: #"\d{2}/\d{2}/\d{4}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{2}/\d{2}/\d{2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4}-\d{2}-\d{2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{8,}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\d+\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return pattern.count >= 3 ? pattern : firstComponent
    }
    
    private func calculateConfidence(
        consistency: Double,
        transactionCount: Int,
        pattern: String
    ) -> Double {
        var confidence = consistency
        
        if transactionCount >= 5 {
            confidence += 0.1
        }
        
        if transactionCount >= 10 {
            confidence += 0.1
        }
        
        if isRecognizedMerchantPattern(pattern) {
            confidence += 0.15
        }
        
        return min(1.0, confidence)
    }
    
    private func isRecognizedMerchantPattern(_ pattern: String) -> Bool {
        let knownPatterns = [
            "COLES", "WOOLWORTHS", "ALDI", "IGA", "FOODWORKS",
            "MCDONALD", "KFC", "SUBWAY", "DOMINOS", "PIZZA",
            "NETFLIX", "SPOTIFY", "AMAZON", "APPLE", "GOOGLE",
            "SHELL", "BP", "CALTEX", "MOBIL", "AMPOL",
            "WESTFIELD", "IKEA", "BUNNINGS", "KMART", "TARGET",
            "PAYPAL", "UBER", "AIRBNB", "BOOKING"
        ]
        
        return knownPatterns.contains { pattern.contains($0) }
    }
    
    private func shouldSuggestPattern(
        pattern: String,
        confidence: Double,
        transactionCount: Int
    ) -> Bool {
        guard confidence >= 0.6 else { return false }
        
        guard transactionCount >= 2 else { return false }
        
        guard pattern.count >= 3 else { return false }
        
        return true
    }
    
    private func generateSuggestionDescription(_ pattern: CategoryPattern) -> String {
        let frequency = pattern.transactionCount
        let confidencePercent = Int(pattern.confidence * 100)
        
        return "Pattern '\(pattern.merchantPattern)' appears \(frequency) times with \(confidencePercent)% consistency in category '\(pattern.categoryName)'"
    }
}

struct CategoryPattern {
    let merchantPattern: String
    let categoryId: String
    let categoryName: String
    let confidence: Double
    let transactionCount: Int
    let isWorthSuggesting: Bool
}

struct MerchantRuleSuggestion {
    let pattern: CategoryPattern
    let description: String
    let shouldAutoApprove: Bool
}