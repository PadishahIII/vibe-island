//
//  AccessibilityWindowBackend.swift
//  CodexIsland
//
//  Enumerates and focuses terminal OS windows via Accessibility APIs.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

actor AccessibilityWindowBackend: TerminalBackend {
    nonisolated let key: String
    nonisolated let provider: SessionProvider
    nonisolated let displayName: String

    private let bundleIdentifiers: [String]
    private let noticeMessage: String?
    private let ttyFallback: ProcessTreeTerminalFallbackBackend?
    private var lastSnapshotWindows: [String: WindowSignature] = [:]

    init(
        key: String,
        provider: SessionProvider,
        displayName: String,
        bundleIdentifiers: [String],
        noticeMessage: String? = nil,
        ttyFallback: ProcessTreeTerminalFallbackBackend? = nil
    ) {
        self.key = key
        self.provider = provider
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.noticeMessage = noticeMessage
        self.ttyFallback = ttyFallback
    }

    func availability() async -> TerminalBackendAvailability {
        guard isInstalled() else {
            return .notInstalled
        }

        let apps = runningApplications()
        guard !apps.isEmpty else {
            return .installedNotRunning
        }

        guard AccessibilityAuthorization.isTrusted() else {
            if let ttyFallback {
                let fallbackAvailability = await ttyFallback.availability()
                if fallbackAvailability.isReady {
                    return .ready
                }
            }
            return .permissionRequired
        }

        return .ready
    }

    func currentSnapshot() async throws -> TerminalSnapshot {
        guard isInstalled() else {
            throw TerminalBackendError.notInstalled
        }

        let apps = runningApplications()
        guard !apps.isEmpty else {
            throw TerminalBackendError.notRunning
        }

        guard AccessibilityAuthorization.isTrusted() else {
            if let ttyFallback {
                return try await ttyFallback.currentSnapshot()
            }
            throw TerminalBackendError.permissionRequired
        }

        let generatedAt = Date()
        let windows = try apps.flatMap { try enumerateWindows(for: $0) }
        lastSnapshotWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.signature) })

        let sessions = windows.enumerated().map { offset, window in
            TerminalSession(
                id: window.id,
                provider: provider,
                displayIndex: offset + 1,
                title: window.title,
                windowIndex: window.ordinal,
                tabIndex: nil,
                isFocused: window.isFocused,
                lastSeenAt: generatedAt,
                subtitle: nil,
                focusPid: Int(window.processID),
                tty: nil,
                workingDirectory: nil
            )
        }

        return TerminalSnapshot(
            sessions: sessions,
            generatedAt: generatedAt,
            noticeMessage: noticeMessage
        )
    }

    func activateSession(id: String) async throws {
        if id.hasPrefix("tty:") {
            guard let ttyFallback else {
                throw TerminalBackendError.sessionNotFound
            }
            try await ttyFallback.activateSession(id: id)
            return
        }

        let apps = runningApplications()
        guard !apps.isEmpty else {
            throw TerminalBackendError.notRunning
        }

        guard AccessibilityAuthorization.isTrusted() else {
            if let ttyFallback {
                try await ttyFallback.activateSession(id: id)
                return
            }
            throw TerminalBackendError.permissionRequired
        }

        let windows = try apps.flatMap { try enumerateWindows(for: $0) }
        guard let target = targetWindow(for: id, in: windows) else {
            throw TerminalBackendError.sessionNotFound
        }

        _ = target.application.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(target.processID)
        _ = AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
    }

    private func isInstalled() -> Bool {
        installedApplicationURL() != nil
    }

    private func installedApplicationURL() -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }
        return nil
    }

    private func runningApplications() -> [NSRunningApplication] {
        var applications: [pid_t: NSRunningApplication] = [:]

        for bundleIdentifier in bundleIdentifiers {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) where !application.isTerminated {
                applications[application.processIdentifier] = application
            }
        }

        return applications.values.sorted {
            if $0.isActive != $1.isActive {
                return $0.isActive && !$1.isActive
            }

            return $0.processIdentifier < $1.processIdentifier
        }
    }

    private func enumerateWindows(for app: NSRunningApplication) throws -> [WindowCandidate] {
        let processID = app.processIdentifier
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)

        guard error == .success else {
            throw TerminalBackendError.unavailable("Unable to enumerate \(displayName) windows.")
        }

        let cgWindows = cgWindowMetadata(for: processID)
        var usedCGWindowIDs: Set<Int> = []

        return ((value as? [AXUIElement]) ?? [])
            .enumerated()
            .compactMap { offset, window in
                let title = copiedStringAttribute(kAXTitleAttribute, from: window) ?? displayName
                let frame = copiedFrame(from: window) ?? .zero
                let isMinimized = copiedBoolAttribute(kAXMinimizedAttribute, from: window) ?? false
                let isFocused =
                    (copiedBoolAttribute(kAXFocusedAttribute, from: window) ?? false)
                    || (copiedBoolAttribute(kAXMainAttribute, from: window) ?? false)

                guard !isMinimized else {
                    return nil
                }

                let ordinal = offset + 1
                let cgWindow = bestCGWindowMatch(
                    title: title,
                    frame: frame,
                    windows: cgWindows,
                    usedIDs: &usedCGWindowIDs
                )
                let id =
                    cgWindow.map { "pid:\(processID):cg:\($0.id)" }
                    ?? fallbackIdentifier(processID: processID, title: title, frame: frame, ordinal: ordinal)

                return WindowCandidate(
                    id: id,
                    processID: processID,
                    ordinal: ordinal,
                    title: title.isEmpty ? "\(displayName) Window \(ordinal)" : title,
                    frame: frame,
                    isFocused: isFocused,
                    signature: WindowSignature(processID: processID, title: title, frame: frame, ordinal: ordinal),
                    application: app,
                    element: window
                )
            }
    }

    private func targetWindow(for id: String, in windows: [WindowCandidate]) -> WindowCandidate? {
        if let exact = windows.first(where: { $0.id == id }) {
            return exact
        }

        guard let signature = lastSnapshotWindows[id] else {
            return nil
        }

        return windows.first {
            $0.processID == signature.processID
                && normalizedTitle($0.title) == normalizedTitle(signature.title)
                && $0.ordinal == signature.ordinal
                && framesApproximatelyEqual($0.frame, signature.frame)
        }
    }
}

