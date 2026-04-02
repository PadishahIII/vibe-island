//
//  WindowManager.swift
//  CodexIsland
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.codexisland", category: "Window")

class WindowManager {
    private(set) var windowController: NotchWindowController?
    private let dragThreshold: CGFloat = 10

    private struct DragState {
        let startLocation: CGPoint
        var hasMovedAcrossThreshold = false
    }

    private struct WindowRestoreState {
        let status: NotchStatus
        let openReason: NotchOpenReason
        let contentType: NotchContentType
        let isHovering: Bool
    }

    private var dragState: DragState?

    /// Set up or recreate the notch window
    func setupNotchWindow() -> NotchWindowController? {
        setupNotchWindow(restoring: nil)
    }

    func moveWindow(to screen: NSScreen) -> NotchWindowController? {
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        if screenSelector.isSelected(screen) {
            return windowController
        }

        let restoreState = snapshot(from: windowController)
        screenSelector.selectScreen(screen)
        return setupNotchWindow(restoring: restoreState)
    }

    func beginWindowDrag(at location: CGPoint) {
        dragState = DragState(startLocation: location)
    }

    @discardableResult
    func updateWindowDrag(to location: CGPoint) -> Bool {
        guard var dragState else { return false }

        let dragDistance = hypot(
            location.x - dragState.startLocation.x,
            location.y - dragState.startLocation.y
        )
        guard dragDistance >= dragThreshold else { return false }

        dragState.hasMovedAcrossThreshold = true
        self.dragState = dragState

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return true
        }

        _ = moveWindow(to: screen)
        return true
    }

    @discardableResult
    func endWindowDrag() -> Bool {
        let didDrag = dragState?.hasMovedAcrossThreshold ?? false
        dragState = nil
        return didDrag
    }

    func cancelWindowDrag() {
        dragState = nil
    }

    private func setupNotchWindow(restoring restoreState: WindowRestoreState?) -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        windowController = NotchWindowController(screen: screen)
        windowController?.showWindow(nil)

        if let restoreState {
            windowController?.viewModel.contentType = restoreState.contentType
            windowController?.viewModel.openReason = restoreState.openReason
            windowController?.viewModel.status = restoreState.status
            windowController?.viewModel.isHovering = restoreState.isHovering
        }

        return windowController
    }

    private func snapshot(from controller: NotchWindowController?) -> WindowRestoreState? {
        guard let viewModel = controller?.viewModel else {
            return nil
        }

        return WindowRestoreState(
            status: viewModel.status,
            openReason: viewModel.openReason,
            contentType: viewModel.contentType,
            isHovering: viewModel.isHovering
        )
    }
}
