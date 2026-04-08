//
//  TerminalSessionMonitor.swift
//  CodexIsland
//
//  Polls supported terminal backends and exposes them as SessionState rows.
//

import Combine
import Foundation

@MainActor
final class TerminalSessionMonitor: ObservableObject {
    static let shared = TerminalSessionMonitor()

    @Published private(set) var sessions: [SessionState] = []
    @Published private(set) var noticeMessage: String?

    private let backend = CompositeTerminalBackend.defaultBackends()
    private let visibilitySelector = SessionVisibilitySelector.shared

    private var isStarted = false

    private init() {}

    func start() {
        isStarted = true
    }

    func stop() {
        isStarted = false
        sessions = []
        noticeMessage = nil
    }

    func activate(sessionId: String) {
        Task { @MainActor in
            do {
                try await backend.activateSession(id: sessionId)
                await backend.invalidateCache()
                SessionRefreshCoordinator.shared.requestRefresh()
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    func refreshTitleOverrides() {
        sessions = sessions.map { session in
            var updated = session
            updated.customTitle = SessionTitleStore.title(for: session.provider, sessionId: session.sessionId)
            return updated
        }
    }

    func refreshFromCoordinator() async {
        guard isStarted else { return }
        await refreshSessions()
    }

    private func refreshSessions() async {
        let enabledProviders = Set(
            visibilitySelector.visibleProviders.filter { $0.isTerminalProvider }
        )

        guard !enabledProviders.isEmpty else {
            sessions = []
            noticeMessage = nil
            return
        }

        do {
            let snapshot = try await backend.currentSnapshot(enabledProviders: enabledProviders)
            let existingStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
            sessions = snapshot.sessions.map {
                makeSessionState(
                    from: $0,
                    existingState: existingStates[$0.id],
                    generatedAt: snapshot.generatedAt
                )
            }
            noticeMessage = snapshot.noticeMessage
        } catch {
            sessions = []
            noticeMessage = error.localizedDescription
        }
    }

    private func makeSessionState(
        from session: TerminalSession,
        existingState: SessionState?,
        generatedAt: Date
    ) -> SessionState {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "\(session.provider.displayName) Session \(session.displayIndex)" : title
        let createdAt = existingState?.createdAt ?? generatedAt
        let lastActivity =
            hasMeaningfulChange(in: session, defaultDisplayTitle: displayTitle, existingState: existingState)
            ? generatedAt
            : (existingState?.lastActivity ?? generatedAt)

        return SessionState(
            sessionId: session.id,
            provider: session.provider,
            cwd: session.workingDirectory ?? "/",
            projectName: displayTitle,
            transcriptPath: nil,
            pid: session.focusPid,
            tty: session.tty,
            terminalName: session.subtitleLabel,
            isInTmux: false,
            isFocusedTerminalSession: session.isFocused,
            phase: .idle,
            chatItems: [],
            toolTracker: ToolTracker(),
            subagentState: SubagentState(),
            conversationInfo: ConversationInfo(
                summary: displayTitle,
                lastMessage: nil,
                lastMessageRole: nil,
                lastToolName: nil,
                firstUserMessage: nil,
                lastUserMessageDate: nil
            ),
            needsClearReconciliation: false,
            lastActivity: lastActivity,
            createdAt: createdAt
        )
    }

    private func hasMeaningfulChange(
        in session: TerminalSession,
        defaultDisplayTitle: String,
        existingState: SessionState?
    ) -> Bool {
        guard let existingState else {
            return true
        }

        return existingState.projectName != defaultDisplayTitle
            || existingState.cwd != (session.workingDirectory ?? "/")
            || existingState.pid != session.focusPid
            || existingState.tty != session.tty
            || existingState.terminalName != session.subtitleLabel
            || existingState.isFocusedTerminalSession != session.isFocused
    }
}
