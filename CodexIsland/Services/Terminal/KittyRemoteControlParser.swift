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
    let workingDirectory: String?
}

enum KittyRemoteControlParser {
    nonisolated static func parse(_ json: String) throws -> [ParsedKittyWindowRecord] {
        let data = Data(json.utf8)

        do {
            let raw = try JSONSerialization.jsonObject(with: data)
            guard let osWindows = raw as? [[String: Any]] else {
                throw TerminalBackendError.parseFailed("Unable to decode Kitty remote-control output.")
            }

            return osWindows.enumerated().flatMap { osWindowIndex, osWindow in
                let osWindowFocused = boolValue(from: osWindow["is_focused"]) ?? false
                let tabs = osWindow["tabs"] as? [[String: Any]] ?? []

                return tabs.enumerated().flatMap { tabIndex, tab -> [ParsedKittyWindowRecord] in
                    let tabTitle = stringValue(from: tab["title"]) ?? ""
                    let tabFocused = boolValue(from: tab["is_focused"]) ?? false
                    let windows = tab["windows"] as? [[String: Any]] ?? []

                    return windows.compactMap { window -> ParsedKittyWindowRecord? in
                        guard let windowID = intValue(from: window["id"]) else {
                            return nil
                        }

                        let title = stringValue(from: window["title"]) ?? tabTitle

                        return ParsedKittyWindowRecord(
                            windowID: windowID,
                            title: title.isEmpty ? tabTitle : title,
                            osWindowIndex: osWindowIndex + 1,
                            tabIndex: tabIndex + 1,
                            isFocused: boolValue(from: window["is_focused"]) ?? (tabFocused && osWindowFocused),
                            workingDirectory: extractWorkingDirectory(from: window)
                        )
                    }
                }
            }
        } catch {
            throw TerminalBackendError.parseFailed("Unable to decode Kitty remote-control output.")
        }
    }

    nonisolated private static func extractWorkingDirectory(from window: [String: Any]) -> String? {
        if let cwd = pathString(from: window["cwd"]) ?? pathString(from: window["current_working_directory"]) {
            return cwd
        }

        if let foregroundProcesses = window["foreground_processes"] as? [[String: Any]] {
            for process in foregroundProcesses {
                if let cwd = pathString(from: process["cwd"]) ?? pathString(from: process["current_working_directory"]) {
                    return cwd
                }
            }
        }

        return nil
    }

    nonisolated private static func pathString(from rawValue: Any?) -> String? {
        if let string = stringValue(from: rawValue), !string.isEmpty {
            return string
        }

        if let dictionary = rawValue as? [String: Any] {
            for key in ["path", "string", "value"] {
                if let value = stringValue(from: dictionary[key]), !value.isEmpty {
                    return value
                }
            }
        }

        if let values = rawValue as? [Any] {
            for value in values {
                if let path = pathString(from: value) {
                    return path
                }
            }
        }

        return nil
    }

    nonisolated private static func stringValue(from rawValue: Any?) -> String? {
        guard let rawValue else {
            return nil
        }

        if let string = rawValue as? String {
            return string
        }

        if let number = rawValue as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    nonisolated private static func intValue(from rawValue: Any?) -> Int? {
        if let value = rawValue as? Int {
            return value
        }

        if let number = rawValue as? NSNumber {
            return number.intValue
        }

        if let string = rawValue as? String {
            return Int(string)
        }

        return nil
    }

    nonisolated private static func boolValue(from rawValue: Any?) -> Bool? {
        if let value = rawValue as? Bool {
            return value
        }

        if let number = rawValue as? NSNumber {
            return number.boolValue
        }

        if let string = rawValue as? String {
            switch string.lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}
