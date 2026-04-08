//
//  EventMonitors.swift
//  CodexIsland
//
//  Singleton that aggregates all event monitors
//

import AppKit
import Combine

@MainActor
class EventMonitors {
    static let shared = EventMonitors()

    let mouseLocation = CurrentValueSubject<CGPoint, Never>(.zero)
    let mouseDown = PassthroughSubject<NSEvent, Never>()
    let mouseUp = PassthroughSubject<NSEvent, Never>()
    let mouseDragged = PassthroughSubject<CGPoint, Never>()

    private var mouseMoveMonitor: EventMonitor?
    private var mouseDownMonitor: EventMonitor?
    private var mouseUpMonitor: EventMonitor?
    private var mouseDraggedMonitor: EventMonitor?
    private var activeClients = 0
    private var isDragMonitoring = false

    private init() {}

    func start() {
        activeClients += 1
        guard activeClients == 1 else { return }

        ensureBaseMonitors()
        mouseMoveMonitor?.start()
        mouseDownMonitor?.start()
        mouseUpMonitor?.start()
    }

    func stop() {
        guard activeClients > 0 else { return }
        activeClients -= 1
        guard activeClients == 0 else { return }

        stopMouseDraggedMonitoring()
        mouseMoveMonitor?.stop()
        mouseDownMonitor?.stop()
        mouseUpMonitor?.stop()
    }

    func startMouseDraggedMonitoring() {
        guard activeClients > 0 else { return }
        guard !isDragMonitoring else { return }

        ensureMouseDraggedMonitor()
        mouseDraggedMonitor?.start()
        isDragMonitoring = true
    }

    func stopMouseDraggedMonitoring() {
        guard isDragMonitoring else { return }
        mouseDraggedMonitor?.stop()
        isDragMonitoring = false
    }

    private func ensureBaseMonitors() {
        if mouseMoveMonitor == nil {
            mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
                self?.mouseLocation.send(NSEvent.mouseLocation)
            }
        }

        if mouseDownMonitor == nil {
            mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] event in
                self?.mouseDown.send(event)
            }
        }

        if mouseUpMonitor == nil {
            mouseUpMonitor = EventMonitor(mask: .leftMouseUp) { [weak self] event in
                self?.mouseUp.send(event)
            }
        }
    }

    private func ensureMouseDraggedMonitor() {
        if mouseDraggedMonitor == nil {
            mouseDraggedMonitor = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
                let location = NSEvent.mouseLocation
                self?.mouseLocation.send(location)
                self?.mouseDragged.send(location)
            }
        }
    }
}