private struct WindowSignature: Sendable {
    let processID: pid_t
    let title: String
    let frame: CGRect
    let ordinal: Int
}

private struct WindowCandidate {
    let id: String
    let processID: pid_t
    let ordinal: Int
    let title: String
    let frame: CGRect
    let isFocused: Bool
    let signature: WindowSignature
    let application: NSRunningApplication
    nonisolated(unsafe) let element: AXUIElement
}

private struct CGWindowMetadata {
    let id: Int
    let title: String
    let frame: CGRect
}

nonisolated private func copiedStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
        return nil
    }

    return value as? String
}

nonisolated private func copiedBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
        return nil
    }

    return (value as? Bool) ?? ((value as? NSNumber)?.boolValue)
}

nonisolated private func copiedFrame(from element: AXUIElement) -> CGRect? {
    guard
        let position = copiedPointAttribute(kAXPositionAttribute, from: element),
        let size = copiedSizeAttribute(kAXSizeAttribute, from: element)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

nonisolated private func copiedPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }

    return point
}

nonisolated private func copiedSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
        return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }

    return size
}

nonisolated private func cgWindowMetadata(for pid: pid_t) -> [CGWindowMetadata] {
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

    return info.compactMap { window in
        guard
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
            ownerPID == pid,
            let layer = window[kCGWindowLayer as String] as? Int,
            layer == 0,
            let windowID = window[kCGWindowNumber as String] as? Int,
            let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds)
        else {
            return nil
        }

        let title = (window[kCGWindowName as String] as? String) ?? ""
        return CGWindowMetadata(id: windowID, title: title, frame: frame)
    }
}

nonisolated private func bestCGWindowMatch(
    title: String,
    frame: CGRect,
    windows: [CGWindowMetadata],
    usedIDs: inout Set<Int>
) -> CGWindowMetadata? {
    let normalizedCandidateTitle = normalizedTitle(title)

    let matches = windows
        .filter { !usedIDs.contains($0.id) }
        .sorted {
            cgWindowScore(for: $0, title: normalizedCandidateTitle, frame: frame)
                > cgWindowScore(for: $1, title: normalizedCandidateTitle, frame: frame)
        }

    guard let bestMatch = matches.first else {
        return nil
    }

    let score = cgWindowScore(for: bestMatch, title: normalizedCandidateTitle, frame: frame)
    guard score > 0 else {
        return nil
    }

    usedIDs.insert(bestMatch.id)
    return bestMatch
}

nonisolated private func cgWindowScore(for window: CGWindowMetadata, title: String, frame: CGRect) -> Int {
    var score = 0

    if normalizedTitle(window.title) == title {
        score += 5
    }

    if framesApproximatelyEqual(window.frame, frame) {
        score += 4
    }

    if abs(window.frame.midX - frame.midX) < 8, abs(window.frame.midY - frame.midY) < 8 {
        score += 1
    }

    return score
}

nonisolated private func normalizedTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

nonisolated private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) < 4
        && abs(lhs.origin.y - rhs.origin.y) < 4
        && abs(lhs.size.width - rhs.size.width) < 4
        && abs(lhs.size.height - rhs.size.height) < 4
}

nonisolated private func fallbackIdentifier(processID: pid_t, title: String, frame: CGRect, ordinal: Int) -> String {
    let sanitizedTitle = title
        .replacingOccurrences(of: ":", with: "_")
        .replacingOccurrences(of: "|", with: "_")

    return "pid:\(processID):ax:\(ordinal):\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height)):\(sanitizedTitle)"
}
