//
//  KittyHybridBackend.swift
//  CodexIsland
//
//  Kitty session management using remote control with Accessibility fallback.
//

import AppKit
import Foundation

actor KittyHybridBackend: TerminalBackend {
    nonisolated let key = "kitty"
    nonisolated let provider: SessionProvider = .kitty
    nonisolated let displayName = "Kitty"

    private let remoteControlService = KittyRemoteControlService.shared
    private var fallbackBackend: AccessibilityWindowBackend?

    func availability() async -> TerminalBackendAvailability {
        let status = await remoteControlService.status()

        guard status.isInstalled else {
            return .notInstalled
        }

        guard status.isRunning else {
            return .installedNotRunning
        }

        if status.isReady {
            return .ready
        }

        let fallbackBackend = await fallbackBackendInstance()
        return await fallbackBackend.availability()
    }

    func currentSnapshot() async throws -> TerminalSnapshot {
        let status = await remoteControlService.status()

        guard status.isInstalled else {
            throw TerminalBackendError.notInstalled
        }

        guard status.isRunning else {
            throw TerminalBackendError.notRunning
        }

        if status.isReady {
            do {
                return try await remoteSnapshot()
            } catch {
                let fallbackBackend = await fallbackBackendInstance()
                if await fallbackBackend.availability() == .ready {
                    return try await fallbackBackend.currentSnapshot()
                }
                throw error
            }
        }

        let fallbackBackend = await fallbackBackendInstance()
        return try await fallbackBackend.currentSnapshot()
    }

    func activateSession(id: String) async throws {
        let status = await remoteControlService.status()

        guard status.isRunning else {
            throw TerminalBackendError.notRunning
        }

        if id.hasPrefix("rc:") {
            try await remoteControlService.focusWindow(
                windowID: rawRemoteWindowID(from: id),
                preferredProcessID: rawRemoteProcessID(from: id)
            )
            return
        }

        let fallbackBackend = await fallbackBackendInstance()
        try await fallbackBackend.activateSession(id: id)
    }

    private func remoteSnapshot() async throws -> TerminalSnapshot {
        let generatedAt = Date()
        let windows = try await remoteControlService.currentWindows()
        let sessions = windows.map { window in
            TerminalSession(
                id: remoteSessionID(for: window),
                provider: provider,
                displayIndex: window.windowID,
                title: window.title.isEmpty ? "Kitty Window \(window.windowID)" : window.title,
                windowIndex: window.osWindowIndex,
                tabIndex: window.tabIndex,
                isFocused: window.isFocused,
                lastSeenAt: generatedAt,
                subtitle: nil,
                focusPid: Int(window.endpoint.processID),
                tty: nil,
                workingDirectory: window.workingDirectory
            )
        }

        return TerminalSnapshot(
            sessions: sessions,
            generatedAt: generatedAt,
            noticeMessage: nil
        )
    }

    private func fallbackBackendInstance() async -> AccessibilityWindowBackend {
        if let fallbackBackend {
            return fallbackBackend
        }

        let backend = await MainActor.run {
            AccessibilityWindowBackend(
                key: "kitty-fallback",
                provider: .kitty,
                displayName: "Kitty",
                bundleIdentifiers: ["net.kovidgoyal.kitty"],
                noticeMessage: "Kitty remote-control listener not found. Showing Kitty OS windows only."
            )
        }
        fallbackBackend = backend
        return backend
    }

    private func rawRemoteWindowID(from id: String) -> Int {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)

        if let last = parts.last, let value = Int(last) {
            return value
        }

        return Int(id.dropFirst(3)) ?? 0
    }

    private func rawRemoteProcessID(from id: String) -> pid_t? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count >= 3, let value = Int32(parts[1]) else {
            return nil
        }

        return value
    }

    private func remoteSessionID(for window: KittyRemoteWindowRecord) -> String {
        "rc:\(window.endpoint.processID):\(window.windowID)"
    }
}
