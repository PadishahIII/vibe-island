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

    private let bundleIdentifier = "net.kovidgoyal.kitty"
    private var fallbackBackend: AccessibilityWindowBackend?

    func availability() async -> TerminalBackendAvailability {
        guard isInstalled() else {
            return .notInstalled
        }

        guard isRunning() else {
            return .installedNotRunning
        }

        if !(await remoteControlEndpoints()).isEmpty {
            return .ready
        }

        let fallbackBackend = await fallbackBackendInstance()
        return await fallbackBackend.availability()
    }

    func currentSnapshot() async throws -> TerminalSnapshot {
        guard isInstalled() else {
            throw TerminalBackendError.notInstalled
        }

        guard isRunning() else {
            throw TerminalBackendError.notRunning
        }

        let endpoints = await remoteControlEndpoints()
        if !endpoints.isEmpty {
            do {
                return try await remoteSnapshot(endpoints: endpoints)
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
        guard isRunning() else {
            throw TerminalBackendError.notRunning
        }

        if id.hasPrefix("rc:") {
            let endpoints = await remoteControlEndpoints()
            guard let target = endpoint(forSessionID: id, in: endpoints) ?? endpoints.first else {
                throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
            }

            guard let executablePath = kittyExecutablePath() else {
                throw TerminalBackendError.notInstalled
            }

            let rawID = rawRemoteWindowID(from: id)
            _ = try await ProcessExecutor.shared.run(
                executablePath,
                arguments: ["@", "--to", target.address, "focus-window", "--match", "id:\(rawID)"]
            )

            runningApplications()
                .first(where: { $0.processIdentifier == target.processID })?
                .activate(options: [.activateAllWindows])
            return
        }

        let fallbackBackend = await fallbackBackendInstance()
        try await fallbackBackend.activateSession(id: id)
    }

    private func remoteSnapshot(endpoints: [RemoteControlEndpoint]) async throws -> TerminalSnapshot {
        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        let generatedAt = Date()
        var sessions: [TerminalSession] = []
        var capturedError: Error?

        for endpoint in endpoints {
            do {
                let output = try await ProcessExecutor.shared.run(
                    executablePath,
                    arguments: ["@", "--to", endpoint.address, "ls"]
                )

                let records = try KittyRemoteControlParser.parse(output)
                sessions.append(
                    contentsOf: records.map { record in
                        TerminalSession(
                            id: "rc:\(endpoint.processID):\(record.windowID)",
                            provider: provider,
                            displayIndex: record.windowID,
                            title: record.title.isEmpty ? "Kitty Window \(record.windowID)" : record.title,
                            windowIndex: record.osWindowIndex,
                            tabIndex: record.tabIndex,
                            isFocused: record.isFocused,
                            lastSeenAt: generatedAt,
                            subtitle: nil,
                            focusPid: Int(endpoint.processID),
                            tty: nil
                        )
                    }
                )
            } catch {
                capturedError = error
            }
        }

        if sessions.isEmpty, let capturedError {
            throw capturedError
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

    private func kittyExecutablePath() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/kitty")
        let executablePath = executableURL.path

        if FileManager.default.isExecutableFile(atPath: executablePath) {
            return executablePath
        }

        return nil
    }

    private func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    private func isRunning() -> Bool {
        !runningApplications().isEmpty
    }

    private func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .sorted {
                if $0.isActive != $1.isActive {
                    return $0.isActive && !$1.isActive
                }

                return $0.processIdentifier < $1.processIdentifier
            }
    }

    private func remoteControlEndpoints() async -> [RemoteControlEndpoint] {
        var endpoints: [RemoteControlEndpoint] = []

        for application in runningApplications() {
            let processID = application.processIdentifier

            if let address = await remoteControlAddress(processID: processID) {
                endpoints.append(RemoteControlEndpoint(processID: processID, address: address))
            }
        }

        return endpoints
    }

    private func endpoint(forSessionID id: String, in endpoints: [RemoteControlEndpoint]) -> RemoteControlEndpoint? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count >= 3, let processID = Int32(String(parts[1])) else {
            return nil
        }

        return endpoints.first(where: { $0.processID == processID })
    }

    private func rawRemoteWindowID(from id: String) -> String {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)

        if parts.count >= 3 {
            return String(parts[2])
        }

        return String(id.dropFirst(3))
    }

    private func remoteControlAddress(processID: pid_t) async -> String? {
        if let configuredAddress = await remoteControlAddressFromProcessArguments(processID: processID) {
            return configuredAddress
        }

        guard let socketPath = await remoteControlSocketPath(processID: processID) else {
            return nil
        }

        return "unix:\(socketPath)"
    }

    private func remoteControlAddressFromProcessArguments(processID: pid_t) async -> String? {
        let output = try? await ProcessExecutor.shared.run(
            "/bin/ps",
            arguments: ["-ww", "-o", "command=", "-p", "\(processID)"]
        )

        guard let commandLine = output?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return KittyRemoteControlAddressParser.parse(commandLine: commandLine)
    }

    private func remoteControlSocketPath(processID: pid_t) async -> String? {
        let output = try? await ProcessExecutor.shared.run(
            "/usr/sbin/lsof",
            arguments: ["-U", "-a", "-p", "\(processID)", "-Fn"]
        )

        guard let stdout = output else {
            return nil
        }

        var candidates: [String] = []

        for line in stdout.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else {
                continue
            }

            let path = String(line.dropFirst())

            if path.hasPrefix("/"), !path.contains("(none)") {
                candidates.append(path)
            }
        }

        return candidates.first(where: {
            $0.localizedCaseInsensitiveContains("kitty") || $0.localizedCaseInsensitiveContains(".sock")
        }) ?? candidates.first
    }
}

private struct RemoteControlEndpoint: Sendable {
    let processID: pid_t
    let address: String
}
