//
//  ProcessScanContext.swift
//  CodexIsland
//
//  Shared per-refresh process scan context with cached cwd lookups.
//

import Foundation

final class ProcessScanContext: @unchecked Sendable {
    nonisolated let tree: [Int: ProcessInfo]

    nonisolated(unsafe) private var cwdCache: [Int: String] = [:]
    nonisolated(unsafe) private var missingCwds: Set<Int> = []

    nonisolated init(tree: [Int: ProcessInfo]) {
        self.tree = tree
    }

    nonisolated func workingDirectory(for pid: Int) -> String? {
        if let cached = cwdCache[pid] {
            return cached
        }

        if missingCwds.contains(pid) {
            return nil
        }

        let cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: pid)
        if let cwd {
            cwdCache[pid] = cwd
        } else {
            missingCwds.insert(pid)
        }
        return cwd
    }

    nonisolated func isInTmux(pid: Int) -> Bool {
        ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)
    }
}
