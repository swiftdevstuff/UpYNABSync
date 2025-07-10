import ArgumentParser
import Foundation

struct AuthCommand: AsyncParsableCommand, BaseCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Set up API token authentication for Up Banking and YNAB",
        discussion: """
        This command helps you set up secure authentication for both Up Banking and YNAB APIs.
        
        You'll need:
        1. Up Banking Personal Access Token (from Up Banking app)
        2. YNAB Personal Access Token (from YNAB account settings)
        
        All tokens are stored securely in your macOS Keychain.
        
        To get your tokens:
        • Up Banking: Open the Up app → Settings → API → Create Personal Access Token
        • YNAB: Log into YNAB → My Account → Developer Settings → Personal Access Tokens
        """
    )
    
    @Flag(name: .shortAndLong, help: "Clear all existing tokens and start fresh")
    var reset: Bool = false
    
    @Flag(name: .shortAndLong, help: "Test existing tokens without setting new ones")
    var test: Bool = false
    
    @Flag(name: .shortAndLong, help: "Only set Up Banking token")
    var upOnly: Bool = false
    
    @Flag(name: .shortAndLong, help: "Only set YNAB token")
    var ynabOnly: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    private var keychain: KeychainManager { KeychainManager.shared }
    private var upBankingService: UpBankingService { UpBankingService.shared }
    private var ynabService: YNABService { YNABService.shared }
    
    func run() async throws {
        try await validatePrerequisites()
        
        if test {
            try await testExistingTokens()
            return
        }
        
        if reset {
            try await resetTokens()
        }
        
        if !upOnly && !ynabOnly {
            displayInfo("Setting up authentication for both Up Banking and YNAB")
            try await setupUpBankingAuth()
            try await setupYNABAuth()
        } else if upOnly {
            displayInfo("Setting up Up Banking authentication only")
            try await setupUpBankingAuth()
        } else if ynabOnly {
            displayInfo("Setting up YNAB authentication only")
            try await setupYNABAuth()
        }
        
        // Test the tokens after setup
        try await testAllTokens()
        
        displaySuccess("Authentication setup complete! You can now run 'up-ynab-sync config' to set up account mappings.")
    }
    
    func validatePrerequisites() async throws {
        // No specific prerequisites for auth command
    }
    
    // MARK: - Up Banking Authentication
    
    private func setupUpBankingAuth() async throws {
        displayInfo("Setting up Up Banking authentication...")
        
        // Check if token already exists
        if keychain.hasToken(service: KeychainManager.upBankingService) && !reset {
            let shouldReplace = InteractiveInput.readConfirmation(
                prompt: "Up Banking token already exists. Replace it?",
                defaultValue: false
            )
            
            if !shouldReplace {
                displayInfo("Keeping existing Up Banking token")
                return
            }
        }
        
        // Display instructions
        print("""
        
        📱 Up Banking API Token Setup
        
        To get your Up Banking Personal Access Token:
        1. Open the Up Banking app on your phone
        2. Go to Settings → API
        3. Tap "Create Personal Access Token"
        4. Give it a name (e.g., "YNAB Sync")
        5. Copy the token (it starts with "up:yeah:")
        
        Note: The token will only be shown once, so make sure to copy it!
        
        """)
        
        // Get token from user
        guard let token = InteractiveInput.readSecureLine(prompt: "Enter your Up Banking token: ") else {
            throw CLIError.userCancelled
        }
        
        if token.isEmpty {
            throw CLIError.invalidInput("Token cannot be empty")
        }
        
        // Basic validation
        if !token.starts(with: "up:yeah:") {
            displayWarning("Token doesn't start with 'up:yeah:' - this might not be a valid Up Banking token")
            let shouldContinue = InteractiveInput.readConfirmation(
                prompt: "Continue anyway?",
                defaultValue: false
            )
            
            if !shouldContinue {
                throw CLIError.userCancelled
            }
        }
        
        // Save token to keychain
        do {
            try keychain.saveUpBankingToken(token)
            displaySuccess("Up Banking token saved securely")
        } catch {
            throw CLIError.authenticationError("Failed to save Up Banking token: \(error.localizedDescription)")
        }
        
        // Test the token
        try await testUpBankingToken()
    }
    
    private func testUpBankingToken() async throws {
        displayInfo("Testing Up Banking connection...")
        
        do {
            let isConnected = try await upBankingService.testConnection()
            
            if isConnected {
                displaySuccess("Up Banking connection successful!")
                
                if verbose {
                    let accounts = try await upBankingService.getAccounts()
                    displayInfo("Found \(accounts.count) Up Banking accounts:")
                    for account in accounts {
                        print("  • \(account.displayName) (\(account.accountType)): \(account.balance.formattedValue)")
                    }
                }
            } else {
                throw CLIError.authenticationError("Up Banking connection test failed")
            }
        } catch {
            throw CLIError.authenticationError("Failed to test Up Banking connection: \(error.localizedDescription)")
        }
    }
    
    // MARK: - YNAB Authentication
    
    private func setupYNABAuth() async throws {
        displayInfo("Setting up YNAB authentication...")
        
        // Check if token already exists
        if keychain.hasToken(service: KeychainManager.ynabService) && !reset {
            let shouldReplace = InteractiveInput.readConfirmation(
                prompt: "YNAB token already exists. Replace it?",
                defaultValue: false
            )
            
            if !shouldReplace {
                displayInfo("Keeping existing YNAB token")
                return
            }
        }
        
        // Display instructions
        print("""
        
        💰 YNAB API Token Setup
        
        To get your YNAB Personal Access Token:
        1. Log into your YNAB account at https://app.ynab.com
        2. Go to My Account → Developer Settings
        3. Click "New Token"
        4. Give it a name (e.g., "Up Banking Sync")
        5. Copy the token
        
        Note: The token will only be shown once, so make sure to copy it!
        
        """)
        
        // Get token from user
        guard let token = InteractiveInput.readSecureLine(prompt: "Enter your YNAB token: ") else {
            throw CLIError.userCancelled
        }
        
        if token.isEmpty {
            throw CLIError.invalidInput("Token cannot be empty")
        }
        
        // Basic validation - YNAB tokens are typically 64 characters
        if token.count < 32 {
            displayWarning("Token seems unusually short - this might not be a valid YNAB token")
            let shouldContinue = InteractiveInput.readConfirmation(
                prompt: "Continue anyway?",
                defaultValue: false
            )
            
            if !shouldContinue {
                throw CLIError.userCancelled
            }
        }
        
        // Save token to keychain
        do {
            try keychain.saveYNABToken(token)
            displaySuccess("YNAB token saved securely")
        } catch {
            throw CLIError.authenticationError("Failed to save YNAB token: \(error.localizedDescription)")
        }
        
        // Test the token
        try await testYNABToken()
    }
    
    private func testYNABToken() async throws {
        displayInfo("Testing YNAB connection...")
        
        do {
            let isConnected = try await ynabService.testConnection()
            
            if isConnected {
                displaySuccess("YNAB connection successful!")
                
                if verbose {
                    let budgets = try await ynabService.getBudgets()
                    displayInfo("Found \(budgets.count) YNAB budgets:")
                    for budget in budgets {
                        print("  • \(budget.name)")
                    }
                }
            } else {
                throw CLIError.authenticationError("YNAB connection test failed")
            }
        } catch {
            throw CLIError.authenticationError("Failed to test YNAB connection: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Token Management
    
    private func resetTokens() async throws {
        displayWarning("Resetting all tokens...")
        
        let shouldReset = InteractiveInput.readConfirmation(
            prompt: "This will delete all stored tokens. Are you sure?",
            defaultValue: false
        )
        
        if !shouldReset {
            throw CLIError.userCancelled
        }
        
        do {
            try keychain.deleteToken(service: KeychainManager.upBankingService)
            try keychain.deleteToken(service: KeychainManager.ynabService)
            displaySuccess("All tokens cleared")
        } catch {
            displayWarning("Some tokens may not have been cleared: \(error.localizedDescription)")
        }
    }
    
    private func testExistingTokens() async throws {
        displayInfo("Testing existing tokens...")
        
        let hasUpToken = keychain.hasToken(service: KeychainManager.upBankingService)
        let hasYnabToken = keychain.hasToken(service: KeychainManager.ynabService)
        
        if !hasUpToken && !hasYnabToken {
            displayWarning("No tokens found. Run 'up-ynab-sync auth' to set up authentication.")
            return
        }
        
        if hasUpToken {
            do {
                try await testUpBankingToken()
            } catch {
                displayError(error)
            }
        } else {
            displayWarning("No Up Banking token found")
        }
        
        if hasYnabToken {
            do {
                try await testYNABToken()
            } catch {
                displayError(error)
            }
        } else {
            displayWarning("No YNAB token found")
        }
    }
    
    private func testAllTokens() async throws {
        displayInfo("Testing all tokens...")
        
        var allGood = true
        
        // Test Up Banking
        if keychain.hasToken(service: KeychainManager.upBankingService) {
            do {
                try await testUpBankingToken()
            } catch {
                allGood = false
                displayError(error)
            }
        }
        
        // Test YNAB
        if keychain.hasToken(service: KeychainManager.ynabService) {
            do {
                try await testYNABToken()
            } catch {
                allGood = false
                displayError(error)
            }
        }
        
        if allGood {
            displaySuccess("All tokens are working correctly!")
        } else {
            displayWarning("Some tokens have issues. Please check the errors above.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func displayTokenStatus() {
        let hasUpToken = keychain.hasToken(service: KeychainManager.upBankingService)
        let hasYnabToken = keychain.hasToken(service: KeychainManager.ynabService)
        
        print("Token Status:")
        print("  Up Banking: \(hasUpToken ? "✅ Set" : "❌ Not set")")
        print("  YNAB: \(hasYnabToken ? "✅ Set" : "❌ Not set")")
        print()
    }
}