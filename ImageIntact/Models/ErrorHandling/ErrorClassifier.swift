//
//  ErrorClassifier.swift
//  ImageIntact
//
//  Classifies errors and determines retry strategies
//

import Foundation

/// Types of errors that can occur during backup operations
enum ErrorCategory: Sendable {
    case transient      // Can be retried (network timeout, temporary lock)
    case permanent      // Cannot be retried (permission denied, corrupt file)
    case critical       // Should stop backup (disk full, destination unmounted)
    case unknown        // Unclassified error
}

/// Retry strategy for handling errors
struct RetryStrategy: Sendable {
    let shouldRetry: Bool
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let useExponentialBackoff: Bool
    
    static let transientError = RetryStrategy(
        shouldRetry: true,
        maxAttempts: 3,
        baseDelay: 1.0,
        useExponentialBackoff: true
    )
    
    static let noRetry = RetryStrategy(
        shouldRetry: false,
        maxAttempts: 0,
        baseDelay: 0,
        useExponentialBackoff: false
    )
    
    /// Calculate delay for a given attempt number (1-based)
    func delay(for attempt: Int) -> TimeInterval {
        guard shouldRetry && attempt <= maxAttempts else { return 0 }
        
        if useExponentialBackoff {
            // Exponential backoff: 1s, 2s, 4s, 8s...
            return baseDelay * pow(2.0, Double(attempt - 1))
        } else {
            return baseDelay
        }
    }
}

/// Classifies errors and determines appropriate handling strategies
final class ErrorClassifier: Sendable {
    
    // MARK: - Error Classification
    
    /// Classify an error into a category
    static func classify(_ error: Error) -> ErrorCategory {
        let nsError = error as NSError
        
        // Check for specific error codes and domains
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return classifyCocoaError(nsError)
        case NSPOSIXErrorDomain:
            return classifyPOSIXError(nsError)
        case NSURLErrorDomain:
            return classifyURLError(nsError)
        default:
            return analyzeErrorDescription(error)
        }
    }
    
    /// Determine retry strategy based on error category
    static func retryStrategy(for error: Error) -> RetryStrategy {
        switch classify(error) {
        case .transient:
            return .transientError
        case .permanent, .critical, .unknown:
            return .noRetry
        }
    }
    
    // MARK: - Specific Domain Classification
    
    private static func classifyCocoaError(_ error: NSError) -> ErrorCategory {
        switch error.code {
        case NSFileWriteFileExistsError,
             NSFileWriteNoPermissionError,
             NSFileReadNoPermissionError:
            return .permanent
            
        case NSFileWriteOutOfSpaceError,
             NSFileWriteVolumeReadOnlyError:
            return .critical
            
        case NSFileLockingError,
             NSFileWriteUnknownError:
            return .transient
            
        default:
            return .unknown
        }
    }
    
    private static func classifyPOSIXError(_ error: NSError) -> ErrorCategory {
        switch error.code {
        case Int(EACCES), Int(EPERM):  // Permission denied
            return .permanent
            
        case Int(ENOSPC), Int(EDQUOT):  // No space, quota exceeded
            return .critical
            
        case Int(EAGAIN), Int(EINTR), Int(EBUSY):  // Try again, interrupted, busy
            return .transient
            
        case Int(ETIMEDOUT), Int(ECONNRESET):  // Timeout, connection reset
            return .transient
            
        case Int(ENOTCONN), Int(ENETDOWN):  // Not connected, network down
            return .transient
            
        default:
            return .unknown
        }
    }
    
    private static func classifyURLError(_ error: NSError) -> ErrorCategory {
        switch error.code {
        case NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet:
            return .transient
            
        case NSURLErrorCannotOpenFile,
             NSURLErrorNoPermissionsToReadFile:
            return .permanent
            
        case NSURLErrorDataLengthExceedsMaximum:
            return .critical
            
        default:
            return .unknown
        }
    }
    
    // MARK: - Heuristic Classification
    
    private static func analyzeErrorDescription(_ error: Error) -> ErrorCategory {
        let description = error.localizedDescription.lowercased()
        
        // Transient error keywords
        let transientKeywords = [
            "timeout", "timed out",
            "connection lost", "connection reset",
            "temporarily unavailable",
            "resource busy", "file busy",
            "try again", "retry",
            "network", "interrupted"
        ]
        
        // Permanent error keywords
        let permanentKeywords = [
            "permission denied", "access denied",
            "not permitted", "unauthorized",
            "invalid", "corrupt",
            "does not exist", "not found"
        ]
        
        // Critical error keywords
        let criticalKeywords = [
            "no space", "disk full",
            "quota exceeded",
            "volume", "unmounted",
            "memory", "out of memory"
        ]
        
        // Check for keywords
        for keyword in criticalKeywords {
            if description.contains(keyword) {
                return .critical
            }
        }
        
        for keyword in permanentKeywords {
            if description.contains(keyword) {
                return .permanent
            }
        }
        
        for keyword in transientKeywords {
            if description.contains(keyword) {
                return .transient
            }
        }
        
        return .unknown
    }
    
    // MARK: - User-Friendly Messages
    
    /// Get a user-friendly error message with suggested action
    static func userMessage(for error: Error) -> (message: String, action: String?) {
        let category = classify(error)
        let nsError = error as NSError
        
        switch category {
        case .transient:
            return ("Temporary issue encountered", "The operation will be retried automatically")
            
        case .permanent:
            if nsError.code == NSFileWriteNoPermissionError || nsError.code == Int(EACCES) {
                return ("Permission denied", "Check that you have write access to the destination")
            } else if nsError.code == NSFileWriteFileExistsError {
                return ("File already exists", "The file will be skipped")
            } else {
                return ("Cannot process this file", "The file will be skipped and logged")
            }
            
        case .critical:
            if nsError.code == NSFileWriteOutOfSpaceError || nsError.code == Int(ENOSPC) {
                return ("Destination is full", "Free up space on the destination drive")
            } else {
                return ("Critical error occurred", "The backup cannot continue")
            }
            
        case .unknown:
            return ("Unexpected error occurred", "Check the error log for details")
        }
    }
    
    /// Check if an error is safe to retry
    static func isSafeToRetry(_ error: Error) -> Bool {
        let category = classify(error)
        return category == .transient
    }
    
    /// Check if backup should continue after this error
    static func shouldContinueBackup(after error: Error) -> Bool {
        let category = classify(error)
        return category != .critical
    }
}