//
//  CompositeTerminalBackend.swift
//  CodexIsland
//
//  Aggregates terminal sessions across supported backends.
//

import Foundation

actor CompositeTerminalBackend {
    struct Entry: Sendable {
        let key: String
        let provider: SessionProvider
        let displayName: String
        let backend: any TerminalBackend
    }

    private enum SnapshotResult {
        case success(Entry, TerminalSnapshot)
        case failure(Error)
    }

    private let entries: [Entry]
    private var displayIndexMapping: [String: Int] = [:]
    private var nextDisplayIndex = 1

    init(entries: [Entry]) {
        self.entries = entries
    }

    @MainActor
    static func defaultBackends() -> CompositeTerminalBackend {
        CompositeTerminalBackend(
            entries: [
                Entry(key: "iterm2", provider: .iterm2, displayName: "iTerm2", backend: ItermAppleScriptBackend()),
                Entry(key: "kitty", provider: .kitty, displayName: "Kitty", backend: KittyHybridBackend()),
                Entry(
                    key: "alacritty",
                    provider: .alacritty,
                    displayName: "Alacritty",
                    backend: AccessibilityWindowBackend(
                        key: "alacritty",
                        provider: .alacritty,
                        displayName: "Alacritty",
                        bundleIdentifiers: ["org.alacritty", "io.alacritty"],
                        ttyFallback: ProcessTreeTerminalFallbackBackend(
                            key: "alacritty-tty",
                            provider: .alacritty,
                            displayName: "Alacritty",
                            bundleIdentifiers: ["org.alacritty", "io.alacritty"],
                            commandMatchers: ["alacritty.app/contents/macos/alacritty", "/alacritty"],
                            noticeMessage: "Showing Alacritty sessions via TTY fallback."
                        )
                    )
                ),
            ]
        )
    }

    func currentSnapshot(enabledProviders: Set<SessionProvider>) async throws -> TerminalSnapshot {
        guard !enabledProviders.isEmpty else {
            return TerminalSnapshot(sessions: [], generatedAt: Date(), noticeMessage: nil)
        }

        let statuses = await refreshStatuses(enabledProviders: enabledProviders)
        var snapshots: [(Entry, TerminalSnapshot)] = []
        var notices: [String] = []
        var errors: [Error] = []

        await withTaskGroup(of: SnapshotResult.self) { group in
            for entry in entries where enabledProviders.contains(entry.provider) {
                guard statuses[entry.key] == .ready else {
                    continue
                }

                group.addTask {
                    do {
                        let snapshot = try await entry.backend.currentSnapshot()
                        return .success(entry, snapshot)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let entry, let snapshot):
                    snapshots.append((entry, snapshot))
                case .failure(let error):
                    errors.append(error)
                }
            }
        }

        if snapshots.isEmpty {
            if let firstError = errors.first {
                if let backendError = firstError as? TerminalBackendError {
                    throw backendError
                }

                throw TerminalBackendError.unavailable(firstError.localizedDescription)
            }

            if statuses.values.contains(.permissionRequired) {
                throw TerminalBackendError.permissionRequired
            }

            if statuses.values.contains(.installedNotRunning) {
                throw TerminalBackendError.notRunning
            }

            throw TerminalBackendError.notInstalled
        }

        let generatedAt = Date()
        var combinedSessions: [TerminalSession] = []

        for (entry, snapshot) in snapshots {
            if let noticeMessage = snapshot.noticeMessage {
                notices.append(noticeMessage)
            }

            for session in snapshot.sessions {
                let globalID = "\(entry.key)::\(session.id)"
                combinedSessions.append(
                    TerminalSession(
                        id: globalID,
                        provider: session.provider,
                        displayIndex: displayIndex(for: globalID),
                        title: session.title,
                        windowIndex: session.windowIndex,
                        tabIndex: session.tabIndex,
                        isFocused: session.isFocused,
                        lastSeenAt: session.lastSeenAt,
                        subtitle: session.subtitle,
                        focusPid: session.focusPid,
                        tty: session.tty
                    )
                )
            }
        }

        let permissionMissingBackends = entries.compactMap { entry -> String? in
            guard enabledProviders.contains(entry.provider) else {
                return nil
            }

            if statuses[entry.key] == .permissionRequired {
                return entry.displayName
            }

            return nil
        }

        if !permissionMissingBackends.isEmpty {
            notices.append(permissionNotice(for: permissionMissingBackends))
        }

        let noticeMessage = Array(Set(notices))
            .sorted()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TerminalSnapshot(
            sessions: combinedSessions.sorted { lhs, rhs in
                lhs.displayIndex < rhs.displayIndex
            },
            generatedAt: generatedAt,
            noticeMessage: noticeMessage.isEmpty ? nil : noticeMessage
        )
    }

    func activateSession(id: String) async throws {
        let parts = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)

        guard parts.count >= 3 else {
            throw TerminalBackendError.sessionNotFound
        }

        let backendKey = String(parts[0])
        let rawID = String(parts[2])

        guard let entry = entries.first(where: { $0.key == backendKey }) else {
            throw TerminalBackendError.sessionNotFound
        }

        try await entry.backend.activateSession(id: rawID)
    }

    private func refreshStatuses(enabledProviders: Set<SessionProvider>) async -> [String: TerminalBackendAvailability] {
        var statuses: [String: TerminalBackendAvailability] = [:]

        await withTaskGroup(of: (String, TerminalBackendAvailability).self) { group in
            for entry in entries where enabledProviders.contains(entry.provider) {
                group.addTask {
                    let availability = await entry.backend.availability()
                    return (entry.key, availability)
                }
            }

            for await result in group {
                statuses[result.0] = result.1
            }
        }

        return statuses
    }

    private func displayIndex(for sessionID: String) -> Int {
        if let existing = displayIndexMapping[sessionID] {
            return existing
        }

        let allocated = nextDisplayIndex
        displayIndexMapping[sessionID] = allocated
        nextDisplayIndex += 1
        return allocated
    }
}

nonisolated private func permissionNotice(for backendNames: [String]) -> String {
    let names = backendNames.sorted().joined(separator: ", ")
    return "Grant macOS permission to include \(names)."
}
