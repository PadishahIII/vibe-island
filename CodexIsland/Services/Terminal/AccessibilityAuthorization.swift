//
//  AccessibilityAuthorization.swift
//  CodexIsland
//
//  Accessibility permission helpers for terminal enumeration.
//

import ApplicationServices
import Foundation

enum AccessibilityAuthorization {
    nonisolated private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    nonisolated static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    nonisolated static func requestIfNeeded(prompt: Bool) -> Bool {
        guard prompt else {
            return isTrusted()
        }

        let options = [promptOptionKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
