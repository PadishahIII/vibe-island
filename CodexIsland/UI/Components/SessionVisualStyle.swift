//
//  SessionVisualStyle.swift
//  CodexIsland
//
//  Shared color logic for session provider and phase combinations.
//

import SwiftUI

enum SessionVisualStyle {
    static func accentColor(provider: SessionProvider, phase: SessionPhase) -> Color {
        switch phase {
        case .processing:
            return activeProviderColor(provider)
        case .compacting:
            return compactingColor(provider)
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.green
        case .idle:
            return idleProviderColor(provider)
        case .ended:
            return Color.white.opacity(0.35)
        }
    }

    static func activeProviderColor(_ provider: SessionProvider) -> Color {
        switch provider {
        case .claude:
            return TerminalColors.amber
        case .codex:
            return TerminalColors.blue
        case .opencode:
            return TerminalColors.green
        case .iterm2:
            return TerminalColors.cyan
        case .kitty:
            return Color(red: 0.97, green: 0.58, blue: 0.34)
        case .alacritty:
            return Color(red: 0.92, green: 0.39, blue: 0.45)
        }
    }

    static func compactingColor(_ provider: SessionProvider) -> Color {
        switch provider {
        case .codex:
            return Color(red: 0.48, green: 0.74, blue: 1.0)
        case .opencode:
            return Color(red: 0.52, green: 0.82, blue: 0.56)
        case .claude:
            return Color(red: 1.0, green: 0.78, blue: 0.28)
        case .iterm2, .kitty, .alacritty:
            return activeProviderColor(provider)
        }
    }

    static func idleProviderColor(_ provider: SessionProvider) -> Color {
        activeProviderColor(provider).opacity(0.72)
    }
}
