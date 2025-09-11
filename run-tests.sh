#!/bin/bash

# Run ImageIntact Tests
# This script runs the Fast test plan which includes all critical tests

echo "🧪 Running ImageIntact Test Suite..."
echo "=================================="

# Run tests with the Fast test plan
xcodebuild test \
    -scheme "ImageIntact" \
    -testPlan "Fast" \
    -destination 'platform=macOS' \
    2>&1 | grep -E "Test case.*passed|Test case.*failed|TEST.*" | tee test-results.txt

# Count results
PASSED=$(grep -c "passed" test-results.txt 2>/dev/null || echo "0")
FAILED=$(grep -c "failed" test-results.txt 2>/dev/null || echo "0")

echo ""
echo "=================================="
echo "📊 Test Results Summary:"
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"

# Cleanup
rm -f test-results.txt

# Exit with error if any tests failed
if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "⚠️  Some tests failed. Please review the output above."
    exit 1
else
    echo ""
    echo "🎉 All tests passed!"
    exit 0
fi