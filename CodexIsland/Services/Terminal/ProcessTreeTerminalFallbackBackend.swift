//
//  ProcessTreeTerminalFallbackBackend.swift
//  CodexIsland
//
//  Enumerates terminal sessions from the process tree when richer APIs are unavailable.
//

import AppKit
import Foundation

actor ProcessTreeTerminalFallbackBackend: TerminalBackend {
    nonisolated let key: String
    nonisolated let provider: SessionProvider
    nonisolated let displayName: String

    private struct Candidate: Sendable {
        let pid: Int
        let tty: String
        let command: String
        let appPid: Int
    }

    private struct FallbackSession: Sendable {
        let id: String
        let title: String
        let subtitle: String
        let tty: String
        let appPid: Int
        let workingDirectory: String?
    }

    private let bundleIdentifiers: [String]
    private let commandMatchers: [String]
    private let noticeMessage: String

    init(
        key: String,
        provider: SessionProvider,
        displayName: String,
        bundleIdentifiers: [String],
        commandMatchers: [String],
        noticeMessage: String
    ) {
        self.key = key
        self.provider = provider
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.commandMatchers = commandMatchers.map { $0.lowercased() }
        self.noticeMessage = noticeMessage
    }

    func availability() async -> TerminalBackendAvailability {
        guard isInstalled() else {
            return .notInstalled
        }

        guard !runningApplications().isEmpty else {
            return .installedNotRunning
        }

        return currentSessions().isEmpty ? .installedNotRunning : .ready
    }

    func currentSnapshot() async throws -> TerminalSnapshot {
        guard isInstalled() else {
            throw TerminalBackendError.notInstalled
        }

        guard !runningApplications().isEmpty else {
            throw TerminalBackendError.notRunning
        }

        let fallbackSessions = currentSessions()
        guard !fallbackSessions.isEmpty else {
            throw TerminalBackendError.notRunning
        }

        let generatedAt = Date()
        let sessions = fallbackSessions.enumerated().map { offset, session in
            TerminalSession(
                id: session.id,
                provider: provider,
                displayIndex: offset + 1,
                title: session.title,
                windowIndex: offset + 1,
                tabIndex: nil,
                isFocused: false,
                lastSeenAt: generatedAt,
                subtitle: session.subtitle,
                focusPid: session.appPid,
                tty: session.tty,
                workingDirectory: session.workingDirectory
            )
        }

        return TerminalSnapshot(
            sessions: sessions,
            generatedAt: generatedAt,
            noticeMessage: noticeMessage
        )
    }

    func activateSession(id: String) async throws {
        guard let appPid = appPid(from: id) else {
            throw TerminalBackendError.sessionNotFound
        }

        if await WindowFinder.shared.isYabaiAvailable() {
            let windows = await WindowFinder.shared.getAllWindows()
            if let window = windows.first(where: { $0.pid == appPid }),
               await WindowFocuser.shared.focusWindow(id: window.id) {
                return
            }
        }

        if let application = NSRunningApplication(processIdentifier: pid_t(appPid)) {
            _ = application.activate(options: [.activateAllWindows])
            return
        }

        if let application = runningApplications().first(where: { Int($0.processIdentifier) == appPid }) {
            _ = application.activate(options: [.activateAllWindows])
            return
        }

        throw TerminalBackendError.sessionNotFound
    }

    private func currentSessions() -> [FallbackSession] {
        let tree = ProcessTreeBuilder.shared.buildTree()
        let grouped = Dictionary(grouping: tree.values.compactMap { candidate(for: $0, tree: tree) }) {
            "\($0.appPid)::\($0.tty)"
        }

        return grouped.values.compactMap { candidates in
            guard let primary = preferredCandidate(from: candidates) else {
                return nil
            }

            let title = sessionTitle(for: primary)
            return FallbackSession(
                id: "tty:\(provider.rawValue):\(primary.appPid):\(primary.tty)",
                title: title,
                subtitle: "\(displayName) · \(primary.tty)",
                tty: primary.tty,
                appPid: primary.appPid,
                workingDirectory: ProcessTreeBuilder.shared.getWorkingDirectory(forPid: primary.pid)
            )
        }
        .sorted { lhs, rhs in
            if lhs.appPid == rhs.appPid {
                return lhs.tty < rhs.tty
            }
            return lhs.appPid < rhs.appPid
        }
    }

    private func candidate(for info: ProcessInfo, tree: [Int: ProcessInfo]) -> Candidate? {
        guard let tty = normalizedTTY(info.tty),
              let appPid = terminalApplicationPid(for: info.pid, tree: tree) else {
            return nil
        }

        return Candidate(
            pid: info.pid,
            tty: tty,
            command: info.command,
            appPid: appPid
        )
    }

    private func terminalApplicationPid(for pid: Int, tree: [Int: ProcessInfo]) -> Int? {
        var current = pid
        var depth = 0
        var matchedPid: Int?

        while current > 1 && depth < 30 {
            guard let info = tree[current] else { break }
            if matchesProvider(info.command) {
                matchedPid = current
            }
            current = info.ppid
            depth += 1
        }

        return matchedPid
    }

    private func preferredCandidate(from candidates: [Candidate]) -> Candidate? {
        candidates.sorted { lhs, rhs in
            let lhsPriority = processPriority(lhs.command)
            let rhsPriority = processPriority(rhs.command)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            if lhs.pid != rhs.pid {
                return lhs.pid > rhs.pid
            }

            return lhs.command < rhs.command
        }.first
    }

    private func processPriority(_ command: String) -> Int {
        let name = normalizedCommandName(command)

        if isCodingAgent(name) {
            return 0
        }

        if name == "ssh" {
            return 1
        }

        if isShellLike(name) || name == "tmux" {
            return 2
        }

        if name == "login" {
            return 4
        }

        if matchesProvider(command) {
            return 5
        }

        return 3
    }

    private func sessionTitle(for candidate: Candidate) -> String {
        let commandName = normalizedCommandName(candidate.command)
        let cwdLabel = workingDirectoryLabel(for: candidate.pid)

        if isShellLike(commandName) || commandName == "login" || isCodingAgent(commandName) {
            if let cwdLabel {
                return cwdLabel
            }
        }

        if !commandName.isEmpty {
            return commandName
        }

        if let cwdLabel {
            return cwdLabel
        }

        return "\(displayName) \(candidate.tty)"
    }

    private func workingDirectoryLabel(for pid: Int) -> String? {
        guard let cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: pid),
              !cwd.isEmpty,
              cwd != "/" else {
            return nil
        }

        let label = URL(fileURLWithPath: cwd).lastPathComponent
        return label.isEmpty ? cwd : label
    }

    private func normalizedCommandName(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let base = URL(fileURLWithPath: trimmed).lastPathComponent
        let commandName = base.isEmpty ? trimmed : base
        return commandName.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }

    private func isShellLike(_ commandName: String) -> Bool {
        ["zsh", "bash", "fish", "sh", "nu"].contains(commandName)
    }

    private func isCodingAgent(_ commandName: String) -> Bool {
        ["codex", "claude", "opencode"].contains(commandName)
    }

    private func normalizedTTY(_ rawTTY: String?) -> String? {
        guard let rawTTY else {
            return nil
        }

        let trimmed = rawTTY
            .replacingOccurrences(of: "/dev/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }

    private func matchesProvider(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        return commandMatchers.contains { lowercased.contains($0) }
    }

    private func appPid(from id: String) -> Int? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 4 else {
            return nil
        }
        return Int(parts[2])
    }

    private func isInstalled() -> Bool {
        bundleIdentifiers.contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    private func runningApplications() -> [NSRunningApplication] {
        var applications: [pid_t: NSRunningApplication] = [:]

        for bundleIdentifier in bundleIdentifiers {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            where !application.isTerminated {
                applications[application.processIdentifier] = application
            }
        }

        return applications.values.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }

            return lhs.processIdentifier < rhs.processIdentifier
        }
    }
}
