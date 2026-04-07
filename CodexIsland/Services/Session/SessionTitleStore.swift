//
//  SessionTitleStore.swift
//  CodexIsland
//
//  Persists per-session display title overrides shown only inside the app.
//

import Foundation

enum SessionTitleStore {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    nonisolated static func title(for provider: SessionProvider, sessionId: String) -> String? {
        normalizedTitle(defaults.string(forKey: storageKey(for: provider, sessionId: sessionId)))
    }

    nonisolated static func setTitle(_ title: String?, for provider: SessionProvider, sessionId: String) {
        let key = storageKey(for: provider, sessionId: sessionId)

        guard let normalized = normalizedTitle(title) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(normalized, forKey: key)
    }

    nonisolated static func normalizedTitle(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func storageKey(for provider: SessionProvider, sessionId: String) -> String {
        "sessionTitleOverride." + provider.rawValue + "." + sessionId
    }
}
