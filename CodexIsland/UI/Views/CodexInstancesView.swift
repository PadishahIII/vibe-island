//
//  CodexInstancesView.swift
//  CodexIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct CodexInstancesView: View {
    @ObservedObject var sessionMonitor: CodexSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var visibilitySelector = SessionVisibilitySelector.shared
    @ObservedObject private var presentationController = SessionListPresentationController.shared

    var body: some View {
        VStack(spacing: 10) {
            SessionVisibilityPickerRow(visibilitySelector: visibilitySelector)
            SessionListControlsRow(presentationController: presentationController)

            if sessionMonitor.instances.isEmpty {
                emptyState
            } else {
                instancesList
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(emptyStateTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text(emptyStateSubtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        visibilitySelector.visibleProviders.isEmpty ? "All session sources are hidden" : "No sessions"
    }

    private var emptyStateSubtitle: String {
        if visibilitySelector.visibleProviders.isEmpty {
            return "Enable Codex, OpenCode, Claude Code, or terminal providers above"
        }
        return "Run Claude Code, Codex, OpenCode, or open iTerm2, Kitty, or Alacritty"
    }

    // MARK: - Instances List

    private var presentedSections: [SessionSection] {
        let orderedSessions = orderedInstances(from: sessionMonitor.instances)

        switch presentationController.groupingMode {
        case .none:
            return [SessionSection(id: "all", title: nil, sessions: orderedSessions)]
        case .sessionType:
            let grouped = Dictionary(grouping: orderedSessions, by: \.provider)
            return SessionProvider.visibilityOptions.compactMap { provider in
                guard let sessions = grouped[provider], !sessions.isEmpty else { return nil }
                return SessionSection(
                    id: "provider-\(provider.rawValue)",
                    title: provider.displayName,
                    sessions: sessions
                )
            }
        case .status:
            let grouped = Dictionary(grouping: orderedSessions, by: phaseGroup(for:))
            return SessionPhaseGroup.allCases.compactMap { group in
                guard let sessions = grouped[group], !sessions.isEmpty else { return nil }
                return SessionSection(
                    id: "status-\(group.rawValue)",
                    title: group.title,
                    sessions: sessions
                )
            }
        }
    }

    private func orderedInstances(from sessions: [SessionState]) -> [SessionState] {
        switch presentationController.sortMode {
        case .defaultOrder:
            return sessions
        case .updatedAt:
            return sessions.sorted { lhs, rhs in
                if lhs.lastActivity != rhs.lastActivity {
                    return lhs.lastActivity > rhs.lastActivity
                }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private func phaseGroup(for session: SessionState) -> SessionPhaseGroup {
        switch session.phase {
        case .waitingForApproval:
            return .waitingForApproval
        case .processing:
            return .processing
        case .compacting:
            return .compacting
        case .waitingForInput:
            return .waitingForInput
        case .idle:
            return .idle
        case .ended:
            return .ended
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(presentedSections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                                .padding(.horizontal, 8)
                        }

                        VStack(spacing: 2) {
                            ForEach(section.sessions) { session in
                                InstanceRow(
                                    session: session,
                                    onFocus: { focusSession(session) },
                                    onChat: { openChat(session) },
                                    onArchive: { archiveSession(session) },
                                    onApprove: { approveSession(session) },
                                    onReject: { rejectSession(session) }
                                )
                                .id(session.stableId)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        if session.isTerminalSession {
            sessionMonitor.activateTerminalSession(sessionId: session.sessionId)
            return
        }

        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        guard session.supportsChat else {
            focusSession(session)
            return
        }
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        guard !session.isTerminalSession else { return }
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

private struct SessionSection: Identifiable {
    let id: String
    let title: String?
    let sessions: [SessionState]
}

private enum SessionPhaseGroup: String, CaseIterable {
    case waitingForApproval
    case processing
    case compacting
    case waitingForInput
    case idle
    case ended

    var title: String {
        switch self {
        case .waitingForApproval:
            return "Waiting for Approval"
        case .processing:
            return "Processing"
        case .compacting:
            return "Compacting"
        case .waitingForInput:
            return "Ready for Input"
        case .idle:
            return "Idle"
        case .ended:
            return "Ended"
        }
    }
}

private struct SessionListControlsRow: View {
    @ObservedObject var presentationController: SessionListPresentationController

    var body: some View {
        HStack(spacing: 8) {
            SessionListMenu(
                icon: "arrow.up.arrow.down",
                title: "Sort",
                value: presentationController.sortMode.shortTitle
            ) {
                ForEach(SessionListSortMode.allCases, id: \.self) { mode in
                    Button {
                        presentationController.setSortMode(mode)
                    } label: {
                        if presentationController.sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            SessionListMenu(
                icon: "square.grid.2x2",
                title: "Group",
                value: presentationController.groupingMode.shortTitle
            ) {
                ForEach(SessionListGroupingMode.allCases, id: \.self) { mode in
                    Button {
                        presentationController.setGroupingMode(mode)
                    } label: {
                        if presentationController.groupingMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionListMenu<Content: View>: View {
    let icon: String
    let title: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let codexBlue = TerminalColors.prompt
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    private var isTerminalSession: Bool {
        session.isTerminalSession
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // State indicator on left
            stateIndicator
                .frame(width: 14)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SessionProviderBadge(provider: session.provider, phase: session.phase)

                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                if let terminalName = session.terminalName, !terminalName.isEmpty {
                    Text(terminalName + (session.isInTmux ? " • tmux" : ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                }

                // Show tool call when waiting for approval, otherwise last activity
                if isWaitingForApproval, let toolName = session.pendingToolName {
                    // Show tool name in amber + input on same line
                    HStack(spacing: 4) {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.9))
                        if isInteractiveTool {
                            Text("Needs your input")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        } else if let input = session.pendingToolInput {
                            Text(input)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                } else if let role = session.lastMessageRole {
                    switch role {
                    case "tool":
                        // Tool call - show tool name + input
                        HStack(spacing: 4) {
                            if let toolName = session.lastToolName {
                                Text(MCPToolFormatter.formatToolName(toolName))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            if let input = session.lastMessage {
                                Text(input)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    case "user":
                        // User message - prefix with "You:"
                        HStack(spacing: 4) {
                            Text("You:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    default:
                        // Assistant message - just show text
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                } else if let lastMsg = session.lastMessage {
                    Text(lastMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Action icons or approval buttons
            if isTerminalSession {
                HStack(spacing: 8) {
                    IconButton(icon: "eye") {
                        onFocus()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval && isInteractiveTool {
                // Interactive tools like AskUserQuestion - show chat + terminal buttons
                HStack(spacing: 8) {
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Go to Terminal button (only if yabai available)
                    if isYabaiAvailable {
                        TerminalButton(
                            isEnabled: session.isInTmux,
                            onTap: { onFocus() }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval {
                InlineApprovalButtons(
                    onChat: onChat,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Chat icon - always show
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Focus icon (only for tmux instances with yabai)
                    if session.isInTmux && isYabaiAvailable {
                        IconButton(icon: "eye") {
                            onFocus()
                        }
                    }

                    // Archive button - only for idle or completed sessions
                    if session.phase == .idle || session.phase == .waitingForInput {
                        IconButton(icon: "archivebox") {
                            onArchive()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isTerminalSession {
                onFocus()
            } else {
                onChat()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        if isTerminalSession {
            Circle()
                .fill(session.isFocusedTerminalSession ? TerminalColors.green : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        } else {
            switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(codexBlue)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
        }
    }

}

private struct SessionProviderBadge: View {
    let provider: SessionProvider
    let phase: SessionPhase

    var body: some View {
        Text(provider.badgeLabel)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.16))
            )
            .overlay(
                Capsule()
                    .stroke(badgeColor.opacity(0.35), lineWidth: 0.8)
            )
            .fixedSize(horizontal: true, vertical: true)
    }

    private var badgeColor: Color {
        SessionVisualStyle.badgeColor(provider: provider)
    }
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
