//
//  KittyRemoteControlService.swift
//  CodexIsland
//
//  Shared Kitty remote-control discovery and launch utilities.
//

import AppKit
import Foundation

struct KittyRemoteControlEndpoint: Equatable, Sendable {
    let processID: pid_t
    let address: String
}

struct KittyRemoteWindowRecord: Equatable, Sendable {
    let endpoint: KittyRemoteControlEndpoint
    let windowID: Int
    let title: String
    let osWindowIndex: Int
    let tabIndex: Int
    let isFocused: Bool
    let workingDirectory: String?
}

struct KittyRemoteControlStatus: Equatable, Sendable {
    let executablePath: String?
    let isRunning: Bool
    let endpoints: [KittyRemoteControlEndpoint]
    let suggestedLaunchCommand: String?

    var isInstalled: Bool {
        executablePath != nil
    }

    var isReady: Bool {
        isInstalled && !endpoints.isEmpty
    }

    var blockingMessage: String? {
        if !isInstalled {
            return "Kitty is not installed."
        }

        if !isRunning {
            return "Kitty is not running in remote-control mode."
        }

        if endpoints.isEmpty {
            return "Kitty is running, but the shared remote-control socket was not detected."
        }

        return nil
    }
}

actor KittyRemoteControlService {
    static let shared = KittyRemoteControlService()

    private let bundleIdentifier = "net.kovidgoyal.kitty"
    private let fileManager = FileManager.default
    private let sharedSocketPath = "/tmp/vibe-island-kitty.sock"

    private init() {}

    func status() async -> KittyRemoteControlStatus {
        let executablePath = kittyExecutablePath()
        let running = isRunning()
        let endpoints: [KittyRemoteControlEndpoint]

        if running, let endpoint = await sharedEndpoint() {
            endpoints = [endpoint]
        } else {
            endpoints = []
        }

        return KittyRemoteControlStatus(
            executablePath: executablePath,
            isRunning: running,
            endpoints: endpoints,
            suggestedLaunchCommand: executablePath.map(suggestedLaunchCommand(executablePath:))
        )
    }

    func currentWindows() async throws -> [KittyRemoteWindowRecord] {
        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        guard let endpoint = await sharedEndpoint() else {
            throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
        }

        let output = try await ProcessExecutor.shared.run(
            executablePath,
            arguments: ["@", "--to", endpoint.address, "ls"]
        )

        let records = try KittyRemoteControlParser.parse(output)
        return records.map { record in
            KittyRemoteWindowRecord(
                endpoint: endpoint,
                windowID: record.windowID,
                title: record.title,
                osWindowIndex: record.osWindowIndex,
                tabIndex: record.tabIndex,
                isFocused: record.isFocused,
                workingDirectory: normalizedDirectoryIfPresent(record.workingDirectory)
            )
        }
    }

    func focusWindow(windowID: Int) async throws {
        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        guard let endpoint = await sharedEndpoint() else {
            throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
        }

        _ = try await ProcessExecutor.shared.run(
            executablePath,
            arguments: ["@", "--to", endpoint.address, "focus-window", "--match", "id:\(windowID)"]
        )

        runningApplications()
            .first(where: { $0.processIdentifier == endpoint.processID })?
            .activate(options: [.activateAllWindows])
    }

    func launchSession(kind: NewSessionKind, directory: String) async throws {
        let normalizedDirectory = normalizedDirectory(directory)
        guard directoryExists(normalizedDirectory) else {
            throw TerminalBackendError.unavailable("Selected workspace does not exist.")
        }

        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        guard let endpoint = await sharedEndpoint() else {
            let fallback = suggestedLaunchCommand(executablePath: executablePath)
            throw TerminalBackendError.unavailable(
                "Kitty remote-control listener is not available. Start Kitty with: \(fallback)"
            )
        }

        var arguments = [
            "@",
            "--to",
            endpoint.address,
            "launch",
            "--type",
            "os-window",
            "--cwd",
            normalizedDirectory,
        ]

        if let commandName = kind.commandName {
            arguments.append("--hold")
            arguments.append(contentsOf: [loginShellPath(), "-lc", "exec \(commandName)"])
        }

        _ = try await ProcessExecutor.shared.run(executablePath, arguments: arguments)
    }

    private func suggestedLaunchCommand(executablePath: String) -> String {
        return [
            shellQuoted(executablePath),
            "-o",
            "allow_remote_control=yes",
            "--listen-on",
            shellQuoted(sharedAddress)
        ].joined(separator: " ")
    }

    private func loginShellPath() -> String {
        let candidate = Foundation.ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if fileManager.isExecutableFile(atPath: "/bin/zsh") {
            return "/bin/zsh"
        }

        return "/bin/bash"
    }

    private func kittyExecutablePath() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/kitty")
        let executablePath = executableURL.path

        if fileManager.isExecutableFile(atPath: executablePath) {
            return executablePath
        }

        return nil
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

    private var sharedAddress: String {
        "unix:\(sharedSocketPath)"
    }

    private func sharedEndpoint() async -> KittyRemoteControlEndpoint? {
        guard isRunning() else {
            return nil
        }

        guard await isSharedSocketReachable() else {
            return nil
        }

        let ownerProcessID = runningApplications().first?.processIdentifier ?? 0
        return KittyRemoteControlEndpoint(
            processID: ownerProcessID,
            address: sharedAddress
        )
    }

    private func isSharedSocketReachable() async -> Bool {
        guard let executablePath = kittyExecutablePath() else {
            return false
        }

        do {
            _ = try await ProcessExecutor.shared.run(
                executablePath,
                arguments: ["@", "--to", sharedAddress, "ls"]
            )
            return true
        } catch {
            return false
        }
    }

    private func normalizedDirectory(_ directory: String) -> String {
        let normalized = URL(fileURLWithPath: directory)
            .standardizedFileURL
            .path
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    private func normalizedDirectoryIfPresent(_ directory: String?) -> String? {
        guard let directory else {
            return nil
        }

        let normalized = normalizedDirectory(directory)
        return normalized.isEmpty ? nil : normalized
    }

    private func directoryExists(_ directory: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func shellQuoted(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        if !value.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" || $0 == ":" }) {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
