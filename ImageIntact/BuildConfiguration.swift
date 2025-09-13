//
//  BuildConfiguration.swift
//  ImageIntact
//
//  Build configuration flags and helpers
//

import Foundation

/// Build configuration helper
struct BuildConfiguration {
    
    /// Check if this is an open source build
    static var isOpenSourceBuild: Bool {
        // Check for GitHubBuild.txt resource file
        // This file should only be included in GitHub builds
        if Bundle.main.path(forResource: "GitHubBuild", ofType: "txt") != nil {
            return true
        }
        
        return false
    }
    
    /// Check if this is an App Store build
    static var isAppStoreBuild: Bool {
        return !isOpenSourceBuild
    }
    
    /// Get build edition name
    static var editionName: String {
        if isOpenSourceBuild {
            return "Open Source Edition"
        } else {
            return "App Store Edition"
        }
    }
    
    /// Check if IAP is available
    static var isIAPAvailable: Bool {
        // IAP only available in App Store builds
        return isAppStoreBuild
    }
    
    /// Get the app version with edition suffix
    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        if isOpenSourceBuild {
            return "\(version) (\(build)) - GitHub Edition"
        } else {
            return "\(version) (\(build))"
        }
    }
    
    /// Features available in current build
    static var availableFeatures: String {
        if isOpenSourceBuild {
            return """
            ✅ Manual backup/restore
            ✅ Multi-destination support
            ✅ Checksum verification
            ✅ File organization
            ✅ Duplicate detection
            ✅ All core features
            
            ℹ️ Premium features available in App Store version
            """
        } else {
            return """
            ✅ All Open Source features
            ⭐ Automated backups (Pro)
            ⭐ Smart duplicate detection (Pro)
            ⭐ Cloud destinations (Pro)
            ⭐ Advanced metadata (Pro)
            ⭐ Selective restore (Pro)
            """
        }
    }
}