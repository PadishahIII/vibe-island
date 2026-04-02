//
//  ItermAppleScriptBackend.swift
//  CodexIsland
//
//  iTerm2 session enumeration and activation through AppleScript.
//

import AppKit
import Foundation

actor ItermAppleScriptBackend: TerminalBackend {
    nonisolated let key = "iterm2"
    nonisolated let provider: SessionProvider = .iterm2
    nonisolated let displayName = "iTerm2"

    private let bundleIdentifier = "com.googlecode.iterm2"
    private let fallbackBackend = ProcessTreeTerminalFallbackBackend(
        key: "iterm2-tty",
        provider: .iterm2,
        displayName: "iTerm2",
        bundleIdentifiers: ["com.googlecode.iterm2"],
        commandMatchers: ["iterm.app/contents/macos/iterm2", "itermserver", "/iterm2"],
        noticeMessage: "Showing iTerm2 sessions via TTY fallback."
    )
    private var displayIndexMapping: [String: Int] = [:]
    private var nextDisplayIndex = 1

    func availability() async -> TerminalBackendAvailability {
        guard isInstalled() else {
            return .notInstalled
        }

        guard isRunning() else {
            return .installedNotRunning
        }

        do {
            _ = try await AppleScriptRunner.execute(source: ItermScriptTemplates.availabilityCheck)
            return .ready
        } catch let error as TerminalBackendError {
            let fallbackAvailability = await fallbackBackend.availability()
            if fallbackAvailability.isReady {
                return .ready
            }

            switch error {
            case .permissionRequired:
                return .permissionRequired
            case .notRunning:
                return .installedNotRunning
            default:
                return .error(error.localizedDescription)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func currentSnapshot() async throws -> TerminalSnapshot {
        guard isInstalled() else {
            throw TerminalBackendError.notInstalled
        }

        guard isRunning() else {
            throw TerminalBackendError.notRunning
        }

        do {
            let output = try await AppleScriptRunner.execute(source: ItermScriptTemplates.enumerateSessions)
            let records = try ItermSnapshotParser.parse(output)
            if records.isEmpty {
                return try await fallbackBackend.currentSnapshot()
            }

            let generatedAt = Date()
            var sessions: [TerminalSession] = []
            sessions.reserveCapacity(records.count)

            for record in records {
                sessions.append(
                    TerminalSession(
                        id: record.backendSessionID,
                        provider: provider,
                        displayIndex: displayIndex(for: record.backendSessionID),
                        title: record.title.isEmpty ? "Untitled session" : record.title,
                        windowIndex: record.windowIndex,
                        tabIndex: record.tabIndex,
                        isFocused: record.isFocused,
                        lastSeenAt: generatedAt,
                        subtitle: nil,
                        focusPid: nil,
                        tty: nil
                    )
                )
            }

            sessions.sort { lhs, rhs in
                lhs.displayIndex < rhs.displayIndex
            }

            return TerminalSnapshot(
                sessions: sessions,
                generatedAt: generatedAt,
                noticeMessage: nil
            )
        } catch {
            return try await fallbackBackend.currentSnapshot()
        }
    }

    func activateSession(id: String) async throws {
        if id.hasPrefix("tty:") {
            try await fallbackBackend.activateSession(id: id)
            return
        }

        guard isInstalled() else {
            throw TerminalBackendError.notInstalled
        }

        guard isRunning() else {
            throw TerminalBackendError.notRunning
        }

        let result = try await AppleScriptRunner.execute(source: ItermScriptTemplates.activateSession(id))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard result == "ok" else {
            throw TerminalBackendError.sessionNotFound
        }
    }

    private func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    private func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
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
