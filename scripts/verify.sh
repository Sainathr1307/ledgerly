#!/usr/bin/env bash
# verify.sh — generate the Xcode project, then build and test Ledgerly on an iPhone simulator.
# Usage: scripts/verify.sh            (picks the first available iPhone simulator on iOS 18 or later)
#        SIM_UDID=<udid> scripts/verify.sh   (use a specific simulator)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/build"
BUILD_LOG="$LOG_DIR/verify-build.log"
TEST_LOG="$LOG_DIR/verify-test.log"
mkdir -p "$LOG_DIR"

fail() {
  echo ""
  echo "FAIL: $1"
  exit 1
}

# --- Tools -------------------------------------------------------------------
if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild not found. Install Xcode 16 or later, then run: sudo xcode-select -s /Applications/Xcode.app"
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  fail "xcodegen not found. Install it with: brew install xcodegen"
fi

# --- Project -----------------------------------------------------------------
echo "==> Generating Ledgerly.xcodeproj with XcodeGen"
xcodegen generate

# --- Simulator ---------------------------------------------------------------
UDID="${SIM_UDID:-}"
if [ -z "$UDID" ]; then
  DEVICE_LIST="$(xcrun simctl list devices available)"
  # Walk the list, remember which runtime section we're in, and take the first iPhone on iOS 18+.
  UDID="$(printf '%s\n' "$DEVICE_LIST" | awk '
    /^-- / {
      major = 0
      if ($2 == "iOS") { split($3, parts, "."); major = parts[1] + 0 }
      next
    }
    major >= 18 && /iPhone/ && found == "" {
      if (match($0, /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/)) {
        found = substr($0, RSTART, RLENGTH)
      }
    }
    END { print found }
  ')"
fi
if [ -z "$UDID" ]; then
  fail "No available iPhone simulator on iOS 18 or later. Add one in Xcode > Settings > Components, or pass SIM_UDID=<udid>."
fi
echo "==> Using simulator $UDID"

# --- Build -------------------------------------------------------------------
BUILD_STATUS="PASS"
echo "==> Building (log: $BUILD_LOG)"
if ! xcodebuild -project Ledgerly.xcodeproj -scheme Ledgerly -destination "id=$UDID" build 2>&1 | tee "$BUILD_LOG"; then
  BUILD_STATUS="FAIL"
fi

# --- Test --------------------------------------------------------------------
TEST_STATUS="SKIPPED"
if [ "$BUILD_STATUS" = "PASS" ]; then
  TEST_STATUS="PASS"
  echo "==> Testing (log: $TEST_LOG)"
  if ! xcodebuild -project Ledgerly.xcodeproj -scheme Ledgerly -destination "id=$UDID" test 2>&1 | tee "$TEST_LOG"; then
    TEST_STATUS="FAIL"
  fi
fi

# --- Summary -----------------------------------------------------------------
# Count distinct warning lines; the same warning is often printed more than once.
WARNING_COUNT="$( (grep -E "warning:" "$BUILD_LOG" || true) | sort -u | wc -l | tr -d ' ')"
ERROR_COUNT="$( (grep -E "error:" "$BUILD_LOG" || true) | sort -u | wc -l | tr -d ' ')"

echo ""
echo "================ Ledgerly verify ================"
echo "Simulator:      $UDID"
echo "Build:          $BUILD_STATUS"
echo "Tests:          $TEST_STATUS"
echo "Build warnings: $WARNING_COUNT"
echo "Build errors:   $ERROR_COUNT"
echo "Logs:           $BUILD_LOG"
if [ "$TEST_STATUS" != "SKIPPED" ]; then
  echo "                $TEST_LOG"
fi
echo "================================================="

if [ "$WARNING_COUNT" != "0" ]; then
  echo "Warnings found in the build log:"
  (grep -E "warning:" "$BUILD_LOG" || true) | sort -u
fi

if [ "$BUILD_STATUS" = "PASS" ] && [ "$TEST_STATUS" = "PASS" ]; then
  if [ "$WARNING_COUNT" = "0" ]; then
    echo "RESULT: PASS"
  else
    echo "RESULT: PASS (build and tests passed, but there are $WARNING_COUNT warnings to fix)"
  fi
  exit 0
fi
echo "RESULT: FAIL"
exit 1
