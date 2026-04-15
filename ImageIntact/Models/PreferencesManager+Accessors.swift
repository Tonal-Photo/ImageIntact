//
//  PreferencesManager+Accessors.swift
//  ImageIntact
//
//  Type-specialized UserDefaults getter/setter helpers with observation registration and
//  equality guards. Each helper uses `NSNumber`-value bridging for numeric types to avoid
//  the `as? T` quirks that can misbehave under strict bridging.
//

import Foundation

extension PreferencesManager {

    func getBool(key: String, default defaultValue: Bool, keyPath: KeyPath<PreferencesManager, Bool>) -> Bool {
        access(keyPath: keyPath)
        return (defaults.object(forKey: key) as? NSNumber)?.boolValue ?? defaultValue
    }

    func setBool(_ newValue: Bool, key: String, keyPath: KeyPath<PreferencesManager, Bool>) {
        // Compare against effective value (respects register(defaults:)), not raw nil.
        // Without this, setting to a default value on a fresh suite would fire observation
        // even though the user-visible value didn't change.
        let effective = defaults.bool(forKey: key)
        guard effective != newValue else { return }
        withMutation(keyPath: keyPath) { defaults.set(newValue, forKey: key) }
    }

    func getInt(key: String, default defaultValue: Int, keyPath: KeyPath<PreferencesManager, Int>) -> Int {
        access(keyPath: keyPath)
        return (defaults.object(forKey: key) as? NSNumber)?.intValue ?? defaultValue
    }

    func setInt(_ newValue: Int, key: String, keyPath: KeyPath<PreferencesManager, Int>) {
        let effective = defaults.integer(forKey: key)
        guard effective != newValue else { return }
        withMutation(keyPath: keyPath) { defaults.set(newValue, forKey: key) }
    }

    func getDouble(key: String, default defaultValue: Double, keyPath: KeyPath<PreferencesManager, Double>) -> Double {
        access(keyPath: keyPath)
        return (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? defaultValue
    }

    func setDouble(_ newValue: Double, key: String, keyPath: KeyPath<PreferencesManager, Double>) {
        let effective = defaults.double(forKey: key)
        guard effective != newValue else { return }
        withMutation(keyPath: keyPath) { defaults.set(newValue, forKey: key) }
    }

    func getString(key: String, default defaultValue: String, keyPath: KeyPath<PreferencesManager, String>) -> String {
        access(keyPath: keyPath)
        return defaults.string(forKey: key) ?? defaultValue
    }

    func setString(_ newValue: String, key: String, keyPath: KeyPath<PreferencesManager, String>) {
        // defaults.string(forKey:) returns registered default if set, nil otherwise.
        // Compare against effective value so setting to a registered default is a no-op.
        let effective = defaults.string(forKey: key)
        guard effective != newValue else { return }
        withMutation(keyPath: keyPath) { defaults.set(newValue, forKey: key) }
    }

    func getOptionalString(key: String, keyPath: KeyPath<PreferencesManager, String?>) -> String? {
        access(keyPath: keyPath)
        return defaults.string(forKey: key)
    }

    func setOptionalString(_ newValue: String?, key: String, keyPath: KeyPath<PreferencesManager, String?>) {
        let oldValue = defaults.string(forKey: key)
        guard oldValue != newValue else { return }
        withMutation(keyPath: keyPath) {
            if let v = newValue { defaults.set(v, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}
