#!/bin/bash

# Script to monitor ImageIntact progress debug log

echo "📊 ImageIntact Progress Debug Monitor"
echo "====================================="
echo ""

# Find the debug log file
DEBUG_FILE="$TMPDIR/imageintact_progress_debug.txt"

if [ ! -f "$DEBUG_FILE" ]; then
    echo "⚠️  Debug file not found at: $DEBUG_FILE"
    echo ""
    echo "Please run a backup in ImageIntact first."
    echo "The debug file will be created automatically."
    echo ""
    echo "Waiting for file to be created..."

    # Wait for file to be created
    while [ ! -f "$DEBUG_FILE" ]; do
        sleep 1
    done
    echo "✅ Debug file created!"
fi

echo "📁 Debug log location: $DEBUG_FILE"
echo ""
echo "📊 Monitoring progress updates (press Ctrl+C to stop)..."
echo "====================================="
echo ""

# Monitor the file
tail -f "$DEBUG_FILE"