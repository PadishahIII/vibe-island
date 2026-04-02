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
    case iterm2
    case kitty
    case alacritty

    var displayName: String {
        switch self {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        case .iterm2:
            return "iTerm2"
        case .kitty:
            return "Kitty"
        case .alacritty:
            return "Alacritty"
        }
    }

    var badgeLabel: String {
        switch self {
        case .claude:
            return "claudecode"
        case .codex:
            return "codex"
        case .opencode:
            return "opencode"
        case .iterm2:
            return "iterm2"
        case .kitty:
            return "kitty"
        case .alacritty:
            return "alacritty"
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
        case .iterm2:
            return "iterm2"
        case .kitty:
            return "kitty"
        case .alacritty:
            return "alacritty"
        }
    }

    var isTerminalProvider: Bool {
        switch self {
        case .iterm2, .kitty, .alacritty:
            return true
        case .claude, .codex, .opencode:
            return false
        }
    }

    var supportsChat: Bool {
        !isTerminalProvider
    }

    static var visibilityOptions: [SessionProvider] {
        [.claude, .codex, .opencode, .iterm2, .kitty, .alacritty]
    }
}
