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

### Option 1: Homebrew (Recommended)

1. **Add the tap**
   ```bash
   brew tap swiftdevstuff/upynabsync
   ```

2. **Install UpYNABSync**
   ```bash
   brew install up-ynab-sync
   ```
3. **Verify installation**
   ```bash
   up-ynab-sync --version
   ```

### Option 2: Build from Source

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

## 🧠 Merchant Learning & Auto-Categorization

UpYNABSync includes powerful AI-driven merchant learning capabilities that automatically categorize transactions based on patterns, making your budgeting workflow seamless and intelligent.

### ✨ Quick Start

Transform your transaction categorization in 4 simple steps:

1. **Learn from recent transactions**
   ```bash
   up-ynab-sync learn
   ```
   Analyze your recent Up Banking transactions and interactively create categorization rules.

2. **Learn from existing YNAB patterns**
   ```bash
   up-ynab-sync learn --from-ynab
   ```
   Analyze your existing YNAB categorization to automatically suggest rules.

3. **Enable auto-categorization**
   ```bash
   up-ynab-sync config --categorization
   ```
   Configure auto-categorization settings including confidence thresholds.

4. **Sync with categorization**
   ```bash
   up-ynab-sync sync --categorize
   ```
   Apply categorization rules during sync for automatic transaction categorization.

### 🎯 Managing Rules

**View and manage your categorization rules:**

```bash
# View all rules with usage statistics
up-ynab-sync rules --list

# View detailed statistics
up-ynab-sync rules --stats

# Add a new rule manually
up-ynab-sync rules --add "COLES" --category "Groceries"

# Remove a rule
up-ynab-sync rules --remove "COLES"

# Export rules for backup
up-ynab-sync rules --export my-rules-backup.json

# Import rules from backup
up-ynab-sync rules --import-file my-rules-backup.json
```

### 🔍 How It Works

The merchant learning system uses sophisticated pattern recognition:

1. **Pattern Extraction**: Extracts merchant patterns from transaction descriptions, removing noise like "CARD PURCHASE" and transaction IDs
2. **Smart Matching**: Matches transactions against your categorization rules using fuzzy matching
3. **Confidence Scoring**: Each match gets a confidence score based on pattern strength and historical accuracy
4. **Automatic Application**: High-confidence matches (≥70%) are automatically applied during sync
5. **Continuous Learning**: The system learns from your corrections and improves over time

### 💡 Example Workflow

Here's how a typical merchant learning workflow looks:

```bash
# Start by learning from recent transactions
$ up-ynab-sync learn --days 14

# Interactive session begins
Processing transaction: -$67.50 from "COLES SUPERMARKET RICHMOND"
Detected pattern: COLES
Select category: Groceries

# Create rule and continue...
Rule created: COLES → Groceries

# Learn from existing YNAB patterns
$ up-ynab-sync learn --from-ynab --days 60

# Found 15 potential patterns
Pattern 'SHELL' appears 8 times with 100% consistency in category 'Transport:Fuel'
Create rule? (y/n): y

# Enable auto-categorization
$ up-ynab-sync config --categorization
Auto-apply during sync? (y/n): y
Minimum confidence threshold (0.0-1.0): 0.7

# Sync with categorization
$ up-ynab-sync sync --categorize

# Results
✅ Synced 12 transactions
🎯 Auto-categorized 8 transactions using merchant rules
📊 3 new transactions ready for manual categorization
```

### 🎨 Advanced Usage

**Advanced learning options:**

```bash
# Learn from longer time periods
up-ynab-sync learn --from-ynab --days 90

# Auto-approve obvious patterns
up-ynab-sync learn --auto-approve

# Process more transactions in learning session
up-ynab-sync learn --limit 50

# Learn with verbose output
up-ynab-sync learn --verbose
```

**Advanced rule management:**

```bash
# View detailed rule statistics
up-ynab-sync rules --stats --verbose

# Export rules with metadata
up-ynab-sync rules --export --include-stats

# Remove unused rules
up-ynab-sync rules --cleanup
```

### 🔒 Privacy & Security

- **Local-only processing**: All pattern analysis and learning happens on your device
- **No cloud services**: Your financial data never leaves your machine
- **Secure storage**: Rules stored in encrypted local database
- **Open source**: Full transparency - you can audit the code yourself

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `up-ynab-sync auth` | Set up API authentication for Up Banking and YNAB |
| `up-ynab-sync config` | Configure account mappings between Up Banking and YNAB |
| `up-ynab-sync sync` | Perform transaction sync with optional categorization |
| `up-ynab-sync status` | Check system health and performance metrics |
| `up-ynab-sync review` | Review and fix failed transactions |

### Merchant Learning Commands

| Command | Description |
|---------|-------------|
| `up-ynab-sync learn` | Interactive merchant categorization rule creation |
| `up-ynab-sync learn --from-ynab` | Analyze existing YNAB patterns for rule suggestions |
| `up-ynab-sync learn --auto-approve` | Auto-approve obvious merchant patterns |
| `up-ynab-sync rules --list` | View all categorization rules |
| `up-ynab-sync rules --stats` | View rule performance statistics |
| `up-ynab-sync rules --add` | Manually add a new categorization rule |
| `up-ynab-sync rules --remove` | Remove a categorization rule |
| `up-ynab-sync rules --export` | Export rules to JSON file |
| `up-ynab-sync rules --import-file` | Import rules from JSON file |

### Configuration Commands

| Command | Description |
|---------|-------------|
| `up-ynab-sync config --categorization` | Configure categorization settings |
| `up-ynab-sync sync --categorize` | Sync with automatic categorization |
| `up-ynab-sync review --categorization` | Review categorization performance |

### Automation Commands

| Command | Description |
|---------|-------------|
| `up-ynab-sync install` | Set up automatic daily syncing with Launch Agent |
| `up-ynab-sync reset` | Reset all configuration and data |

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
