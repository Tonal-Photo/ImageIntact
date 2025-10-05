#!/bin/bash

# Force reset Core Data store when app crashes due to migration issues
echo "🧹 Force resetting ImageIntact Core Data stores..."

# Find all possible store locations
LOCATIONS=(
    "$HOME/Library/Containers/com.tonalphoto.tech.ImageIntact/Data/Library/Application Support/ImageIntact"
    "$HOME/Library/Containers/com.nothingmagical.ImageIntact/Data/Library/Application Support/ImageIntact"
    "$HOME/Library/Application Support/ImageIntact"
)

for location in "${LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        echo "📁 Found store directory: $location"

        # Remove all database files
        rm -f "$location"/ImageIntactEvents.sqlite*
        rm -f "$location"/ImageIntact.sqlite*
        rm -f "$location"/*.sqlite*

        echo "✅ Cleaned: $location"
    fi
done

echo ""
echo "✅ Core Data stores have been reset"
echo "ℹ️  The app will create fresh databases on next launch"
echo ""
echo "Note: All Vision analysis data has been cleared and will need to be regenerated."