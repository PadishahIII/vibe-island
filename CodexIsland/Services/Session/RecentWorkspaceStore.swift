//
//  RecentWorkspaceStore.swift
//  CodexIsland
//
//  Persists recently launched workspace directories by session type.
//

import Foundation

actor RecentWorkspaceStore {
    static let shared = RecentWorkspaceStore()

    private enum Keys {
        static let prefix = "recentLaunchWorkspaces."
    }

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let maxEntries = 16

    private init() {}

    func recentDirectories(for kind: NewSessionKind, limit: Int = 12) -> [String] {
        let stored = defaults.stringArray(forKey: storageKey(for: kind)) ?? []
        return stored
            .map(normalizedDirectory(from:))
            .filter(directoryExists(_:))
            .uniqued()
            .prefix(limit)
            .map { $0 }
    }

    func record(directory: String, for kind: NewSessionKind) {
        let normalized = normalizedDirectory(from: directory)
        guard !normalized.isEmpty, directoryExists(normalized) else {
            return
        }

        var entries = defaults.stringArray(forKey: storageKey(for: kind)) ?? []
        entries.removeAll { normalizedDirectory(from: $0) == normalized }
        entries.insert(normalized, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        defaults.set(entries, forKey: storageKey(for: kind))
    }

    private func storageKey(for kind: NewSessionKind) -> String {
        Keys.prefix + kind.rawValue
    }

    private func normalizedDirectory(from path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private extension Sequence where Element == String {
    nonisolated func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
