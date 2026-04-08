//
//  SessionRefreshCoordinator.swift
//  CodexIsland
//
//  Coordinates adaptive refresh cycles for terminal and agent session discovery.
//

import Combine
import Foundation

@MainActor
final class SessionRefreshCoordinator {
    static let shared = SessionRefreshCoordinator()

    private let visibilitySelector = SessionVisibilitySelector.shared

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var needsAnotherRefresh = false
    private var lastRefreshInterval: TimeInterval?
    private var isStarted = false
    private var isNotchPresented = false
    private var hasUrgentSessions = false
    private var hasTrackedSessions = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        visibilitySelector.$visibleProviders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isStarted else { return }
                self.scheduleRefresh()
                self.configureTimer()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        scheduleRefresh()
        configureTimer()
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        lastRefreshInterval = nil
        refreshTask?.cancel()
        refreshTask = nil
        needsAnotherRefresh = false
    }

    func requestRefresh() {
        scheduleRefresh()
    }

    func updatePresentation(status: NotchStatus) {
        let isPresented = status != .closed
        guard isPresented != isNotchPresented else { return }
        isNotchPresented = isPresented
        configureTimer()

        if isPresented {
            scheduleRefresh()
        }
    }

    func updateSessionSummary(hasUrgentSessions: Bool, hasTrackedSessions: Bool) {
        let didUrgencyChange = self.hasUrgentSessions != hasUrgentSessions
        let didTrackedChange = self.hasTrackedSessions != hasTrackedSessions

        guard didUrgencyChange || didTrackedChange else { return }

        self.hasUrgentSessions = hasUrgentSessions
        self.hasTrackedSessions = hasTrackedSessions
        configureTimer()

        if hasUrgentSessions || (!hasTrackedSessions && didTrackedChange) {
            scheduleRefresh()
        }
    }

    private func configureTimer() {
        guard isStarted else { return }

        let nextInterval = refreshInterval()

        if nextInterval == nil {
            timer?.invalidate()
            timer = nil
            lastRefreshInterval = nil
            return
        }

        guard nextInterval != lastRefreshInterval || timer == nil else { return }

        timer?.invalidate()
        lastRefreshInterval = nextInterval

        guard let nextInterval else { return }

        timer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    private func refreshInterval() -> TimeInterval? {
        let visibleProviders = visibilitySelector.visibleProviders
        guard !visibleProviders.isEmpty else {
            return nil
        }

        if isNotchPresented || hasUrgentSessions {
            return 1.0
        }

        if hasTrackedSessions {
            return 2.5
        }

        return 6.0
    }

    private func scheduleRefresh() {
        guard isStarted else { return }

        if refreshTask != nil {
            needsAnotherRefresh = true
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            repeat {
                needsAnotherRefresh = false
                await performRefreshCycle()
            } while needsAnotherRefresh && !Task.isCancelled

            refreshTask = nil
        }
    }

    private func performRefreshCycle() async {
        let visibleProviders = visibilitySelector.visibleProviders
        guard !visibleProviders.isEmpty else { return }

        if visibleProviders.contains(where: \.isTerminalProvider) {
            await TerminalSessionMonitor.shared.refreshFromCoordinator()
        }

        let needsCodexScan = visibleProviders.contains(.codex)
        let needsOpencodeScan = visibleProviders.contains(.opencode)

        if needsCodexScan || needsOpencodeScan {
            let context = ProcessScanContext(tree: ProcessTreeBuilder.shared.buildTree())

            if needsCodexScan {
                await CodexSessionScanner.shared.refresh(using: context)
            }

            if needsOpencodeScan {
                await OpencodeSessionScanner.shared.refresh(using: context)
            }
        }
    }
}
