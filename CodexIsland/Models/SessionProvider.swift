//
//  SessionProvider.swift
//  CodexIsland
//
//  Supported coding agent providers.
//

import Foundation

enum SessionProvider: String, Codable, Equatable, Sendable {
    case claude
    case codex
    case opencode

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }

    var commandName: String {
        switch self {
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        case .opencode:
            return "opencode"
        }
    }
}
