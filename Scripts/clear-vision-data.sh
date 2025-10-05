#!/bin/bash

# Script to clear Vision Framework analysis data from Core Data
# This allows re-analyzing images that have already been processed

echo "🧹 Clearing Vision Framework analysis data..."
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

# Clear Vision-related tables
echo "🗑️  Clearing Vision data..."

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
SELECT 'Image Metadata:', COUNT(*) FROM ZIMAGEMETADATA;
SELECT 'Detected Objects:', COUNT(*) FROM ZDETECTEDOBJECT;
SELECT 'Scene Classifications:', COUNT(*) FROM ZSCENECLASSIFICATION;
SELECT 'Face Rectangles:', COUNT(*) FROM ZFACERECTANGLE;
SELECT 'EXIF Data:', COUNT(*) FROM ZEXIFDATA;
EOF

echo ""
echo "✅ Vision data cleared successfully!"
echo ""
echo "📝 Note: The next backup will re-analyze all images with Vision Framework"
echo "💡 Backup created at: $BACKUP_PATH (in case you need to restore)"