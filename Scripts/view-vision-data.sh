#!/bin/bash

# Script to view Vision Framework analysis data from Core Data

# Find the Core Data store
STORE_PATH=~/Library/Containers/com.tonalphoto.tech.ImageIntact/Data/Library/Application\ Support/ImageIntact/ImageIntactEvents.sqlite

if [ ! -f "$STORE_PATH" ]; then
    echo "Core Data store not found at: $STORE_PATH"
    echo "Looking in alternative locations..."

    # Try old location
    STORE_PATH=~/Library/Containers/com.nothingmagical.ImageIntact/Data/Library/Application\ Support/ImageIntact/ImageIntact.sqlite

    if [ ! -f "$STORE_PATH" ]; then
        # Try non-sandboxed location
        STORE_PATH=~/Library/Application\ Support/ImageIntact/ImageIntactEvents.sqlite

        if [ ! -f "$STORE_PATH" ]; then
            echo "Core Data store not found. Run the app first to create data."
            exit 1
        fi
    fi
fi

echo "Found Core Data store at: $STORE_PATH"
echo ""
echo "=== Vision Analysis Results ==="
echo ""

# Query ImageMetadata table
sqlite3 "$STORE_PATH" <<EOF
.mode column
.headers on
.width 40 10 10 10 30

SELECT
    substr(ZFILEPATH, -40) as File,
    ZIMAGEWIDTH || 'x' || ZIMAGEHEIGHT as Size,
    ZFACECOUNT as Faces,
    CASE ZHASTEXT WHEN 1 THEN 'Yes' ELSE 'No' END as HasText,
    datetime(ZANALYSISDATE + 978307200, 'unixepoch', 'localtime') as AnalyzedAt
FROM ZIMAGEDETADATA
ORDER BY ZANALYSISDATE DESC
LIMIT 20;

.print
.print "=== Scene Classifications (Top 5 per image, last 10 images) ==="
.print

SELECT
    substr(im.ZFILEPATH, -30) as File,
    sc.ZLABEL as Scene,
    printf('%.0f%%', sc.ZCONFIDENCE * 100) as Confidence
FROM ZSCENECLASSIFICATION sc
JOIN ZIMAGEDETADATA im ON sc.ZIMAGEMETADATA = im.Z_PK
WHERE im.Z_PK IN (
    SELECT Z_PK FROM ZIMAGEDETADATA
    ORDER BY ZANALYSISDATE DESC
    LIMIT 10
)
ORDER BY im.ZANALYSISDATE DESC, sc.ZCONFIDENCE DESC;

.print
.print "=== Summary Statistics ==="
.print

SELECT
    COUNT(*) as "Total Images Analyzed",
    SUM(CASE WHEN ZFACECOUNT > 0 THEN 1 ELSE 0 END) as "Images with Faces",
    SUM(CASE WHEN ZHASTEXT = 1 THEN 1 ELSE 0 END) as "Images with Text",
    AVG(ZFACECOUNT) as "Avg Faces per Image"
FROM ZIMAGEDETADATA;

EOF

echo ""
echo "Note: You can also use a SQLite browser app to explore the data:"
echo "  - DB Browser for SQLite (free): https://sqlitebrowser.org"
echo "  - TablePlus (commercial): https://tableplus.com"
echo "  - Base (Mac App Store): https://menial.co.uk/base/"
echo ""
echo "Database location: $STORE_PATH"