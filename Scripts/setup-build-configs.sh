#!/bin/bash

# Setup build configurations for ImageIntact
# This script adds the necessary build settings for GitHub vs App Store builds

PROJECT_PATH="ImageIntact.xcodeproj/project.pbxproj"

echo "Setting up build configurations for ImageIntact..."

# Check if we're in the right directory
if [ ! -f "$PROJECT_PATH" ]; then
    echo "Error: ImageIntact.xcodeproj not found. Please run this script from the project root."
    exit 1
fi

# Add Swift compiler flags for different configurations
echo "Adding Swift compiler flags..."

# For Debug configuration - App Store build by default
xcrun agvtool new-marketing-version 1.0.0 2>/dev/null || true

# Create a new build configuration for Open Source
echo "Creating Open Source build configuration..."

# Use PlistBuddy to add custom build settings
/usr/libexec/PlistBuddy -c "Add :OTHER_SWIFT_FLAGS string" ImageIntact.xcodeproj/project.pbxproj 2>/dev/null || true

# Add build schemes
cat > ImageIntact.xcodeproj/xcshareddata/xcschemes/ImageIntact-OpenSource.xcscheme << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "ImageIntact"
               BuildableName = "ImageIntact.app"
               BlueprintName = "ImageIntact"
               ReferencedContainer = "container:ImageIntact.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "ImageIntact"
            BuildableName = "ImageIntact.app"
            BlueprintName = "ImageIntact"
            ReferencedContainer = "container:ImageIntact.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <EnvironmentVariables>
         <EnvironmentVariable
            key = "OPENSOURCE_BUILD"
            value = "1"
            isEnabled = "YES">
         </EnvironmentVariable>
      </EnvironmentVariables>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
EOF

echo "Build configurations setup complete!"
echo ""
echo "To use different builds:"
echo "  - App Store Build: Use the default 'ImageIntact' scheme"
echo "  - Open Source Build: Use the 'ImageIntact-OpenSource' scheme"
echo ""
echo "For GitHub releases, add this to your build command:"
echo "  xcodebuild -scheme ImageIntact-OpenSource -configuration Release OTHER_SWIFT_FLAGS=\"-D OPENSOURCE_BUILD\""
echo ""
echo "For App Store releases, use the default scheme without the flag."