import ArgumentParser
import Foundation

struct LearnCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "learn",
        abstract: "Learn merchant categorization patterns from transactions",
        discussion: """
        Interactive command to create merchant categorization rules from transactions.
        
        The tool will show recent transactions and help you create rules for
        automatic categorization in future syncs.
        
        Examples:
        • up-ynab-sync learn                    # Learn from recent transactions
        • up-ynab-sync learn --days 14          # Look back 14 days
        • up-ynab-sync learn --from-ynab        # Learn from existing YNAB patterns
        • up-ynab-sync learn --limit 10         # Process only 10 transactions
        
        Prerequisites:
        • API tokens must be set up (run 'up-ynab-sync auth' first)
        • Configuration must be complete (run 'up-ynab-sync config' first)
        """
    )
    
    @Option(name: .long, help: "Days to look back for transactions")
    var days: Int = 7
    
    @Option(name: .long, help: "Maximum transactions to process")
    var limit: Int = 20
    
    @Flag(name: .long, help: "Learn from existing YNAB categorization patterns")
    var fromYnab: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Auto-approve obvious patterns without asking")
    var autoApprove: Bool = false
    
    private var upBankingService: UpBankingService { UpBankingService.shared }
    private var ynabService: YNABService { YNABService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    private var merchantLearningService: MerchantLearningService { MerchantLearningService.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        if fromYnab {
            try await learnFromYNABPatterns()
        } else {
            try await learnFromRecentTransactions()
        }
        
        try await displayLearningStats()
    }
    
    func validatePrerequisites() async throws {
        // Check API tokens and configuration
        let keychain = KeychainManager.shared
        
        guard keychain.hasToken(service: KeychainManager.upBankingService) else {
            throw CLIError.prerequisiteNotMet("Up Banking API token not found. Please run 'up-ynab-sync auth' first.")
        }
        
        guard keychain.hasToken(service: KeychainManager.ynabService) else {
            throw CLIError.prerequisiteNotMet("YNAB API token not found. Please run 'up-ynab-sync auth' first.")
        }
        
        guard configManager.hasConfiguration() else {
            throw CLIError.prerequisiteNotMet("Configuration not found. Please run 'up-ynab-sync config' first.")
        }
        
        displayInfo("Prerequisites validated")
    }
    
    // MARK: - Learning from Recent Transactions
    
    private func learnFromRecentTransactions() async throws {
        displayInfo("🎓 Learning Mode: Analyzing recent transactions")
        
        // Get configuration
        let config = try configManager.loadConfiguration()
        
        // Get recent transactions from Up Banking
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
        
        displayInfo("Looking for transactions from \(DateFormatter.dateOnly.string(from: startDate)) to \(DateFormatter.dateOnly.string(from: endDate))")
        
        var allTransactions: [UpTransaction] = []
        
        for mapping in config.accountMappings {
            displayInfo("Fetching transactions for \(mapping.upAccountName)...")
            
            let transactions = try await upBankingService.getTransactions(
                accountId: mapping.upAccountId,
                since: startDate,
                until: endDate,
                pageSize: limit
            )
            
            allTransactions.append(contentsOf: transactions)
        }
        
        // Filter out transactions that already have merchant rules
        let transactionsToProcess = try await filterUnknownTransactions(allTransactions)
        
        if transactionsToProcess.isEmpty {
            displayInfo("No new transactions found to learn from.")
            return
        }
        
        displayInfo("Found \(transactionsToProcess.count) transactions to analyze")
        
        // Process transactions interactively
        try await runInteractiveLearningSession(transactionsToProcess)
    }
    
    private func filterUnknownTransactions(_ transactions: [UpTransaction]) async throws -> [UpTransaction] {
        var unknownTransactions: [UpTransaction] = []
        
        for transaction in transactions {
            let merchantRule = try merchantLearningService.getMerchantRule(for: transaction)
            if merchantRule == nil {
                unknownTransactions.append(transaction)
            }
        }
        
        return unknownTransactions
    }
    
    private func runInteractiveLearningSession(_ transactions: [UpTransaction]) async throws {
        let config = try configManager.loadConfiguration()
        let categories = try await ynabService.getCategories(budgetId: config.ynabBudgetId)
        
        print("\n🎓 Interactive Learning Session")
        print(String(repeating: "=", count: 50))
        
        var processedCount = 0
        var rulesCreated = 0
        
        for (index, transaction) in transactions.enumerated() {
            print("\n[\(index + 1)/\(transactions.count)] Processing transaction:")
            print(String(repeating: "━", count: 50))
            
            let result = try await presentTransactionForLearning(transaction, categories: categories)
            
            if result.ruleCreated {
                rulesCreated += 1
            }
            
            processedCount += 1
            
            // Ask if user wants to continue
            if index < transactions.count - 1 {
                let shouldContinue = InteractiveInput.readConfirmation(
                    prompt: "Continue to next transaction?",
                    defaultValue: true
                )
                
                if !shouldContinue {
                    break
                }
            }
        }
        
        print("\n🎉 Learning session complete!")
        print("Processed: \(processedCount) transactions")
        print("Rules created: \(rulesCreated)")
    }
    
    private func presentTransactionForLearning(
        _ transaction: UpTransaction,
        categories: [YNABCategory]
    ) async throws -> (ruleCreated: Bool, skipped: Bool) {
        
        // Display transaction details
        print("💰 Amount: \(transaction.amount.formattedValue)")
        print("📅 Date: \(DateFormatter.display.string(from: transaction.settledAt ?? transaction.createdAt))")
        print("🏪 Description: \(transaction.displayDescription)")
        if let rawText = transaction.rawText, rawText != transaction.description {
            print("📝 Raw text: \(rawText)")
        }
        if let message = transaction.message, !message.isEmpty {
            print("💬 Message: \(message)")
        }
        
        // Extract merchant pattern
        let merchantPattern = merchantLearningService.extractMerchantPattern(from: transaction)
        print("🔍 Detected pattern: \(merchantPattern)")
        
        // Check if pattern is obvious and auto-approve if requested
        if autoApprove && isObviousPattern(merchantPattern) {
            if let autoCategory = suggestCategoryForPattern(merchantPattern, categories: categories) {
                displayInfo("Auto-approving obvious pattern: \(merchantPattern) → \(autoCategory.displayName)")
                
                let payeeName = cleanPayeeName(transaction.displayDescription)
                try merchantLearningService.createMerchantRule(
                    pattern: merchantPattern,
                    categoryId: autoCategory.id,
                    categoryName: autoCategory.displayName,
                    payeeName: payeeName,
                    confidence: 0.9
                )
                
                return (ruleCreated: true, skipped: false)
            }
        }
        
        // Present options to user
        print("\nWhat would you like to do with this transaction?")
        print("1. Create a merchant rule")
        print("2. Skip this transaction")
        print("3. Stop learning session")
        
        let choice = InteractiveInput.readChoice(
            prompt: "Choose an option:",
            choices: ["Create rule", "Skip", "Stop"]
        )
        
        switch choice {
        case "Create rule":
            return try await createMerchantRule(
                for: transaction,
                pattern: merchantPattern,
                categories: categories
            )
        case "Skip":
            return (ruleCreated: false, skipped: true)
        case "Stop":
            throw CLIError.userCancelled
        default:
            return (ruleCreated: false, skipped: true)
        }
    }
    
    private func createMerchantRule(
        for transaction: UpTransaction,
        pattern: String,
        categories: [YNABCategory]
    ) async throws -> (ruleCreated: Bool, skipped: Bool) {
        
        // Filter and present categories
        let activeCategories = categories.filter { $0.isActive }
        let categoryChoices = activeCategories.map { $0.displayName }
        
        print("\nSelect a category for '\(pattern)':")
        
        guard let selectedCategoryName = InteractiveInput.readChoice(
            prompt: "Choose category:",
            choices: categoryChoices
        ) else {
            displayWarning("No category selected, skipping...")
            return (ruleCreated: false, skipped: true)
        }
        
        guard let selectedCategory = activeCategories.first(where: { $0.displayName == selectedCategoryName }) else {
            displayWarning("Category not found")
            return (ruleCreated: false, skipped: true)
        }
        
        // Get payee name
        let defaultPayeeName = cleanPayeeName(transaction.displayDescription)
        print("Payee name (default: '\(defaultPayeeName)'): ", terminator: "")
        let payeeName = InteractiveInput.readLine(prompt: "") ?? defaultPayeeName
        let finalPayeeName = payeeName.isEmpty ? defaultPayeeName : payeeName
        
        // Confirm rule creation
        print("\n📋 Rule Summary:")
        print("Pattern: \(pattern)")
        print("Category: \(selectedCategory.displayName)")
        print("Payee: \(finalPayeeName)")
        
        let confirmed = InteractiveInput.readConfirmation(
            prompt: "Create this rule?",
            defaultValue: true
        )
        
        if !confirmed {
            return (ruleCreated: false, skipped: true)
        }
        
        // Create the rule
        do {
            try merchantLearningService.createMerchantRule(
                pattern: pattern,
                categoryId: selectedCategory.id,
                categoryName: selectedCategory.displayName,
                payeeName: finalPayeeName,
                confidence: 1.0
            )
            
            displaySuccess("Rule created successfully!")
            return (ruleCreated: true, skipped: false)
        } catch {
            displayError(error)
            return (ruleCreated: false, skipped: true)
        }
    }
    
    // MARK: - Learning from YNAB Patterns
    
    private func learnFromYNABPatterns() async throws {
        displayInfo("🔍 Learning from existing YNAB categorization patterns")
        
        // This would analyze existing YNAB transactions to find patterns
        // For now, we'll show a placeholder
        displayInfo("YNAB pattern analysis is not yet implemented")
        displayInfo("Use the regular learning mode to create rules from recent transactions")
    }
    
    // MARK: - Helper Methods
    
    private func isObviousPattern(_ pattern: String) -> Bool {
        let obviousPatterns = [
            "COLES", "WOOLWORTHS", "ALDI", "IGA",
            "MCDONALD", "KFC", "SUBWAY", "PIZZA",
            "NETFLIX", "SPOTIFY", "AMAZON",
            "SHELL", "BP", "CALTEX", "MOBIL",
            "WESTFIELD", "IKEA", "BUNNINGS"
        ]
        
        return obviousPatterns.contains { pattern.uppercased().contains($0) }
    }
    
    private func suggestCategoryForPattern(_ pattern: String, categories: [YNABCategory]) -> YNABCategory? {
        let upperPattern = pattern.uppercased()
        
        // Simple pattern matching for common categories
        if ["COLES", "WOOLWORTHS", "ALDI", "IGA"].contains(where: { upperPattern.contains($0) }) {
            return categories.first { $0.name.lowercased().contains("groceries") || $0.name.lowercased().contains("food") }
        }
        
        if ["SHELL", "BP", "CALTEX", "MOBIL"].contains(where: { upperPattern.contains($0) }) {
            return categories.first { $0.name.lowercased().contains("fuel") || $0.name.lowercased().contains("gas") }
        }
        
        if ["NETFLIX", "SPOTIFY", "AMAZON"].contains(where: { upperPattern.contains($0) }) {
            return categories.first { $0.name.lowercased().contains("entertainment") || $0.name.lowercased().contains("subscription") }
        }
        
        return nil
    }
    
    private func cleanPayeeName(_ description: String) -> String {
        // Remove common transaction noise and return a clean payee name
        let cleaned = description
            .replacingOccurrences(of: "CARD PURCHASE", with: "")
            .replacingOccurrences(of: "EFTPOS", with: "")
            .replacingOccurrences(of: "VISA", with: "")
            .replacingOccurrences(of: "MASTERCARD", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter of each word
        return cleaned.components(separatedBy: .whitespaces)
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    private func displayLearningStats() async throws {
        let stats = try merchantLearningService.getMerchantRuleStats()
        
        print("\n📊 Learning Statistics:")
        print("Total rules: \(stats["total_rules"] ?? 0)")
        print("Used rules: \(stats["used_rules"] ?? 0)")
        print("Total usage: \(stats["total_usage"] ?? 0)")
        
        if verbose {
            let rules = try merchantLearningService.getAllMerchantRules()
            if !rules.isEmpty {
                print("\n📋 Current Rules:")
                for rule in rules.prefix(10) {
                    print("• \(rule.merchantPattern) → \(rule.categoryName) (used \(rule.usageCount) times)")
                }
                if rules.count > 10 {
                    print("... and \(rules.count - 10) more rules")
                }
            }
        }
    }
}

