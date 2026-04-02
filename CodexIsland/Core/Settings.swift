//
//  Settings.swift
//  CodexIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let visibleSessionProviders = "visibleSessionProviders"
        static let knownSessionProviders = "knownSessionProviders"
        static let sessionListSortMode = "sessionListSortMode"
        static let sessionListGroupingMode = "sessionListGroupingMode"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Session Visibility

    static var visibleSessionProviders: [SessionProvider] {
        get {
            let allProviders = SessionProvider.visibilityOptions
            let allProviderRawValues = allProviders.map(\.rawValue)

            guard let rawValues = defaults.stringArray(forKey: Keys.visibleSessionProviders) else {
                defaults.set(allProviderRawValues, forKey: Keys.knownSessionProviders)
                return allProviders
            }

            let knownRawValues = Set(defaults.stringArray(forKey: Keys.knownSessionProviders) ?? rawValues)
            let newProviders = allProviders.filter { !knownRawValues.contains($0.rawValue) }

            var visibleRawValues = Set(rawValues)
            var didMigrate = false

            if !newProviders.isEmpty {
                visibleRawValues.formUnion(newProviders.map(\.rawValue))
                didMigrate = true
            }

            let visibleProviders = allProviders.filter { visibleRawValues.contains($0.rawValue) }

            if didMigrate || knownRawValues != Set(allProviderRawValues) {
                defaults.set(allProviderRawValues, forKey: Keys.knownSessionProviders)
                defaults.set(visibleProviders.map(\.rawValue), forKey: Keys.visibleSessionProviders)
            }

            return visibleProviders
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: Keys.visibleSessionProviders)
            defaults.set(SessionProvider.visibilityOptions.map(\.rawValue), forKey: Keys.knownSessionProviders)
        }
    }

    // MARK: - Session List Presentation

    static var sessionListSortMode: SessionListSortMode {
        get {
            guard let rawValue = defaults.string(forKey: Keys.sessionListSortMode),
                  let mode = SessionListSortMode(rawValue: rawValue) else {
                return .defaultOrder
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.sessionListSortMode)
        }
    }

    static var sessionListGroupingMode: SessionListGroupingMode {
        get {
            guard let rawValue = defaults.string(forKey: Keys.sessionListGroupingMode),
                  let mode = SessionListGroupingMode(rawValue: rawValue) else {
                return .none
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.sessionListGroupingMode)
        }
    }
}
