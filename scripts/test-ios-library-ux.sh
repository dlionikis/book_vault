#!/bin/bash
# Phase 8 iOS Library UX Testing Script
# Automated testing of Library UX alignment implementation

set -e

SIMULATOR_ID="BD90C9D8-B22D-427D-84D9-58D07550E3CD"
APP_BUNDLE_ID="com.bookvault.BookVault"
SCREENSHOT_DIR="/tmp/bookvault-ios-tests"

echo "📱 Phase 8: iOS Library UX Testing"
echo "===================================="
echo ""

# Create screenshot directory
mkdir -p "$SCREENSHOT_DIR"
echo "📁 Screenshots will be saved to: $SCREENSHOT_DIR"
echo ""

# Function to take screenshot
take_screenshot() {
    local name=$1
    local path="$SCREENSHOT_DIR/$name.png"
    xcrun simctl io "$SIMULATOR_ID" screenshot "$path"
    echo "   ✅ Screenshot saved: $name.png"
}

# Function to wait for UI
wait_for_ui() {
    sleep 2
}

echo "1️⃣  Testing Library Empty State"
echo "--------------------------------"
echo "   • Taking screenshot of Library tab..."
take_screenshot "01-library-empty-state"
wait_for_ui

echo ""
echo "2️⃣  Testing Catalog View"
echo "--------------------------------"
echo "   • Taking screenshot of Catalog tab..."
# Note: Manual tap required to switch to Catalog tab
take_screenshot "02-catalog-view"
wait_for_ui

echo ""
echo "3️⃣  Testing Book Detail View"
echo "--------------------------------"
echo "   • Taking screenshot of BookDetail with Add to Library button..."
take_screenshot "03-book-detail-add-button"
wait_for_ui

echo ""
echo "4️⃣  Testing Add to Library"
echo "--------------------------------"
echo "   • Taking screenshot after adding book..."
take_screenshot "04-book-added-to-library"
wait_for_ui

echo ""
echo "5️⃣  Testing Library with Books"
echo "--------------------------------"
echo "   • Taking screenshot of Library with added book..."
take_screenshot "05-library-with-books"
wait_for_ui

echo ""
echo "6️⃣  Testing In Library Button"
echo "--------------------------------"
echo "   • Taking screenshot of BookDetail with In Library button..."
take_screenshot "06-book-detail-in-library"
wait_for_ui

echo ""
echo "7️⃣  Testing Remove from Library"
echo "--------------------------------"
echo "   • Taking screenshot of remove confirmation dialog..."
take_screenshot "07-remove-confirmation"
wait_for_ui

echo ""
echo "8️⃣  Testing Library After Removal"
echo "--------------------------------"
echo "   • Taking screenshot of Library after book removed..."
take_screenshot "08-library-after-removal"
wait_for_ui

echo ""
echo "✅ Screenshot capture complete!"
echo ""
echo "📊 Manual Testing Required:"
echo "   1. Review screenshots in: $SCREENSHOT_DIR"
echo "   2. Perform interactive tests in simulator"
echo "   3. Test cross-platform sync with web app"
echo "   4. Update test results in: docs/mobile/implementation-phases/PHASE-8-TEST-RESULTS.md"
echo ""
echo "🔗 Open screenshots folder:"
echo "   open $SCREENSHOT_DIR"
