//
//  SessionVisibilitySelector.swift
//  CodexIsland
//
//  UI-facing controller for per-provider visibility settings.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class SessionVisibilitySelector: ObservableObject {
    static let shared = SessionVisibilitySelector()

    @Published var isPickerExpanded: Bool = false
    @Published private(set) var visibleProviders: Set<SessionProvider>

    private init() {
        self.visibleProviders = Set(AppSettings.visibleSessionProviders)
    }

    var expandedPickerHeight: CGFloat {
        guard isPickerExpanded else { return 0 }
        return CGFloat(SessionProvider.visibilityOptions.count * 30 + 12)
    }

    var currentSelectionLabel: String {
        let visibleCount = visibleProviders.count
        let totalCount = SessionProvider.visibilityOptions.count

        if visibleCount == totalCount {
            return "All"
        }

        if visibleCount == 0 {
            return "None"
        }

        return "\(visibleCount) Visible"
    }

    func refreshFromSettings() {
        visibleProviders = Set(AppSettings.visibleSessionProviders)
    }

    func isVisible(_ provider: SessionProvider) -> Bool {
        visibleProviders.contains(provider)
    }

    func setVisible(_ isVisible: Bool, for provider: SessionProvider) {
        var updated = visibleProviders
        if isVisible {
            updated.insert(provider)
        } else {
            updated.remove(provider)
        }
        apply(updated)
    }

    func toggle(_ provider: SessionProvider) {
        setVisible(!isVisible(provider), for: provider)
    }

    private func apply(_ providers: Set<SessionProvider>) {
        visibleProviders = providers
        AppSettings.visibleSessionProviders = SessionProvider.visibilityOptions.filter { providers.contains($0) }
    }
}
