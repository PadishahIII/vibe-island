//
//  EventMonitors.swift
//  CodexIsland
//
//  Singleton that aggregates all event monitors
//

import AppKit
import Combine

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

    private init() {
        setupMonitors()
    }

    private func setupMonitors() {
        mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            self?.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseMoveMonitor?.start()

        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] event in
            self?.mouseDown.send(event)
        }
        mouseDownMonitor?.start()

        mouseUpMonitor = EventMonitor(mask: .leftMouseUp) { [weak self] event in
            self?.mouseUp.send(event)
        }
        mouseUpMonitor?.start()

        mouseDraggedMonitor = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
            let location = NSEvent.mouseLocation
            self?.mouseLocation.send(location)
            self?.mouseDragged.send(location)
        }
        mouseDraggedMonitor?.start()
    }

    deinit {
        mouseMoveMonitor?.stop()
        mouseDownMonitor?.stop()
        mouseUpMonitor?.stop()
        mouseDraggedMonitor?.stop()
    }
}
