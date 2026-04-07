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
            return "Kitty is running, but no remote-control listener was detected."
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
        let endpoints = running ? await remoteControlEndpoints() : []

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

        let endpoints = await remoteControlEndpoints()
        guard !endpoints.isEmpty else {
            throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
        }

        var windows: [KittyRemoteWindowRecord] = []
        var capturedError: Error?

        for endpoint in endpoints {
            do {
                let output = try await ProcessExecutor.shared.run(
                    executablePath,
                    arguments: ["@", "--to", endpoint.address, "ls"]
                )

                let records = try KittyRemoteControlParser.parse(output)
                windows.append(
                    contentsOf: records.map { record in
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
                )
            } catch {
                capturedError = error
            }
        }

        if windows.isEmpty, let capturedError {
            throw capturedError
        }

        return windows
    }

    func focusWindow(windowID: Int, preferredProcessID: pid_t? = nil) async throws {
        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        let endpoints = await remoteControlEndpoints()
        guard !endpoints.isEmpty else {
            throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
        }

        let orderedEndpoints: [KittyRemoteControlEndpoint]
        if let preferred = preferredEndpoint(in: endpoints, processID: preferredProcessID) {
            orderedEndpoints = [preferred] + endpoints.filter {
                $0.processID != preferred.processID || $0.address != preferred.address
            }
        } else {
            orderedEndpoints = endpoints
        }

        var capturedError: Error?

        for endpoint in orderedEndpoints {
            do {
                _ = try await ProcessExecutor.shared.run(
                    executablePath,
                    arguments: ["@", "--to", endpoint.address, "focus-window", "--match", "id:\(windowID)"]
                )

                runningApplications()
                    .first(where: { $0.processIdentifier == endpoint.processID })?
                    .activate(options: [.activateAllWindows])
                return
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            throw capturedError
        }

        throw TerminalBackendError.unavailable("Kitty remote-control listener is not available.")
    }

    func launchSession(kind: NewSessionKind, directory: String) async throws {
        let normalizedDirectory = normalizedDirectory(directory)
        guard directoryExists(normalizedDirectory) else {
            throw TerminalBackendError.unavailable("Selected workspace does not exist.")
        }

        guard let executablePath = kittyExecutablePath() else {
            throw TerminalBackendError.notInstalled
        }

        let endpoints = await remoteControlEndpoints()
        guard let endpoint = preferredEndpoint(in: endpoints, processID: nil) else {
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

    private func preferredEndpoint(
        in endpoints: [KittyRemoteControlEndpoint],
        processID: pid_t?
    ) -> KittyRemoteControlEndpoint? {
        if let processID, let exact = endpoints.first(where: { $0.processID == processID }) {
            return exact
        }

        return endpoints.first
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

    private func remoteControlEndpoints() async -> [KittyRemoteControlEndpoint] {
        var endpoints: [KittyRemoteControlEndpoint] = []

        if let endpoint = await sharedEndpoint() {
            endpoints.append(endpoint)
        }

        for application in runningApplications() {
            let processID = application.processIdentifier

            guard let address = await remoteControlAddress(processID: processID) else {
                continue
            }

            let candidate = KittyRemoteControlEndpoint(processID: processID, address: address)
            guard !endpoints.contains(where: {
                $0.processID == candidate.processID || $0.address == candidate.address
            }) else {
                continue
            }

            endpoints.append(candidate)
        }

        return endpoints
    }

    private func remoteControlAddress(processID: pid_t) async -> String? {
        guard let executablePath = kittyExecutablePath() else {
            return nil
        }

        if let configuredAddress = await remoteControlAddressFromProcessArguments(processID: processID),
           await isEndpointReachable(configuredAddress, executablePath: executablePath) {
            return configuredAddress
        }

        guard let socketPath = await remoteControlSocketPath(processID: processID) else {
            return nil
        }

        let inferredAddress = "unix:\(socketPath)"
        guard await isEndpointReachable(inferredAddress, executablePath: executablePath) else {
            return nil
        }

        return inferredAddress
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
            $0 == sharedSocketPath || $0.hasPrefix(sharedSocketPath + "-")
        }) ?? candidates.first(where: {
            $0.localizedCaseInsensitiveContains("kitty") || $0.localizedCaseInsensitiveContains(".sock")
        }) ?? candidates.first
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

        return await isEndpointReachable(sharedAddress, executablePath: executablePath)
    }

    private func isEndpointReachable(_ address: String, executablePath: String) async -> Bool {
        guard !address.isEmpty else {
            return false
        }

        do {
            _ = try await ProcessExecutor.shared.run(
                executablePath,
                arguments: ["@", "--to", address, "ls"]
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
