import ArgumentParser
import Foundation

struct RulesCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules",
        abstract: "Manage merchant categorization rules",
        discussion: """
        View, add, edit, and remove merchant categorization rules.
        
        Merchant rules automatically categorize transactions based on patterns 
        detected in transaction descriptions. Rules created with this command 
        are used when syncing with the --categorize flag.
        
        Examples:
        • up-ynab-sync rules --list              # Show all rules
        • up-ynab-sync rules --stats             # Show usage statistics
        • up-ynab-sync rules --add COLES Groceries  # Add new rule
        • up-ynab-sync rules --remove NETFLIX    # Remove rule
        • up-ynab-sync rules --export rules.json # Export rules to file
        • up-ynab-sync rules --import-file rules.json # Import rules from file
        
        Prerequisites:
        • Configuration must be set up (run 'up-ynab-sync config' first)
        • YNAB API token must be available for category validation
        """
    )
    
    @Flag(name: .long, help: "List all merchant rules")
    var list: Bool = false
    
    @Flag(name: .long, help: "Show rule usage statistics")
    var stats: Bool = false
    
    @Option(name: .long, help: "Add new rule: --add MERCHANT_PATTERN")
    var add: String?
    
    @Option(name: .long, help: "Remove rule for merchant pattern")
    var remove: String?
    
    @Option(name: .long, help: "Export rules to JSON file")
    var export: String?
    
    @Option(name: .customLong("import-file"), help: "Import rules from JSON file")
    var importFile: String?
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Force operations without confirmation")
    var force: Bool = false
    
    @Option(name: .long, help: "Specify budget profile for rules (defaults to active profile)")
    var budget: String?
    
    private var merchantLearningService: MerchantLearningService { MerchantLearningService.shared }
    private var ynabService: YNABService { YNABService.shared }
    private var configManager: ConfigManager { ConfigManager.shared }
    
    // MARK: - Budget Profile Helper
    
    private func getBudgetId() throws -> String {
        if let budgetName = budget {
            let profile = try configManager.getProfile(budgetName)
            return profile.ynabBudgetId
        } else {
            let activeProfile = try configManager.getActiveProfile()
            return activeProfile.ynabBudgetId
        }
    }
    
    func run() async throws {
        // Check if any action is specified
        guard list || stats || add != nil || remove != nil || export != nil || importFile != nil else {
            // Default action: list rules
            try await listRules()
            return
        }
        
        // Execute actions in order
        if let importFile = importFile {
            try await importRules(from: importFile)
        }
        
        if let pattern = add {
            try await addRule(pattern: pattern)
        }
        
        if let pattern = remove {
            try await removeRule(pattern: pattern)
        }
        
        if list {
            try await listRules()
        }
        
        if stats {
            try await showStatistics()
        }
        
        if let exportFile = export {
            try await exportRules(to: exportFile)
        }
    }
    
    // MARK: - List Rules
    
    private func listRules() async throws {
        displayInfo("📋 Merchant Categorization Rules")
        
        do {
            let rules = try merchantLearningService.getAllMerchantRules()
            
            if rules.isEmpty {
                displayInfo("No merchant rules found.")
                displayInfo("Use 'up-ynab-sync learn' to create rules from transactions.")
                return
            }
            
            print("")
            print("Found \(rules.count) merchant rules:")
            print(String(repeating: "=", count: 60))
            print("")
            
            for (index, rule) in rules.enumerated() {
                let number = String(format: "%3d", index + 1)
                print("[\(number)] \(rule.merchantPattern)")
                print("     Category: \(rule.categoryName)")
                print("     Payee: \(rule.payeeName)")
                print("     Usage: \(rule.usageCount) times")
                print("     Confidence: \(String(format: "%.1f", rule.confidence * 100))%")
                
                if let lastUsed = rule.lastUsed {
                    if let lastUsedDate = ISO8601DateFormatter().date(from: lastUsed) {
                        print("     Last used: \(DateFormatter.display.string(from: lastUsedDate))")
                    } else {
                        print("     Last used: \(lastUsed)")
                    }
                }
                
                if verbose {
                    print("     Created: \(formatDate(rule.createdAt))")
                    print("     Updated: \(formatDate(rule.updatedAt))")
                    print("     ID: \(rule.id ?? -1)")
                }
                
                print("")
            }
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Statistics
    
    private func showStatistics() async throws {
        displayInfo("📊 Merchant Rules Statistics")
        
        do {
            let stats = try merchantLearningService.getMerchantRuleStats()
            let rules = try merchantLearningService.getAllMerchantRules()
            
            print("")
            print("Overall Statistics:")
            print(String(repeating: "=", count: 40))
            print("Total rules: \(stats["total_rules"] ?? 0)")
            print("Used rules: \(stats["used_rules"] ?? 0)")
            print("Total usage: \(stats["total_usage"] ?? 0)")
            
            if !rules.isEmpty {
                print("")
                print("Top 10 Most Used Rules:")
                print(String(repeating: "-", count: 40))
                
                let sortedRules = rules.sorted { $0.usageCount > $1.usageCount }
                for (index, rule) in sortedRules.prefix(10).enumerated() {
                    let number = String(format: "%2d", index + 1)
                    print("[\(number)] \(rule.merchantPattern) → \(rule.categoryName)")
                    print("     Used \(rule.usageCount) times")
                    print("")
                }
                
                if verbose {
                    print("Category Distribution:")
                    print(String(repeating: "-", count: 40))
                    
                    let categoryGroups = Dictionary(grouping: rules) { $0.categoryName }
                    let sortedCategories = categoryGroups.sorted { $0.value.count > $1.value.count }
                    
                    for (category, categoryRules) in sortedCategories {
                        let totalUsage = categoryRules.reduce(0) { $0 + $1.usageCount }
                        print("\(category): \(categoryRules.count) rules, \(totalUsage) uses")
                    }
                }
            }
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Add Rule
    
    private func addRule(pattern: String) async throws {
        displayInfo("➕ Adding new merchant rule for pattern: \(pattern)")
        
        // Validate prerequisites
        guard configManager.hasConfiguration() else {
            throw CLIError.prerequisiteNotMet("Configuration not found. Please run 'up-ynab-sync config' first.")
        }
        
        do {
            let config = try configManager.loadConfiguration()
            
            // Check if rule already exists
            let existingRule = try merchantLearningService.getMerchantRule(for: UpTransaction.mock(description: pattern))
            if existingRule != nil {
                displayWarning("Rule already exists for pattern: \(pattern)")
                if !force {
                    let shouldContinue = InteractiveInput.readConfirmation(
                        prompt: "Do you want to replace it?",
                        defaultValue: false
                    )
                    if !shouldContinue {
                        return
                    }
                }
            }
            
            // Get categories from YNAB
            displayInfo("Fetching categories from YNAB...")
            let categories = try await ynabService.getCategories(budgetId: config.ynabBudgetId)
            let activeCategories = categories.filter { $0.isActive }
            
            if activeCategories.isEmpty {
                throw CLIError.configurationError("No active categories found in YNAB budget")
            }
            
            // Present category selection
            let categoryChoices = activeCategories.map { $0.displayName }
            
            print("\nSelect a category for '\(pattern)':")
            guard let selectedCategoryName = InteractiveInput.readChoice(
                prompt: "Choose category:",
                choices: categoryChoices
            ) else {
                displayWarning("No category selected, cancelling...")
                return
            }
            
            guard let selectedCategory = activeCategories.first(where: { $0.displayName == selectedCategoryName }) else {
                displayWarning("Category not found")
                return
            }
            
            // Get payee name
            print("Enter payee name for '\(pattern)' (or press Enter for default): ", terminator: "")
            let payeeInput = InteractiveInput.readLine(prompt: "") ?? ""
            let payeeName = payeeInput.isEmpty ? cleanPayeeName(pattern) : payeeInput
            
            // Confirm rule creation
            print("\n📋 Rule Summary:")
            print("Pattern: \(pattern)")
            print("Category: \(selectedCategory.displayName)")
            print("Payee: \(payeeName)")
            
            let confirmed = force || InteractiveInput.readConfirmation(
                prompt: "Create this rule?",
                defaultValue: true
            )
            
            if !confirmed {
                displayInfo("Rule creation cancelled")
                return
            }
            
            // Create the rule
            let budgetId = try getBudgetId()
            try merchantLearningService.createMerchantRule(
                pattern: pattern.uppercased(),
                categoryId: selectedCategory.id,
                categoryName: selectedCategory.displayName,
                payeeName: payeeName,
                confidence: 1.0,
                budgetId: budgetId
            )
            
            displaySuccess("Rule created successfully!")
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Remove Rule
    
    private func removeRule(pattern: String) async throws {
        displayInfo("🗑️ Removing merchant rule for pattern: \(pattern)")
        
        do {
            // Check if rule exists
            let existingRule = try merchantLearningService.getMerchantRule(for: UpTransaction.mock(description: pattern))
            guard let rule = existingRule else {
                displayWarning("No rule found for pattern: \(pattern)")
                return
            }
            
            // Show rule details
            print("\n📋 Rule to be removed:")
            print("Pattern: \(rule.merchantPattern)")
            print("Category: \(rule.categoryName)")
            print("Payee: \(rule.payeeName)")
            print("Usage: \(rule.usageCount) times")
            
            // Confirm deletion
            let confirmed = force || InteractiveInput.readConfirmation(
                prompt: "Are you sure you want to remove this rule?",
                defaultValue: false
            )
            
            if !confirmed {
                displayInfo("Rule removal cancelled")
                return
            }
            
            // Remove the rule
            try merchantLearningService.deleteMerchantRule(pattern: rule.merchantPattern)
            
            displaySuccess("Rule removed successfully!")
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Export Rules
    
    private func exportRules(to filePath: String) async throws {
        displayInfo("📤 Exporting merchant rules to: \(filePath)")
        
        do {
            let rules = try merchantLearningService.getAllMerchantRules()
            
            if rules.isEmpty {
                displayWarning("No rules to export")
                return
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let jsonData = try encoder.encode(rules)
            
            let url = URL(fileURLWithPath: filePath)
            try jsonData.write(to: url)
            
            displaySuccess("Exported \(rules.count) rules to \(filePath)")
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Import Rules
    
    private func importRules(from filePath: String) async throws {
        displayInfo("📥 Importing merchant rules from: \(filePath)")
        
        do {
            let url = URL(fileURLWithPath: filePath)
            let jsonData = try Data(contentsOf: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let rules = try decoder.decode([MerchantRule].self, from: jsonData)
            
            if rules.isEmpty {
                displayWarning("No rules found in file")
                return
            }
            
            print("Found \(rules.count) rules in file")
            
            let confirmed = force || InteractiveInput.readConfirmation(
                prompt: "Import these rules? (existing rules with same patterns will be replaced)",
                defaultValue: false
            )
            
            if !confirmed {
                displayInfo("Import cancelled")
                return
            }
            
            var imported = 0
            let budgetId = try getBudgetId()
            for rule in rules {
                do {
                    try merchantLearningService.createMerchantRule(
                        pattern: rule.merchantPattern,
                        categoryId: rule.categoryId,
                        categoryName: rule.categoryName,
                        payeeName: rule.payeeName,
                        confidence: rule.confidence,
                        budgetId: budgetId
                    )
                    imported += 1
                } catch {
                    logger.warning("Failed to import rule \(rule.merchantPattern): \(error.localizedDescription)")
                }
            }
            
            displaySuccess("Successfully imported \(imported) out of \(rules.count) rules")
            
        } catch {
            displayError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        return DateFormatter.display.string(from: date)
    }
    
    private func cleanPayeeName(_ pattern: String) -> String {
        return pattern.components(separatedBy: .whitespaces)
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Mock Transaction Extension

extension UpTransaction {
    static func mock(description: String) -> UpTransaction {
        return UpTransaction(
            id: UUID().uuidString,
            status: "SETTLED",
            rawText: description,
            description: description,
            message: nil,
            holdInfo: nil,
            roundUp: nil,
            cashback: nil,
            amount: UpAmount(
                currencyCode: "AUD",
                value: "10.00",
                valueInBaseUnits: 1000
            ),
            foreignAmount: nil,
            settledAt: Date(),
            createdAt: Date(),
            relationships: UpTransactionRelationships(
                account: UpRelationshipData(data: nil),
                transferAccount: nil,
                category: nil,
                parentCategory: nil,
                tags: nil
            )
        )
    }
}