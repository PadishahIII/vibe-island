//
//  AppleScriptRunner.swift
//  CodexIsland
//
//  Executes AppleScript requests off the main thread.
//

import AppKit
import Foundation

enum AppleScriptRunner {
    static func execute(source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var executionError: NSDictionary?

                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(
                        throwing: TerminalBackendError.scriptFailed("Unable to compile the AppleScript request.")
                    )
                    return
                }

                let descriptor = script.executeAndReturnError(&executionError)

                if let executionError {
                    let number = executionError[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = (executionError[NSAppleScript.errorBriefMessage] as? String)
                        ?? (executionError[NSAppleScript.errorMessage] as? String)
                        ?? "AppleScript failed."

                    switch number {
                    case -1743:
                        continuation.resume(throwing: TerminalBackendError.permissionRequired)
                    case -600:
                        continuation.resume(throwing: TerminalBackendError.notRunning)
                    default:
                        continuation.resume(throwing: TerminalBackendError.scriptFailed("\(message) (\(number))"))
                    }
                    return
                }

                continuation.resume(returning: descriptor.stringValue ?? "")
            }
        }
    }
}
