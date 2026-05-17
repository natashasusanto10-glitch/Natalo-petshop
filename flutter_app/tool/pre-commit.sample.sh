#!/bin/sh
# Pre-commit hook sample — jalankan flutter analyze + format check sebelum
# commit. Block commit kalau ada issues, supaya broken code tidak masuk
# git history.
#
# ━━━ Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Dari root repo (parent dari flutter_app/):
#
#   cp flutter_app/tool/pre-commit.sample.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Test setup:
#
#   .git/hooks/pre-commit
#
# Skip emergency:
#
#   git commit --no-verify -m "wip: skip checks"
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -e

FLUTTER_DIR="flutter_app"

# Skip kalau tidak ada perubahan di flutter_app.
if ! git diff --cached --name-only | grep -q "^$FLUTTER_DIR/"; then
  exit 0
fi

echo "🔍 Pre-commit checks for Flutter app..."
cd "$FLUTTER_DIR" || exit 0

# 1. Format check — fail kalau ada file yang belum di-format.
echo "  → dart format check..."
if ! dart format --set-exit-if-changed --output=none . > /dev/null 2>&1; then
  echo "❌ Code formatting issues. Run:"
  echo "   cd $FLUTTER_DIR && dart format ."
  exit 1
fi

# 2. Analyze — fail kalau ada lint/error.
echo "  → flutter analyze..."
ANALYZE_OUTPUT=$(flutter analyze --no-pub --no-fatal-warnings 2>&1)
if ! echo "$ANALYZE_OUTPUT" | tail -3 | grep -q "No issues found"; then
  echo "❌ flutter analyze found issues:"
  echo "$ANALYZE_OUTPUT"
  exit 1
fi

echo "✅ Pre-commit checks passed"
exit 0
