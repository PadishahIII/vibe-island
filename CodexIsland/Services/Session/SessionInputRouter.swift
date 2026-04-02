//
//  SessionInputRouter.swift
//  CodexIsland
//
//  Routes chat input to tmux panes or directly to session TTY devices.
//

import Foundation

actor SessionInputRouter {
    static let shared = SessionInputRouter()

    private init() {}

    func send(_ message: String, to session: SessionState) async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !session.isTerminalSession,
              let tty = normalizedTTY(session.tty) else {
            return false
        }

        if session.isInTmux, let target = await findTmuxTarget(tty: tty) {
            return await ToolApprovalHandler.shared.sendMessage(text, to: target)
        }

        return writeDirectly(text, toTTY: tty)
    }

    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let paneTTY = normalizedTTY(parts[1])
                if paneTTY == tty {
                    return TmuxTarget(from: parts[0])
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func writeDirectly(_ text: String, toTTY tty: String) -> Bool {
        let devicePath = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let payload = text + "\r"

        guard let data = payload.data(using: .utf8) else {
            return false
        }

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: devicePath))
            try handle.write(contentsOf: data)
            try handle.close()
            return true
        } catch {
            return false
        }
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
}
