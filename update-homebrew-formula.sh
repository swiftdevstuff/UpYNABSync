#!/bin/bash

# Homebrew Formula Auto-Updater for UpYNABSync
# Usage: ./update-homebrew-formula.sh v1.2.0

set -e  # Exit on any error

# Configuration - UPDATE THESE IF DIFFERENT
GITHUB_REPO="swiftdevstuff/UpYNABSync"
HOMEBREW_TAP_REPO="swiftdevstuff/homebrew-upynabsync"
FORMULA_NAME="up-ynab-sync"
FORMULA_CLASS="UpYnabSync"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Validate input
VERSION=$1
if [ -z "$VERSION" ]; then
    log_error "Usage: $0 <version>\nExample: $0 v1.2.0"
fi

# Remove 'v' prefix if present for consistency
VERSION_NUMBER="${VERSION#v}"
VERSION_TAG="v${VERSION_NUMBER}"

log_info "Starting Homebrew formula update for ${VERSION_TAG}"

# Step 1: Verify the GitHub release exists
log_info "Verifying GitHub release ${VERSION_TAG} exists..."
RELEASE_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION_TAG}"
if ! curl -sf "$RELEASE_URL" > /dev/null; then
    log_error "GitHub release ${VERSION_TAG} not found. Make sure you've created and pushed the tag first."
fi
log_success "GitHub release ${VERSION_TAG} verified"

# Step 2: Generate SHA256 hash
log_info "Generating SHA256 hash for release archive..."
ARCHIVE_URL="https://github.com/${GITHUB_REPO}/archive/refs/tags/${VERSION_TAG}.tar.gz"
SHA256=$(curl -sL "$ARCHIVE_URL" | shasum -a 256 | cut -d' ' -f1)

if [ -z "$SHA256" ]; then
    log_error "Failed to generate SHA256 hash"
fi

log_success "SHA256 generated: $SHA256"

# Step 3: Clone homebrew tap repository
TEMP_DIR=$(mktemp -d)
TAP_DIR="$TEMP_DIR/homebrew-tap"

log_info "Cloning Homebrew tap repository..."
if ! git clone "https://github.com/${HOMEBREW_TAP_REPO}.git" "$TAP_DIR"; then
    log_error "Failed to clone Homebrew tap repository"
fi

cd "$TAP_DIR"

# Step 4: Update the formula file
FORMULA_FILE="Formula/${FORMULA_NAME}.rb"

log_info "Updating formula file: $FORMULA_FILE"

if [ ! -f "$FORMULA_FILE" ]; then
    log_error "Formula file not found: $FORMULA_FILE"
fi

# Create the updated formula content
cat > "$FORMULA_FILE" << EOF
class ${FORMULA_CLASS} < Formula
  desc "Sync Up Banking transactions to YNAB"
  homepage "https://github.com/${GITHUB_REPO}"
  url "https://github.com/${GITHUB_REPO}/archive/refs/tags/${VERSION_TAG}.tar.gz"
  sha256 "${SHA256}"
  license "MIT"
  version "${VERSION_NUMBER}"

  depends_on :macos
  depends_on xcode: ["12.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/${FORMULA_NAME}"
  end

  test do
    system "#{bin}/${FORMULA_NAME}", "--help"
  end
end
EOF

log_success "Formula file updated"

# Step 5: Commit and push changes
log_info "Committing and pushing changes..."

git add "$FORMULA_FILE"

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "⚠️  No changes detected in formula file"
    echo "Current version might already be ${VERSION_TAG}"
else
    git commit -m "Update ${FORMULA_NAME} to ${VERSION_TAG}"
    
    if ! git push origin main; then
        log_error "Failed to push changes to Homebrew tap repository"
    fi
    
    log_success "Changes pushed to Homebrew tap repository"
fi

# Step 6: Clean up
cd /
rm -rf "$TEMP_DIR"

# Success message
log_success "Homebrew formula update complete! 🎉"
echo
log_info "Users can now update with:"
echo "  brew update && brew upgrade ${FORMULA_NAME}"

