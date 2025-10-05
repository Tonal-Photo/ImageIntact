#!/bin/bash

# Fix FileManifestEntry calls in test files

for file in ImageIntactTests/*.swift; do
    echo "Processing $file..."
    
    # Create temp file
    temp_file="${file}.tmp"
    
    # Process the file to add imageWidth and imageHeight parameters
    perl -pe 's/(FileManifestEntry\([^)]+size:\s*\d+(?:\s*\*\s*\d+)?)\s*\)/\1,\n                imageWidth: nil,\n                imageHeight: nil\n            )/g' "$file" > "$temp_file"
    
    # Check if changes were made
    if ! cmp -s "$file" "$temp_file"; then
        mv "$temp_file" "$file"
        echo "  Updated $file"
    else
        rm "$temp_file"
        echo "  No changes needed in $file"
    fi
done

echo "Done!"
