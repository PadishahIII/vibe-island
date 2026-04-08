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

    private struct BackendRefreshResult {
        let availability: TerminalBackendAvailability
        let snapshot: TerminalSnapshot?
        let backendError: TerminalBackendError?
        let refreshedAt: Date
    }

    private let entries: [Entry]
    private var displayIndexMapping: [String: Int] = [:]
    private var nextDisplayIndex = 1
    private let refreshCacheTTL: TimeInterval = 1.0
    private var refreshCache: [String: BackendRefreshResult] = [:]

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

        let refreshResults = await refreshResults(enabledProviders: enabledProviders)
        var snapshots: [(Entry, TerminalSnapshot)] = []
        var notices: [String] = []
        let errors = refreshResults.compactMap(\.1.backendError)

        for (entry, result) in refreshResults where result.availability == .ready {
            if let snapshot = result.snapshot {
                snapshots.append((entry, snapshot))
            }
        }

        if snapshots.isEmpty {
            if let firstError = errors.first {
                throw firstError
            }

            if refreshResults.contains(where: { $0.1.availability == .permissionRequired }) {
                throw TerminalBackendError.permissionRequired
            }

            if refreshResults.contains(where: { $0.1.availability == .installedNotRunning }) {
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
                        tty: session.tty,
                        workingDirectory: session.workingDirectory
                    )
                )
            }
        }

        let permissionMissingBackends = entries.compactMap { entry -> String? in
            guard enabledProviders.contains(entry.provider) else {
                return nil
            }

            if refreshResults.first(where: { $0.0.key == entry.key })?.1.availability == .permissionRequired {
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

    func invalidateCache() {
        refreshCache.removeAll()
    }

    private func refreshResults(
        enabledProviders: Set<SessionProvider>
    ) async -> [(Entry, BackendRefreshResult)] {
        await withTaskGroup(of: (Entry, BackendRefreshResult).self, returning: [(Entry, BackendRefreshResult)].self) { group in
            for entry in entries where enabledProviders.contains(entry.provider) {
                group.addTask { [refreshCacheTTL] in
                    let result = await self.refreshResult(for: entry, ttl: refreshCacheTTL)
                    return (entry, result)
                }
            }

            var results: [(Entry, BackendRefreshResult)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func refreshResult(for entry: Entry, ttl: TimeInterval) async -> BackendRefreshResult {
        let now = Date()
        if let cached = refreshCache[entry.key],
           now.timeIntervalSince(cached.refreshedAt) < ttl {
            return cached
        }

        let result: BackendRefreshResult
        do {
            let snapshot = try await entry.backend.currentSnapshot()
            result = BackendRefreshResult(
                availability: .ready,
                snapshot: snapshot,
                backendError: nil,
                refreshedAt: now
            )
        } catch let backendError as TerminalBackendError {
            result = BackendRefreshResult(
                availability: availability(for: backendError),
                snapshot: nil,
                backendError: backendError,
                refreshedAt: now
            )
        } catch {
            result = BackendRefreshResult(
                availability: .error(error.localizedDescription),
                snapshot: nil,
                backendError: .unavailable(error.localizedDescription),
                refreshedAt: now
            )
        }

        refreshCache[entry.key] = result
        return result
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

    private func availability(for error: TerminalBackendError) -> TerminalBackendAvailability {
        switch error {
        case .notInstalled:
            return .notInstalled
        case .notRunning:
            return .installedNotRunning
        case .permissionRequired:
            return .permissionRequired
        case .sessionNotFound, .parseFailed, .scriptFailed, .unavailable:
            return .error(error.localizedDescription)
        }
    }
}

nonisolated private func permissionNotice(for backendNames: [String]) -> String {
    let names = backendNames.sorted().joined(separator: ", ")
    return "Grant macOS permission to include \(names)."
}
