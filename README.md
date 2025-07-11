# UpYNABSync

[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS 12+](https://img.shields.io/badge/macOS-12+-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful macOS CLI tool that automatically syncs transactions from Up Banking to YNAB (You Need A Budget) with intelligent merchant categorization.

## Features

- **Automatic Transaction Syncing**: Seamlessly sync transactions from Up Banking to YNAB
- **Smart Merchant Categorization**: AI-powered categorization learns from your habits
- **Duplicate Prevention**: Robust duplicate detection prevents sync conflicts
- **Automated Scheduling**: Set up automatic daily syncing with macOS Launch Agents
- **Comprehensive Monitoring**: Status monitoring and error handling with detailed reporting
- **Flexible Configuration**: Map multiple Up Banking accounts to YNAB accounts
- **Secure**: API tokens stored securely in macOS Keychain

## Quick Start

### Prerequisites

- macOS 12 or later
- Up Banking account with API access
- YNAB account with API access
- Swift 5.9+ (for building from source)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/swiftdevstuff/UpYNABSync.git
   cd UpYNABSync
   ```

2. **Build the project**
   ```bash
   swift build -c release
   ```

3. **Install the binary**
   ```bash
   cp .build/release/up-ynab-sync /usr/local/bin/
   ```

### Setup

1. **Set up API tokens**
   ```bash
   up-ynab-sync auth
   ```
   You'll need:
   - Up Banking API token (from Up Banking app)
   - YNAB API token (from YNAB account settings)

2. **Configure account mappings**
   ```bash
   up-ynab-sync config
   ```
   Map your Up Banking accounts to YNAB accounts through an interactive process.

3. **Perform your first sync**
   ```bash
   up-ynab-sync sync
   ```

4. **Set up automatic syncing** (optional)
   ```bash
   up-ynab-sync install
   ```

## Smart Categorization

UpYNABSync includes powerful merchant learning capabilities that can automatically categorize transactions based on patterns.

### Getting Started with Categorization

1. **Learn from recent transactions**
   ```bash
   up-ynab-sync learn
   ```
   This analyzes your recent Up Banking transactions and helps you create categorization rules.

2. **Learn from existing YNAB patterns**
   ```bash
   up-ynab-sync learn --from-ynab
   ```
   This analyzes your existing YNAB categorization to suggest automatic rules.

3. **Enable categorization**
   ```bash
   up-ynab-sync config --categorization
   ```
   Configure auto-categorization settings including confidence thresholds.

4. **Sync with categorization**
   ```bash
   up-ynab-sync sync --categorize
   ```
   Apply categorization rules during sync.

### Managing Categorization Rules

- **View all rules**: `up-ynab-sync rules --list`
- **Add new rule**: `up-ynab-sync rules --add "MERCHANT_NAME"`
- **Remove rule**: `up-ynab-sync rules --remove "MERCHANT_NAME"`
- **Export rules**: `up-ynab-sync rules --export rules.json`
- **Import rules**: `up-ynab-sync rules --import-file rules.json`
- **View statistics**: `up-ynab-sync rules --stats`

### How Categorization Works

1. **Pattern Extraction**: The system extracts merchant patterns from transaction descriptions
2. **Rule Matching**: Transactions are matched against your categorization rules
3. **Confidence Scoring**: Each match gets a confidence score based on pattern strength
4. **Automatic Application**: High-confidence matches are automatically applied
5. **Learning**: The system learns from your corrections and improves over time

## Commands

### Core Commands

- `up-ynab-sync auth` - Set up API authentication
- `up-ynab-sync config` - Configure account mappings
- `up-ynab-sync sync` - Perform transaction sync
- `up-ynab-sync status` - Check system health
- `up-ynab-sync review` - Review and fix failed transactions

### Categorization Commands

- `up-ynab-sync learn` - Create merchant categorization rules
- `up-ynab-sync rules` - Manage categorization rules
- `up-ynab-sync config --categorization` - Configure categorization settings
- `up-ynab-sync review --categorization` - Review categorization performance

### Automation Commands

- `up-ynab-sync install` - Set up automatic daily syncing
- `up-ynab-sync reset` - Reset all configuration and data

## Configuration

### Account Mappings

Account mappings are stored in `~/.up-ynab-sync/config.json`:

```json
{
  "ynab_budget_id": "your-budget-id",
  "account_mappings": [
    {
      "up_account_id": "up-account-id",
      "up_account_name": "Up Transaction Account",
      "up_account_type": "TRANSACTIONAL",
      "ynab_account_id": "ynab-account-id",
      "ynab_account_name": "Checking"
    }
  ],
  "categorization_settings": {
    "enabled": true,
    "auto_apply_during_sync": true,
    "min_confidence_threshold": 0.7,
    "suggest_new_rules": true
  }
}
```

### Categorization Settings

- **enabled**: Enable/disable categorization
- **auto_apply_during_sync**: Automatically apply rules during sync
- **min_confidence_threshold**: Minimum confidence for auto-application (0.0-1.0)
- **suggest_new_rules**: Show suggestions for new rules during sync

## Monitoring and Troubleshooting

### Status Monitoring

```bash
up-ynab-sync status --verbose
```

Shows:
- Overall system health
- API connection status
- Account mapping status
- Categorization performance
- Recent sync results
- Launch Agent status

### Reviewing Issues

```bash
up-ynab-sync review
```

Helps you:
- Review failed transactions
- Fix balance mismatches
- Handle duplicate transactions
- Resolve configuration issues

### Categorization Review

```bash
up-ynab-sync review --categorization
```

Shows:
- Rule performance statistics
- Unused rules
- Top performing rules
- Category distribution
- Recommendations for improvement

## Advanced Usage

### Sync Options

```bash
# Sync last 7 days
up-ynab-sync sync --days 7

# Sync with categorization
up-ynab-sync sync --categorize

# Dry run (preview only)
up-ynab-sync sync --dry-run

# Full sync with date selection
up-ynab-sync sync --full
```

### Learning Options

```bash
# Learn from last 14 days
up-ynab-sync learn --days 14

# Auto-approve obvious patterns
up-ynab-sync learn --auto-approve

# Learn from YNAB patterns (last 60 days)
up-ynab-sync learn --from-ynab --days 60
```

### Rule Management

```bash
# View detailed rule statistics
up-ynab-sync rules --stats --verbose

# Export rules for backup
up-ynab-sync rules --export my-rules-backup.json

# Import rules (with confirmation)
up-ynab-sync rules --import-file my-rules-backup.json
```

## Data Storage

UpYNABSync stores data in `~/.up-ynab-sync/`:

- `config.json` - Configuration and account mappings
- `sync.db` - SQLite database for transaction history and categorization rules
- `logs/` - Application logs

## Security

- API tokens are stored securely in macOS Keychain
- All data processing occurs locally on your machine
- No data is transmitted to third parties
- Database is encrypted at rest (via macOS file system encryption)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Testing

Run the test suite:

```bash
swift test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Up Banking](https://up.com.au/) for their excellent banking API
- [YNAB](https://www.youneedabudget.com/) for their comprehensive budgeting API
- [ArgumentParser](https://github.com/apple/swift-argument-parser) for CLI argument parsing
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) for database operations

## Support

For issues and feature requests, please use the [GitHub issue tracker](https://github.com/yourusername/UpYNABSync/issues).

---

**Note**: This tool is not affiliated with Up Banking or YNAB. It's an independent project that uses their public APIs.
