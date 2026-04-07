//
//  SessionTitlePrompt.swift
//  CodexIsland
//
//  Native editor prompt for per-session display title overrides.
//

import AppKit
import Foundation

enum SessionTitlePrompt {
    @MainActor
    static func present(for session: SessionState) -> SessionTitleEditAction? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Edit Display Title"
        alert.informativeText = "Only changes the title shown inside Vibe Island."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")

        let textField = NSTextField(string: session.customTitle ?? session.displayTitle)
        textField.placeholderString = session.defaultDisplayTitle
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1

        let hintLabel = NSTextField(labelWithString: "Leave empty to restore the original title.")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [textField, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 54))
        accessory.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            stack.topAnchor.constraint(equalTo: accessory.topAnchor),
            stack.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            textField.widthAnchor.constraint(equalToConstant: 320),
        ])

        alert.accessoryView = accessory

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let normalized = SessionTitleStore.normalizedTitle(textField.stringValue)
            if normalized == session.defaultDisplayTitle {
                return .save(nil)
            }
            return .save(normalized)
        case .alertThirdButtonReturn:
            return .save(nil)
        default:
            return nil
        }
    }
}

enum SessionTitleEditAction {
    case save(String?)
}
