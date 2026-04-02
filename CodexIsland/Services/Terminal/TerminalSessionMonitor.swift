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

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        visibilitySelector.$visibleProviders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard timer == nil else { return }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func activate(sessionId: String) {
        Task { @MainActor in
            do {
                try await backend.activateSession(id: sessionId)
                refresh()
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    private func refresh() {
        Task { @MainActor in
            await refreshSessions()
        }
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
            sessions = snapshot.sessions.map(makeSessionState(from:))
            noticeMessage = snapshot.noticeMessage
        } catch {
            sessions = []
            noticeMessage = error.localizedDescription
        }
    }

    private func makeSessionState(from session: TerminalSession) -> SessionState {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "\(session.provider.displayName) Session \(session.displayIndex)" : title

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
            lastActivity: session.lastSeenAt,
            createdAt: session.lastSeenAt
        )
    }
}
