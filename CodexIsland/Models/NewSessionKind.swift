//
//  NewSessionKind.swift
//  CodexIsland
//
//  Supported session types for creating new Kitty-backed windows.
//

import Foundation

enum NewSessionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case opencode
    case codex
    case terminal

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .opencode:
            return "OpenCode"
        case .codex:
            return "Codex"
        case .terminal:
            return "Terminal"
        }
    }

    nonisolated var actionTitle: String {
        switch self {
        case .opencode:
            return "Create OpenCode"
        case .codex:
            return "Create Codex"
        case .terminal:
            return "Open Terminal"
        }
    }

    nonisolated var helperText: String {
        switch self {
        case .opencode:
            return "Start a new OpenCode session in Kitty."
        case .codex:
            return "Start a new Codex session in Kitty."
        case .terminal:
            return "Open a plain terminal window in Kitty."
        }
    }

    nonisolated var commandName: String? {
        switch self {
        case .opencode:
            return "opencode"
        case .codex:
            return "codex"
        case .terminal:
            return nil
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .opencode:
            return "square.stack.3d.up"
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .terminal:
            return "terminal"
        }
    }
}
