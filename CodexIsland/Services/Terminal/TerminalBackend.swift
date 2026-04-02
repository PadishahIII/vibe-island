//
//  TerminalBackend.swift
//  CodexIsland
//
//  Shared terminal session backend types.
//

import Foundation

struct TerminalSession: Identifiable, Equatable, Sendable {
    let id: String
    let provider: SessionProvider
    let displayIndex: Int
    let title: String
    let windowIndex: Int
    let tabIndex: Int?
    let isFocused: Bool
    let lastSeenAt: Date
    let subtitle: String?
    let focusPid: Int?
    let tty: String?
    let workingDirectory: String?

    var locationLabel: String {
        if let tabIndex, tabIndex > 0 {
            return "W\(windowIndex) T\(tabIndex)"
        }

        return "W\(windowIndex)"
    }

    var subtitleLabel: String {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }

        if isFocused {
            return "Current focus · \(provider.displayName) · \(locationLabel)"
        }

        return "\(provider.displayName) · \(locationLabel)"
    }
}

struct TerminalSnapshot: Equatable, Sendable {
    let sessions: [TerminalSession]
    let generatedAt: Date
    let noticeMessage: String?
}

enum TerminalBackendAvailability: Sendable {
    case loading
    case ready
    case notInstalled
    case installedNotRunning
    case permissionRequired
    case error(String)

    nonisolated var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }
}

extension TerminalBackendAvailability: Equatable {
    nonisolated static func == (lhs: TerminalBackendAvailability, rhs: TerminalBackendAvailability) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.ready, .ready): return true
        case (.notInstalled, .notInstalled): return true
        case (.installedNotRunning, .installedNotRunning): return true
        case (.permissionRequired, .permissionRequired): return true
        case (.error(let lhsMessage), .error(let rhsMessage)): return lhsMessage == rhsMessage
        default: return false
        }
    }
}

protocol TerminalBackend: Sendable {
    var key: String { get }
    var provider: SessionProvider { get }
    var displayName: String { get }

    func availability() async -> TerminalBackendAvailability
    func currentSnapshot() async throws -> TerminalSnapshot
    func activateSession(id: String) async throws
}

enum TerminalBackendError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case notRunning
    case permissionRequired
    case sessionNotFound
    case parseFailed(String)
    case scriptFailed(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "No supported terminal app is installed."
        case .notRunning:
            return "No supported terminal app is running."
        case .permissionRequired:
            return "Additional macOS permissions are required to inspect terminal sessions."
        case .sessionNotFound:
            return "The selected terminal session no longer exists."
        case .parseFailed(let message):
            return message
        case .scriptFailed(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }
}
