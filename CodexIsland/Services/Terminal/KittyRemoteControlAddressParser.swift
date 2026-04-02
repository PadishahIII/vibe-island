//
//  KittyRemoteControlAddressParser.swift
//  CodexIsland
//
//  Extracts Kitty listen-on endpoints from process arguments.
//

import Foundation

enum KittyRemoteControlAddressParser {
    nonisolated static func parse(commandLine: String) -> String? {
        let tokens = shellSplit(commandLine)

        guard !tokens.isEmpty else {
            return nil
        }

        for (index, token) in tokens.enumerated() {
            if token == "--listen-on", index + 1 < tokens.count {
                return normalizedAddress(tokens[index + 1])
            }

            if token.hasPrefix("--listen-on=") {
                return normalizedAddress(String(token.dropFirst("--listen-on=".count)))
            }

            if token == "-o", index + 1 < tokens.count {
                if let address = overrideAddress(from: tokens[index + 1]) {
                    return address
                }
            }

            if token.hasPrefix("-o"), token.count > 2 {
                let overrideToken: String

                if token.hasPrefix("-o=") {
                    overrideToken = String(token.dropFirst(3))
                } else {
                    overrideToken = String(token.dropFirst(2))
                }

                if let address = overrideAddress(from: overrideToken) {
                    return address
                }
            }
        }

        return nil
    }

    nonisolated private static func overrideAddress(from token: String) -> String? {
        guard token.hasPrefix("listen_on=") else {
            return nil
        }

        return normalizedAddress(String(token.dropFirst("listen_on=".count)))
    }

    nonisolated private static func normalizedAddress(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    nonisolated private static func shellSplit(_ commandLine: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoteCharacter: Character?
        var isEscaping = false

        for character in commandLine {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" && quoteCharacter != "'" {
                isEscaping = true
                continue
            }

            if let activeQuoteCharacter = quoteCharacter {
                if character == activeQuoteCharacter {
                    quoteCharacter = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quoteCharacter = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
