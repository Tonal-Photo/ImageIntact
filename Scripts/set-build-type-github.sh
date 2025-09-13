#!/bin/bash

# Simple script to set GitHub build type
# Add this as a build phase ONLY to the GitHub scheme

echo "=== GitHub Build Type Script ==="

# Check required environment variables
if [ -z "$BUILT_PRODUCTS_DIR" ] || [ -z "$CONTENTS_FOLDER_PATH" ]; then
    echo "❌ ERROR: Required build environment variables not set"
    echo "BUILT_PRODUCTS_DIR: ${BUILT_PRODUCTS_DIR:-NOT SET}"
    echo "CONTENTS_FOLDER_PATH: ${CONTENTS_FOLDER_PATH:-NOT SET}"
    exit 1
fi

# Ensure Resources directory exists
RESOURCES_DIR="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
echo "Creating directory: $RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR" || { echo "❌ Failed to create Resources directory"; exit 1; }

BUILD_TYPE_FILE="$RESOURCES_DIR/BuildType.txt"

# Write GitHub build type
echo "GitHub" > "$BUILD_TYPE_FILE" || { echo "❌ Failed to write BuildType.txt"; exit 1; }

# Verify file was created
if [ -f "$BUILD_TYPE_FILE" ]; then
    CONTENT=$(cat "$BUILD_TYPE_FILE")
    echo "✅ BuildType.txt created successfully"
    echo "   Path: $BUILD_TYPE_FILE"
    echo "   Content: '$CONTENT'"
else
    echo "❌ ERROR: BuildType.txt was not created"
    exit 1
fi

echo "=== GitHub Build Type Set Successfully ==="