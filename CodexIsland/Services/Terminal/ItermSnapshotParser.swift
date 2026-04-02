//
//  ItermSnapshotParser.swift
//  CodexIsland
//
//  Parses iTerm2 AppleScript session rows.
//

import Foundation

struct ParsedItermSessionRecord: Equatable, Sendable {
    let backendSessionID: String
    let title: String
    let windowIndex: Int
    let tabIndex: Int
    let isFocused: Bool
}

enum ItermSnapshotParser {
    nonisolated private static let fieldSeparator = Character(UnicodeScalar(31)!)

    nonisolated static func parse(_ output: String) throws -> [ParsedItermSessionRecord] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return []
        }

        return try trimmed
            .split(whereSeparator: \.isNewline)
            .map { line in
                let fields = line.split(separator: fieldSeparator, omittingEmptySubsequences: false)

                guard fields.count == 5 else {
                    throw TerminalBackendError.parseFailed("Unexpected iTerm2 session row format: \(line)")
                }

                let sessionID = String(fields[0])
                let title = String(fields[1])

                guard !sessionID.isEmpty else {
                    throw TerminalBackendError.parseFailed("Encountered an iTerm2 session without an identifier.")
                }

                guard let windowIndex = Int(fields[2]) else {
                    throw TerminalBackendError.parseFailed("Invalid iTerm2 window index: \(fields[2])")
                }

                guard let tabIndex = Int(fields[3]) else {
                    throw TerminalBackendError.parseFailed("Invalid iTerm2 tab index: \(fields[3])")
                }

                let focusedField = String(fields[4]).lowercased()
                let isFocused = focusedField == "1" || focusedField == "true"

                return ParsedItermSessionRecord(
                    backendSessionID: sessionID,
                    title: title,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    isFocused: isFocused
                )
            }
    }
}
