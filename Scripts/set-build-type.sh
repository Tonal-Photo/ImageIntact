#!/bin/bash

# Set build type based on scheme name
# This script should be added as a build phase in Xcode

# Don't exit on error immediately, we want to see what fails
set +e

# Debug: Print all environment variables we need
echo "=== Build Type Script Starting ==="
echo "SCHEME_NAME: ${SCHEME_NAME:-NOT SET}"
echo "BUILT_PRODUCTS_DIR: ${BUILT_PRODUCTS_DIR:-NOT SET}"
echo "CONTENTS_FOLDER_PATH: ${CONTENTS_FOLDER_PATH:-NOT SET}"
echo "CONFIGURATION: ${CONFIGURATION:-NOT SET}"
echo "TARGET_NAME: ${TARGET_NAME:-NOT SET}"
echo "================================="

# Check if required variables are set
if [ -z "$BUILT_PRODUCTS_DIR" ]; then
    echo "❌ ERROR: BUILT_PRODUCTS_DIR is not set"
    exit 1
fi

if [ -z "$CONTENTS_FOLDER_PATH" ]; then
    echo "❌ ERROR: CONTENTS_FOLDER_PATH is not set"
    exit 1
fi

# Ensure Resources directory exists
RESOURCES_DIR="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
echo "Creating Resources directory: $RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to create Resources directory"
    exit 1
fi

BUILD_TYPE_FILE="$RESOURCES_DIR/BuildType.txt"
echo "Build type file path: $BUILD_TYPE_FILE"

# Determine build type based on scheme name
echo "Checking scheme name: '${SCHEME_NAME}'"

if [[ "${SCHEME_NAME}" == *"GitHub"* ]] || [[ "${SCHEME_NAME}" == *"github"* ]]; then
    BUILD_TYPE="GitHub"
    echo "✅ Detected GitHub scheme"
elif [[ "${SCHEME_NAME}" == *"App Store"* ]] || [[ "${SCHEME_NAME}" == *"AppStore"* ]] || [[ "${SCHEME_NAME}" == *"app store"* ]]; then
    BUILD_TYPE="AppStore"
    echo "✅ Detected App Store scheme"
else
    # Default to App Store for safety
    BUILD_TYPE="AppStore"
    echo "ℹ️ Using default App Store build type for scheme: '${SCHEME_NAME}'"
fi

# Write build type to file
echo "Writing build type: $BUILD_TYPE"
echo "$BUILD_TYPE" > "$BUILD_TYPE_FILE"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to write to BuildType.txt"
    exit 1
fi

# Verify file was created and has content
if [ -f "$BUILD_TYPE_FILE" ]; then
    CONTENT=$(cat "$BUILD_TYPE_FILE")
    echo "✅ BuildType.txt created successfully"
    echo "   Path: $BUILD_TYPE_FILE"
    echo "   Content: '$CONTENT'"
    
    # Double check the content is what we expect
    if [ "$CONTENT" != "$BUILD_TYPE" ]; then
        echo "❌ ERROR: File content doesn't match expected build type"
        echo "   Expected: '$BUILD_TYPE'"
        echo "   Got: '$CONTENT'"
        exit 1
    fi
else
    echo "❌ ERROR: BuildType.txt was not created"
    ls -la "$RESOURCES_DIR"
    exit 1
fi

echo "=== Build Type Script Completed Successfully ==="
exit 0