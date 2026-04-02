//
//  NotchViewModel.swift
//  CodexIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case instances
    case menu
    case createSession
    case chat(SessionState)

    var id: String {
        switch self {
        case .instances: return "instances"
        case .menu: return "menu"
        case .createSession: return "create-session"
        case .chat(let session): return "chat-\(session.sessionId)"
        }
    }
}

private enum PendingBarAction {
    case open
    case collapse
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared
    private let soundSelector = SoundSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        switch contentType {
        case .chat:
            // Large size for chat view
            return CGSize(
                width: min(screenRect.width * 0.5, 600),
                height: 580
            )
        case .menu:
            // Compact size for settings menu
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 432 + screenSelector.expandedPickerHeight + soundSelector.expandedPickerHeight
            )
        case .createSession:
            return CGSize(
                width: min(screenRect.width * 0.45, 540),
                height: 560
            )
        case .instances:
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 404
            )
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?
    private var closedBarInteractionWidth: CGFloat
    private var isDraggingBar = false
    private var pendingBarAction: PendingBarAction?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        self.closedBarInteractionWidth = max(deviceNotchRect.width + 44, 180)
        setupEventHandlers()
        observeSelectors()
    }

    private func observeSelectors() {
        screenSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        soundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleMouseDown(event)
            }
            .store(in: &cancellables)

        events.mouseDragged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleMouseDragged(location)
            }
            .store(in: &cancellables)

        events.mouseUp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseUp()
            }
            .store(in: &cancellables)
    }

    /// Whether we're in chat mode (sticky behavior)
    private var isInChatMode: Bool {
        if case .chat = contentType { return true }
        return false
    }

    /// The chat session we're viewing (persists across close/open)
    private var currentChatSession: SessionState?

    private var closedBarHeight: CGFloat {
        max(deviceNotchRect.height, 30)
    }

    private var openedBarHeight: CGFloat {
        max(deviceNotchRect.height + 10, 34)
    }

    private var openedBarWidth: CGFloat {
        min(max(closedBarInteractionWidth + 32, deviceNotchRect.width + 72), openedSize.width - 72)
    }

    var openedPanelRectInWindow: CGRect {
        geometry.openedWindowRect(for: openedSize)
    }

    var closedBarRectInWindow: CGRect {
        geometry.closedBarWindowRect(width: closedBarInteractionWidth, height: closedBarHeight)
    }

    private func isPointInCollapsedBar(_ point: CGPoint) -> Bool {
        geometry.isPointInClosedBar(
            point,
            width: closedBarInteractionWidth,
            height: closedBarHeight
        )
    }

    private func isPointInOpenedCollapseBar(_ point: CGPoint) -> Bool {
        geometry.isPointInOpenedHeader(
            point,
            size: openedSize,
            width: openedBarWidth,
            height: openedBarHeight
        )
    }

    private func handleMouseMove(_ location: CGPoint) {
        guard !isDraggingBar else { return }

        let inClosedBar = isPointInCollapsedBar(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inClosedBar || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        hoverTimer?.cancel()
        hoverTimer = nil

        if isHovering {
            if status == .closed || status == .popping {
                notchOpen(reason: .hover)
            }
        } else if status == .opened && openReason != .boot {
            notchClose()
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let isPanelClick = isEventFromActiveNotchWindow(event)
        pendingBarAction = nil
        isDraggingBar = false

        if draggableBarContains(location) {
            AppDelegate.shared?.beginWindowDrag(at: location)
        } else {
            AppDelegate.shared?.cancelWindowDrag()
        }

        switch status {
        case .opened:
            if isPanelClick {
                if isPointInOpenedCollapseBar(location) && !isInChatMode {
                    pendingBarAction = .collapse
                }
                return
            }

            if geometry.isPointOutsidePanel(location, size: openedSize) {
                AppDelegate.shared?.cancelWindowDrag()
                notchClose()
                // Re-post the click so it reaches the window/app behind us
                repostClickAt(location)
            }
        case .closed, .popping:
            if isPointInCollapsedBar(location) {
                pendingBarAction = .open
            }
        }
    }

    private func isEventFromActiveNotchWindow(_ event: NSEvent) -> Bool {
        guard let notchWindow = AppDelegate.shared?.windowController?.window else {
            return false
        }

        if let eventWindow = event.window {
            return eventWindow === notchWindow
        }

        return event.windowNumber == notchWindow.windowNumber
    }

    private func handleMouseDragged(_ location: CGPoint) {
        if AppDelegate.shared?.updateWindowDrag(to: location) == true {
            isDraggingBar = true
            pendingBarAction = nil
        }
    }

    private func handleMouseUp() {
        let didDragWindow = AppDelegate.shared?.endWindowDrag() ?? false
        let pendingAction = pendingBarAction
        pendingBarAction = nil

        let wasDraggingBar = isDraggingBar || didDragWindow
        isDraggingBar = false

        if wasDraggingBar {
            handleMouseMove(NSEvent.mouseLocation)
            return
        }

        switch pendingAction {
        case .open:
            notchOpen(reason: .click)
        case .collapse:
            if !isInChatMode {
                notchClose()
            }
        case .none:
            break
        }
    }

    private func draggableBarContains(_ point: CGPoint) -> Bool {
        switch status {
        case .opened:
            return isPointInOpenedCollapseBar(point)
        case .closed, .popping:
            return isPointInCollapsedBar(point)
        }
    }

    /// Re-posts a mouse click at the given screen location so it reaches windows behind us
    private func repostClickAt(_ location: CGPoint) {
        // Small delay to let the window's ignoresMouseEvents update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Convert to CGEvent coordinate system (screen coordinates with Y from top-left)
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            // Create and post mouse down event
            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            // Create and post mouse up event
            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        status = .opened

        // Don't restore chat on notification - show instances list instead
        if reason == .notification {
            currentChatSession = nil
            return
        }

        // Restore chat session if we had one open before
        if let chatSession = currentChatSession {
            // Avoid unnecessary updates if already showing this chat
            if case .chat(let current) = contentType, current.sessionId == chatSession.sessionId {
                return
            }
            contentType = .chat(chatSession)
        }
    }

    func notchClose() {
        // Save chat session before closing if in chat mode
        if case .chat(let session) = contentType {
            currentChatSession = session
        }
        status = .closed
        contentType = .instances
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func toggleMenu() {
        contentType = contentType == .menu ? .instances : .menu
    }

    func showChat(for session: SessionState) {
        // Avoid unnecessary updates if already showing this chat
        if case .chat(let current) = contentType, current.sessionId == session.sessionId {
            return
        }
        contentType = .chat(session)
    }

    func showCreateSession() {
        contentType = .createSession
    }

    func showInstances() {
        contentType = .instances
    }

    /// Go back to instances list and clear saved chat state
    func exitChat() {
        currentChatSession = nil
        contentType = .instances
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }

    func updateClosedBarInteractionWidth(_ width: CGFloat) {
        closedBarInteractionWidth = max(width, deviceNotchRect.width + 36)
    }
}
