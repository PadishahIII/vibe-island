//
//  CodexSessionScanner.swift
//  CodexIsland
//
//  Discovers interactive codex terminal sessions by correlating processes
//  with the local codex thread database.
//

import Foundation

@MainActor
final class CodexSessionScanner {
    static let shared = CodexSessionScanner()

    private struct RunningProcess {
        let pid: Int
        let tty: String
        let cwd: String
        let isInTmux: Bool
    }

    private let database = CodexSessionDatabase.shared
    private var isStarted = false
    private var trackedSessionIds: Set<String> = []

    private init() {}

    func start() {
        isStarted = true
    }

    func stop() {
        isStarted = false
        trackedSessionIds.removeAll()
    }

    func refresh(using context: ProcessScanContext) async {
        guard isStarted else { return }
        await scan(using: context)
    }

    private func scan(using context: ProcessScanContext) async {
        let runningProcesses = discoverRunningProcesses(context: context)
        let groupedByDirectory = Dictionary(grouping: runningProcesses, by: \.cwd)

        var discoveredSessionIds: Set<String> = []

        for (cwd, processes) in groupedByDirectory {
            let candidates = await database.latestThreads(
                for: cwd,
                limit: max(processes.count * 3, 6)
            )
            let assignments = assign(processes: processes, to: candidates)

            for (process, thread) in assignments {
                discoveredSessionIds.insert(thread.id)

                await SessionStore.shared.process(.sessionDiscovered(DiscoveredSession(
                    sessionId: thread.id,
                    provider: .codex,
                    cwd: thread.cwd,
                    transcriptPath: thread.rolloutPath,
                    pid: process.pid,
                    tty: process.tty,
                    terminalName: nil,
                    isInTmux: process.isInTmux,
                    phase: .waitingForInput,
                    lastActivity: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt))
                )))
            }
        }

        let removedSessionIds = trackedSessionIds.subtracting(discoveredSessionIds)
        trackedSessionIds = discoveredSessionIds

        for sessionId in removedSessionIds {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    private func discoverRunningProcesses(context: ProcessScanContext) -> [RunningProcess] {
        context.tree.values.compactMap { info in
            guard let tty = info.tty,
                  isCodexCommand(info.command),
                  let cwd = context.workingDirectory(for: info.pid) else {
                return nil
            }

            return RunningProcess(
                pid: info.pid,
                tty: tty,
                cwd: cwd,
                isInTmux: context.isInTmux(pid: info.pid)
            )
        }
        .sorted { lhs, rhs in
            if lhs.cwd == rhs.cwd {
                return lhs.pid < rhs.pid
            }
            return lhs.cwd < rhs.cwd
        }
    }

    private func assign(
        processes: [RunningProcess],
        to candidates: [CodexSessionDatabase.ThreadRecord]
    ) -> [(RunningProcess, CodexSessionDatabase.ThreadRecord)] {
        let sortedProcesses = processes.sorted { $0.pid < $1.pid }
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id < rhs.id
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        var assignments: [(RunningProcess, CodexSessionDatabase.ThreadRecord)] = []
        for (index, process) in sortedProcesses.enumerated() where index < sortedCandidates.count {
            assignments.append((process, sortedCandidates[index]))
        }
        return assignments
    }

    private func isCodexCommand(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        guard !lowercased.contains("vibe-island"),
              !lowercased.contains("codex-island") else {
            return false
        }

        return lowercased == "codex"
            || lowercased.hasSuffix("/codex")
            || lowercased.contains("/codex/")
    }
}
