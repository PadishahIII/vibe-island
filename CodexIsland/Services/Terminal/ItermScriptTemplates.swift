//
//  ItermScriptTemplates.swift
//  CodexIsland
//
//  AppleScript templates for iTerm2 session enumeration and activation.
//

import Foundation

enum ItermScriptTemplates {
    static let availabilityCheck = """
    tell application id "com.googlecode.iterm2"
        return version
    end tell
    """

    static let enumerateSessions = """
    tell application id "com.googlecode.iterm2"
        set rowSeparator to linefeed
        set fieldSeparator to character id 31
        set outputRows to {}
        set windowCount to count of windows

        repeat with windowOffset from 1 to windowCount
            set aWindow to window windowOffset
            set windowIsFrontmost to frontmost of aWindow
            set tabCount to count of tabs of aWindow

            repeat with tabOffset from 1 to tabCount
                set aTab to tab tabOffset of aWindow
                set focusedSessionID to ""

                try
                    set focusedSessionID to unique ID of current session of aTab
                end try

                repeat with aSession in sessions of aTab
                    set sessionIDValue to unique ID of aSession
                    set sessionTitleValue to my sanitizeText(name of aSession)
                    set focusedValue to "0"

                    if windowIsFrontmost is true and focusedSessionID is equal to sessionIDValue then
                        set focusedValue to "1"
                    end if

                    set end of outputRows to sessionIDValue & fieldSeparator & sessionTitleValue & fieldSeparator & (windowOffset as text) & fieldSeparator & (tabOffset as text) & fieldSeparator & focusedValue
                end repeat
            end repeat
        end repeat

        set AppleScript's text item delimiters to rowSeparator
        set outputText to outputRows as text
        set AppleScript's text item delimiters to ""
        return outputText
    end tell

    on sanitizeText(inputText)
        set sanitized to inputText as text

        set AppleScript's text item delimiters to return
        set sanitizedParts to text items of sanitized
        set AppleScript's text item delimiters to " "
        set sanitized to sanitizedParts as text

        set AppleScript's text item delimiters to linefeed
        set sanitizedParts to text items of sanitized
        set AppleScript's text item delimiters to " "
        set sanitized to sanitizedParts as text

        set AppleScript's text item delimiters to character id 31
        set sanitizedParts to text items of sanitized
        set AppleScript's text item delimiters to "-"
        set sanitized to sanitizedParts as text

        set AppleScript's text item delimiters to ""
        return sanitized
    end sanitizeText
    """

    static func activateSession(_ sessionID: String) -> String {
        let escapedSessionID = escapeAppleScriptString(sessionID)

        return """
        tell application id "com.googlecode.iterm2"
            set targetSessionID to "\(escapedSessionID)"
            set windowCount to count of windows

            repeat with windowOffset from 1 to windowCount
                set aWindow to window windowOffset
                set tabCount to count of tabs of aWindow

                repeat with tabOffset from 1 to tabCount
                    set aTab to tab tabOffset of aWindow

                    repeat with aSession in sessions of aTab
                        if unique ID of aSession is equal to targetSessionID then
                            select aSession
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat

            return "not_found"
        end tell
        """
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
