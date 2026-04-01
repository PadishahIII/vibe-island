//
//  OpencodeSessionScanner.swift
//  CodexIsland
//
//  Discovers interactive opencode terminal sessions by correlating processes
//  with the local opencode session database.
//

import Foundation

@MainActor
final class OpencodeSessionScanner {
    static let shared = OpencodeSessionScanner()

    private struct RunningProcess {
        let pid: Int
        let tty: String
        let cwd: String
        let isInTmux: Bool
    }

    private let database = OpencodeSessionDatabase.shared
    private var timer: Timer?
    private var trackedSessionIds: Set<String> = []

    private init() {}

    func start() {
        guard timer == nil else { return }

        performScan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.performScan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performScan() {
        Task {
            await scan()
        }
    }

    private func scan() async {
        let tree = ProcessTreeBuilder.shared.buildTree()
        let runningProcesses = discoverRunningProcesses(tree: tree)
        let groupedByDirectory = Dictionary(grouping: runningProcesses, by: \.cwd)

        var discoveredSessionIds: Set<String> = []

        for (cwd, processes) in groupedByDirectory {
            let candidates = await database.latestSessions(
                for: cwd,
                limit: max(processes.count * 3, 6),
                topLevelOnly: true
            )
            let assignments = assign(processes: processes, to: candidates)

            for (process, session) in assignments {
                discoveredSessionIds.insert(session.id)
                let phase = await database.phase(sessionId: session.id)

                await SessionStore.shared.process(.sessionDiscovered(DiscoveredSession(
                    sessionId: session.id,
                    provider: .opencode,
                    cwd: session.directory,
                    transcriptPath: nil,
                    pid: process.pid,
                    tty: process.tty,
                    terminalName: nil,
                    isInTmux: process.isInTmux,
                    phase: phase,
                    lastActivity: Date(timeIntervalSince1970: TimeInterval(session.timeUpdated) / 1000)
                )))
            }
        }

        let removedSessionIds = trackedSessionIds.subtracting(discoveredSessionIds)
        trackedSessionIds = discoveredSessionIds

        for sessionId in removedSessionIds {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    private func discoverRunningProcesses(tree: [Int: ProcessInfo]) -> [RunningProcess] {
        tree.values.compactMap { info in
            guard let tty = info.tty,
                  info.command.lowercased().contains("opencode"),
                  let cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: info.pid) else {
                return nil
            }

            return RunningProcess(
                pid: info.pid,
                tty: tty,
                cwd: cwd,
                isInTmux: ProcessTreeBuilder.shared.isInTmux(pid: info.pid, tree: tree)
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
        to candidates: [OpencodeSessionDatabase.SessionRecord]
    ) -> [(RunningProcess, OpencodeSessionDatabase.SessionRecord)] {
        let sortedProcesses = processes.sorted { $0.pid < $1.pid }
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.timeUpdated == rhs.timeUpdated {
                return lhs.id < rhs.id
            }
            return lhs.timeUpdated > rhs.timeUpdated
        }

        var assignments: [(RunningProcess, OpencodeSessionDatabase.SessionRecord)] = []
        for (index, process) in sortedProcesses.enumerated() where index < sortedCandidates.count {
            assignments.append((process, sortedCandidates[index]))
        }
        return assignments
    }
}
