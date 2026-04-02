//
//  SessionListPresentationController.swift
//  CodexIsland
//
//  UI-facing controller for session list sorting and grouping.
//

import Combine
import Foundation

enum SessionListSortMode: String, CaseIterable {
    case defaultOrder
    case updatedAt

    var title: String {
        switch self {
        case .defaultOrder:
            return "Default Order"
        case .updatedAt:
            return "Update Time"
        }
    }

    var shortTitle: String {
        switch self {
        case .defaultOrder:
            return "Default"
        case .updatedAt:
            return "Updated"
        }
    }
}

enum SessionListGroupingMode: String, CaseIterable {
    case none
    case sessionType
    case status

    var title: String {
        switch self {
        case .none:
            return "No Group"
        case .sessionType:
            return "Session Type"
        case .status:
            return "Status"
        }
    }

    var shortTitle: String {
        switch self {
        case .none:
            return "None"
        case .sessionType:
            return "Type"
        case .status:
            return "Status"
        }
    }
}

@MainActor
final class SessionListPresentationController: ObservableObject {
    static let shared = SessionListPresentationController()

    @Published private(set) var sortMode: SessionListSortMode
    @Published private(set) var groupingMode: SessionListGroupingMode

    private init() {
        sortMode = AppSettings.sessionListSortMode
        groupingMode = AppSettings.sessionListGroupingMode
    }

    func setSortMode(_ mode: SessionListSortMode) {
        guard sortMode != mode else { return }
        sortMode = mode
        AppSettings.sessionListSortMode = mode
    }

    func setGroupingMode(_ mode: SessionListGroupingMode) {
        guard groupingMode != mode else { return }
        groupingMode = mode
        AppSettings.sessionListGroupingMode = mode
    }
}
