#!/bin/bash
# Reset Core Data stores for ImageIntact

echo "🗑️  Resetting ImageIntact Core Data stores..."

# Find and remove all ImageIntact SQLite databases
find ~/Library -name "ImageIntactEvents.sqlite*" 2>/dev/null | while read file; do
    echo "  Removing: $file"
    rm -f "$file"
done

find ~/Library -name "SystemInfo.sqlite*" 2>/dev/null | while read file; do
    echo "  Removing: $file"
    rm -f "$file"
done

# Also check common locations
rm -rf ~/Library/Containers/com.tigerware.ImageIntact/Data/Library/Application\ Support/*.sqlite* 2>/dev/null
rm -rf ~/Library/Application\ Support/ImageIntact/*.sqlite* 2>/dev/null

echo "✅ Core Data stores reset. The app will create fresh databases on next launch."