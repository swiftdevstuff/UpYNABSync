import ArgumentParser
import Foundation

@available(macOS 12, *)
struct UpYNABSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up-ynab-sync",
        abstract: "Sync transactions from Up Banking to YNAB",
        discussion: """
        UpYNABSync automatically syncs transactions from Up Banking to YNAB (You Need A Budget).
        
        Getting Started:
        1. Run 'up-ynab-sync auth' to set up your API tokens
        2. Run 'up-ynab-sync config' to configure account mappings
        3. Run 'up-ynab-sync sync' to perform your first sync
        4. Run 'up-ynab-sync install' to set up automatic daily syncing
        
        For help with any command, use --help (e.g., 'up-ynab-sync sync --help')
        """,
        version: "1.0.0",
        subcommands: [
            AuthCommand.self,
            ConfigCommand.self,
            SyncCommand.self,
            StatusCommand.self,
            ReviewCommand.self,
            LearnCommand.self,
            InstallCommand.self,
            ResetCommand.self
        ]
    )
    
    init() {}
    
    func run() async throws {
        // This should never be called since we have subcommands
        print("Use 'up-ynab-sync --help' to see available commands")
    }
}

// MARK: - Base Command Protocol

protocol BaseCommand {
    var logger: Logger { get }
    
    func validatePrerequisites() async throws
    func displayError(_ error: Error)
    func displaySuccess(_ message: String)
    func displayInfo(_ message: String)
    func displayWarning(_ message: String)
}

extension BaseCommand {
    var logger: Logger { Logger.shared }
    
    func validatePrerequisites() async throws {
        // Default implementation - can be overridden by commands
    }
    
    func displayError(_ error: Error) {
        logger.error(error.localizedDescription)
    }
    
    func displaySuccess(_ message: String) {
        logger.info("✅ \(message)")
    }
    
    func displayInfo(_ message: String) {
        logger.info("ℹ️  \(message)")
    }
    
    func displayWarning(_ message: String) {
        logger.warning("⚠️  \(message)")
    }
}

// MARK: - Interactive Input Helpers

struct InteractiveInput {
    static func readLine(prompt: String) -> String? {
        print(prompt, terminator: "")
        return Swift.readLine()
    }
    
    static func readSecureLine(prompt: String) -> String? {
        print(prompt, terminator: "")
        
        // For secure input, we'd ideally use getpass() or similar
        // For now, we'll use regular input but this should be enhanced
        return Swift.readLine()
    }
    
    static func readChoice(prompt: String, choices: [String]) -> String? {
        print(prompt)
        for (index, choice) in choices.enumerated() {
            print("\(index + 1). \(choice)")
        }
        print("Enter choice (1-\(choices.count)): ", terminator: "")
        
        guard let input = Swift.readLine(),
              let choice = Int(input),
              choice >= 1 && choice <= choices.count else {
            return nil
        }
        
        return choices[choice - 1]
    }
    
    static func readChoiceIndex(prompt: String, choices: [String]) -> Int? {
        print(prompt)
        for (index, choice) in choices.enumerated() {
            print("\(index + 1). \(choice)")
        }
        print("Enter choice (1-\(choices.count)): ", terminator: "")
        
        guard let input = Swift.readLine(),
              let choice = Int(input),
              choice >= 1 && choice <= choices.count else {
            return nil
        }
        
        return choice - 1
    }
    
    static func readConfirmation(prompt: String, defaultValue: Bool = false) -> Bool {
        let defaultText = defaultValue ? "Y/n" : "y/N"
        print("\(prompt) (\(defaultText)): ", terminator: "")
        
        guard let input = Swift.readLine() else {
            return defaultValue
        }
        
        if input.isEmpty {
            return defaultValue
        }
        
        return input.lowercased().starts(with: "y")
    }
}

// MARK: - Progress Display

struct ProgressDisplay {
    static func showProgress(_ message: String) {
        print("🔄 \(message)")
    }
    
    static func showSuccess(_ message: String) {
        print("✅ \(message)")
    }
    
    static func showError(_ message: String) {
        print("❌ \(message)")
    }
    
    static func showWarning(_ message: String) {
        print("⚠️  \(message)")
    }
    
    static func showInfo(_ message: String) {
        print("ℹ️  \(message)")
    }
}

// MARK: - Formatting Helpers

extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "AUD"
        return formatter
    }()
}

extension DateFormatter {
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Error Handling

enum CLIError: Error, LocalizedError {
    case userCancelled
    case invalidInput(String)
    case prerequisiteNotMet(String)
    case configurationError(String)
    case authenticationError(String)
    case syncError(String)
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Operation cancelled by user"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .prerequisiteNotMet(let message):
            return "Prerequisite not met: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .syncError(let message):
            return "Sync error: \(message)"
        }
    }
}

// MARK: - Signal Handling

func setupSignalHandlers() {
    signal(SIGINT) { _ in
        print("\n🛑 Operation cancelled by user")
        exit(1)
    }
    
    signal(SIGTERM) { _ in
        print("\n🛑 Operation terminated")
        exit(1)
    }
}

// MARK: - Entry Point

@available(macOS 12, *)
func runMain() async {
    setupSignalHandlers()
    await UpYNABSync.main()
}

if #available(macOS 12, *) {
    await runMain()
} else {
    fatalError("This tool requires macOS 12 or later")
}
