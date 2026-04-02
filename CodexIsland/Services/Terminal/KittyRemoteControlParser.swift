//
//  KittyRemoteControlParser.swift
//  CodexIsland
//
//  Parses Kitty remote-control window listings.
//

import Foundation

struct ParsedKittyWindowRecord: Equatable, Sendable {
    let windowID: Int
    let title: String
    let osWindowIndex: Int
    let tabIndex: Int
    let isFocused: Bool
}

enum KittyRemoteControlParser {
    nonisolated static func parse(_ json: String) throws -> [ParsedKittyWindowRecord] {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        do {
            let osWindows = try decoder.decode([KittyOSWindow].self, from: data)

            return osWindows.enumerated().flatMap { osWindowIndex, osWindow in
                osWindow.tabs.enumerated().flatMap { tabIndex, tab in
                    tab.windows.map { window in
                        ParsedKittyWindowRecord(
                            windowID: window.id,
                            title: window.title.isEmpty ? tab.title : window.title,
                            osWindowIndex: osWindowIndex + 1,
                            tabIndex: tabIndex + 1,
                            isFocused: window.isFocused ?? (tab.isFocused && osWindow.isFocused)
                        )
                    }
                }
            }
        } catch {
            throw TerminalBackendError.parseFailed("Unable to decode Kitty remote-control output.")
        }
    }
}

private struct KittyOSWindow: Decodable {
    let isFocused: Bool
    let tabs: [KittyTab]

    enum CodingKeys: String, CodingKey {
        case isFocused = "is_focused"
        case tabs
    }
}

private struct KittyTab: Decodable {
    let title: String
    let isFocused: Bool
    let windows: [KittyWindow]

    enum CodingKeys: String, CodingKey {
        case title
        case isFocused = "is_focused"
        case windows
    }
}

private struct KittyWindow: Decodable {
    let id: Int
    let title: String
    let isFocused: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isFocused = "is_focused"
    }
}
