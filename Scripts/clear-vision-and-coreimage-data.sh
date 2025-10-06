#!/bin/bash

# Script to clear Vision Framework AND Core Image analysis data from Core Data
# This allows re-analyzing images that have already been processed

echo "🧹 Clearing Vision Framework and Core Image analysis data..."
echo ""

# Find the SQLite database
DB_PATH="$HOME/Library/Containers/com.tonalphoto.tech.ImageIntact/Data/Library/Application Support/ImageIntact/ImageIntactEvents.sqlite"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    echo ""
    echo "Looking for database in other locations..."

    # Try alternate location
    ALT_DB_PATH="$HOME/Library/Application Support/ImageIntact/ImageIntactEvents.sqlite"
    if [ -f "$ALT_DB_PATH" ]; then
        DB_PATH="$ALT_DB_PATH"
        echo "✅ Found database at: $DB_PATH"
    else
        echo "❌ Could not find database"
        exit 1
    fi
fi

echo "📁 Database location: $DB_PATH"
echo ""

# Backup the database first
BACKUP_PATH="${DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
echo "💾 Creating backup at: $BACKUP_PATH"
cp "$DB_PATH" "$BACKUP_PATH"

# Clear Vision and Core Image related tables
echo "🗑️  Clearing Vision and Core Image data..."

# Check if Core Image tables exist
TABLES=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table';")

sqlite3 "$DB_PATH" <<EOF
-- Delete all Vision analysis data
DELETE FROM ZIMAGEMETADATA;
DELETE FROM ZDETECTEDOBJECT;
DELETE FROM ZSCENECLASSIFICATION;
DELETE FROM ZFACERECTANGLE;
DELETE FROM ZEXIFDATA;

-- Vacuum to reclaim space
VACUUM;

-- Show counts to confirm
SELECT '=== Vision Framework Data ===' AS '';
SELECT 'Image Metadata:', COUNT(*) FROM ZIMAGEMETADATA;
SELECT 'Detected Objects:', COUNT(*) FROM ZDETECTEDOBJECT;
SELECT 'Scene Classifications:', COUNT(*) FROM ZSCENECLASSIFICATION;
SELECT 'Face Rectangles:', COUNT(*) FROM ZFACERECTANGLE;
SELECT 'EXIF Data:', COUNT(*) FROM ZEXIFDATA;
EOF

# Try to clear Core Image tables if they exist
if echo "$TABLES" | grep -q "ZIMAGECOLORANALYSIS"; then
    echo "Clearing Core Image tables..."
    sqlite3 "$DB_PATH" <<EOF
DELETE FROM ZIMAGECOLORANALYSIS;
DELETE FROM ZIMAGEQUALITYMETRICS;
DELETE FROM ZIMAGEHISTOGRAM;
SELECT '' AS '';
SELECT '=== Core Image Data ===' AS '';
SELECT 'Color Analysis:', COUNT(*) FROM ZIMAGECOLORANALYSIS;
SELECT 'Quality Metrics:', COUNT(*) FROM ZIMAGEQUALITYMETRICS;
SELECT 'Histograms:', COUNT(*) FROM ZIMAGEHISTOGRAM;
EOF
else
    echo "Core Image tables not yet created (will be created on first run)"
fi

echo ""
echo "✅ Vision and Core Image data cleared successfully!"
echo ""
echo "📝 Note: The next backup will re-analyze all images"
echo "💡 Backup created at: $BACKUP_PATH (in case you need to restore)"