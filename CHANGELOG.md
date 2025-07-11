# Changelog

All notable changes to UpYNABSync will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-07-11

### Added - Merchant Learning & Auto-Categorization

- **Interactive Learning System**: New `up-ynab-sync learn` command for creating merchant categorization rules through interactive sessions
- **YNAB Pattern Analysis**: `up-ynab-sync learn --from-ynab` command to analyze existing YNAB categorization patterns and suggest automatic rules
- **Comprehensive Rule Management**: Full `up-ynab-sync rules` command suite with list, add, remove, export, import, and statistics functionality
- **Auto-Categorization During Sync**: New `--categorize` flag for `up-ynab-sync sync` to automatically apply categorization rules
- **Merchant Pattern Recognition**: Sophisticated pattern extraction from transaction descriptions with noise removal and fuzzy matching
- **Confidence Scoring System**: Machine learning-inspired confidence scoring for automatic rule application
- **Categorization Configuration**: New `up-ynab-sync config --categorization` command for configuring auto-categorization settings
- **Performance Review**: `up-ynab-sync review --categorization` command for reviewing rule performance and optimization suggestions

### Enhanced

- **Database Architecture**: Upgraded database schema to version 2 with new tables for merchant rules and categorization history
- **User Interface**: Enhanced all y/n prompts to use consistent lowercase formatting
- **Command Help System**: Updated help text and examples for all commands with comprehensive usage information
- **Error Handling**: Improved error messages and user feedback throughout the learning and categorization process
- **Security**: Enhanced local-only processing emphasis with no cloud services or external data transmission

### Technical

- **Pattern Extraction Engine**: Advanced text processing for merchant name extraction with multiple fallback strategies
- **Database Migration System**: Robust database versioning and migration system for seamless upgrades
- **Fuzzy Matching Algorithm**: Intelligent transaction matching using pattern similarity and confidence scoring
- **Rule Storage**: Efficient SQLite-based storage for categorization rules with usage statistics and performance tracking
- **Memory Management**: Optimized memory usage for large transaction datasets during pattern analysis
- **Logging System**: Enhanced logging with appropriate levels for production use

## [1.0.0] - 2025-07-01

### Added

- **Core Sync Functionality**: Complete transaction synchronization from Up Banking to YNAB
- **API Authentication**: Secure token management with macOS Keychain integration
- **Account Mapping**: Interactive configuration system for mapping Up Banking accounts to YNAB accounts
- **Duplicate Prevention**: Robust duplicate detection and prevention system
- **Transaction Processing**: Intelligent transaction processing with amount conversion and date handling
- **Error Recovery**: Comprehensive error handling and recovery mechanisms
- **Status Monitoring**: System health checks and sync status reporting
- **Review System**: Failed transaction review and resolution tools
- **Launch Agent Integration**: Automatic daily syncing with macOS Launch Agent
- **Configuration Management**: JSON-based configuration with validation and error handling
- **Logging System**: Comprehensive logging with rotation and level management
- **CLI Interface**: Full command-line interface with help system and argument parsing
- **Data Security**: Local-only processing with secure API token storage
- **Transaction History**: SQLite database for tracking synced transactions and preventing duplicates
- **Bulk Operations**: Efficient bulk transaction processing and API rate limiting
- **Date Range Support**: Flexible date range selection for syncing historical transactions
- **Dry Run Mode**: Preview functionality for testing sync operations without making changes
- **Reset Functionality**: Complete system reset capability for troubleshooting and fresh starts

### Technical

- **Swift 5.9 Compatibility**: Built with latest Swift language features and best practices
- **macOS 12+ Support**: Native macOS integration with system services and Keychain
- **SQLite Database**: Efficient local data storage with proper schema management
- **REST API Integration**: Robust integration with both Up Banking and YNAB APIs
- **Argument Parser**: Professional CLI interface using Swift ArgumentParser
- **Error Handling**: Comprehensive error types and user-friendly error messages
- **Async/Await Support**: Modern asynchronous programming patterns throughout
- **Memory Efficiency**: Optimized memory usage for processing large transaction datasets
- **Unit Testing**: Comprehensive test suite for core functionality
- **Documentation**: Extensive inline documentation and README

---

## Release Notes

### v1.1.0 Highlights

The v1.1.0 release introduces **Merchant Learning & Auto-Categorization**, a major new feature that transforms how you categorize transactions. This intelligent system learns from your habits and automatically categorizes future transactions, making your budgeting workflow seamless and efficient.

**Key Benefits:**
- **Save Time**: Automatically categorize recurring transactions
- **Improve Accuracy**: Learn from your existing categorization patterns
- **Maintain Privacy**: All processing happens locally on your device
- **Easy Management**: Simple commands to view, edit, and optimize your rules

**Migration Notes:**
- Database will automatically upgrade from v1 to v2 on first run
- All existing functionality remains unchanged
- New categorization features are opt-in and don't affect existing workflows

### v1.0.0 Highlights

The initial release of UpYNABSync provides a complete solution for synchronizing transactions from Up Banking to YNAB with enterprise-grade reliability and security.

**Core Features:**
- **Automated Syncing**: Set up once and forget - automatic daily synchronization
- **Secure**: API tokens stored securely, all processing happens locally
- **Reliable**: Robust error handling and recovery mechanisms
- **Flexible**: Support for multiple account mappings and date ranges
- **Professional**: Clean CLI interface with comprehensive help system

---

## Upgrade Instructions

### From v1.0.0 to v1.1.0

1. **Update the binary**: Replace your existing `up-ynab-sync` binary with the new version
2. **Database Migration**: The database will automatically upgrade on first run
3. **New Features**: Explore the new merchant learning commands:
   ```bash
   up-ynab-sync learn --help
   up-ynab-sync rules --help
   ```

### Compatibility

- **Forward Compatible**: v1.1.0 maintains full compatibility with v1.0.0 configurations
- **Database Migration**: Automatic and safe database schema upgrades
- **Configuration Files**: Existing configuration files work without modification
- **API Tokens**: No need to re-authenticate - existing tokens continue to work

---

## Support

For issues, feature requests, or questions about any version, please use the [GitHub issue tracker](https://github.com/yourusername/UpYNABSync/issues).

## Contributing

We welcome contributions! Please see the [README.md](README.md) for contribution guidelines.