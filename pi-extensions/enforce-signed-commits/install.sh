#!/usr/bin/env bash
#
# Quick install script for enforce-signed-commits extension
# Usage: ./install.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "🔒 Installing enforce-signed-commits extension..."
echo ""

# Install the pre-commit hook
HOOK_DEST="$GIT_ROOT/.git/hooks/pre-commit"

if [ -f "$HOOK_DEST" ]; then
    echo "⚠️  Backing up existing pre-commit hook..."
    cp "$HOOK_DEST" "$HOOK_DEST.backup.$(date +%Y%m%d%H%M%S)"
fi

cp "$SCRIPT_DIR/hooks/pre-commit" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "✓ Pre-commit hook installed"
echo ""

# Run setup to configure Git
echo "Running setup..."
"$SCRIPT_DIR/setup.sh"

echo ""
echo "✅ Installation complete!"
