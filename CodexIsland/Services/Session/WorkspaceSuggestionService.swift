//
//  WorkspaceSuggestionService.swift
//  CodexIsland
//
//  Aggregates workspace suggestions for new session creation.
//

import Foundation

struct WorkspaceSuggestion: Identifiable, Equatable, Sendable {
    let path: String
    let sourceLabel: String

    var id: String { path }

    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }
}

actor WorkspaceSuggestionService {
    static let shared = WorkspaceSuggestionService()

    private let codexDatabase = CodexSessionDatabase.shared
    private let opencodeDatabase = OpencodeSessionDatabase.shared
    private let recentWorkspaceStore = RecentWorkspaceStore.shared
    private let kittyRemoteControl = KittyRemoteControlService.shared

    private init() {}

    func suggestions(for kind: NewSessionKind, limit: Int = 14) async -> [WorkspaceSuggestion] {
        switch kind {
        case .codex:
            let recentDirectories = await recentWorkspaceStore.recentDirectories(for: .codex, limit: limit)
            let recent = recentDirectories.map { WorkspaceSuggestion(path: $0, sourceLabel: "Recent launch") }
            let storedDirectories = await codexDatabase.recentDirectories(limit: limit)
            let stored = storedDirectories.map { WorkspaceSuggestion(path: $0.path, sourceLabel: "Codex history") }
            return mergedSuggestions(groups: [recent, stored], limit: limit)
        case .opencode:
            let recentDirectories = await recentWorkspaceStore.recentDirectories(for: .opencode, limit: limit)
            let recent = recentDirectories.map { WorkspaceSuggestion(path: $0, sourceLabel: "Recent launch") }
            let storedDirectories = await opencodeDatabase.recentDirectories(limit: limit)
            let stored = storedDirectories.map { WorkspaceSuggestion(path: $0.path, sourceLabel: "OpenCode history") }
            return mergedSuggestions(groups: [recent, stored], limit: limit)
        case .terminal:
            let recentDirectories = await recentWorkspaceStore.recentDirectories(for: .terminal, limit: limit)
            let recent = recentDirectories.map { WorkspaceSuggestion(path: $0, sourceLabel: "Recent launch") }

            let currentKittyWindows = (try? await kittyRemoteControl.currentWindows()) ?? []
            let currentKittyDirectories = currentKittyWindows
                .compactMap(\.workingDirectory)
                .map { WorkspaceSuggestion(path: $0, sourceLabel: "Current Kitty session") }

            return mergedSuggestions(groups: [recent, currentKittyDirectories], limit: limit)
        }
    }

    func remember(directory: String, for kind: NewSessionKind) async {
        await recentWorkspaceStore.record(directory: directory, for: kind)
    }

    private func mergedSuggestions(
        groups: [[WorkspaceSuggestion]],
        limit: Int
    ) -> [WorkspaceSuggestion] {
        var seen: Set<String> = []
        var merged: [WorkspaceSuggestion] = []

        for group in groups {
            for suggestion in group {
                let normalizedPath = normalizedPath(for: suggestion.path)
                guard !normalizedPath.isEmpty,
                      directoryExists(normalizedPath),
                      seen.insert(normalizedPath).inserted else {
                    continue
                }

                merged.append(WorkspaceSuggestion(path: normalizedPath, sourceLabel: suggestion.sourceLabel))
                if merged.count >= limit {
                    return merged
                }
            }
        }

        return merged
    }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
