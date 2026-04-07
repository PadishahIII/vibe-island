//
//  CreateSessionView.swift
//  CodexIsland
//
//  Workspace picker and Kitty-backed new session launcher.
//

import AppKit
import SwiftUI

struct CreateSessionView: View {
    @ObservedObject var viewModel: NotchViewModel

    @State private var selectedKind: NewSessionKind = .codex
    @State private var workspaceSuggestions: [WorkspaceSuggestion] = []
    @State private var selectedSuggestionPath: String?
    @State private var directoryPath: String = ""
    @State private var kittyStatus: KittyRemoteControlStatus?
    @State private var errorMessage: String?
    @State private var isLoadingSuggestions = false
    @State private var isLaunching = false

    private let workspaceService = WorkspaceSuggestionService.shared
    private let kittyRemoteControl = KittyRemoteControlService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            kindPicker
            helperSection
            workspaceSection
            directorySection
            Spacer(minLength: 0)
            actionRow
        }
        .padding(.top, 6)
        .task {
            await refreshContent(resetDirectory: true)
        }
        .onChange(of: selectedKind) { _, _ in
            Task {
                await refreshContent(resetDirectory: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.showInstances()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Create Session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Launch through Kitty remote control.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Session Type")

            Picker("Session Type", selection: $selectedKind) {
                ForEach(NewSessionKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImageName)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedKind.helperText)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.42))
        }
    }

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage, !errorMessage.isEmpty {
                messageCard(
                    title: "Launch Error",
                    message: errorMessage,
                    color: TerminalColors.amber
                )
            }

            if let kittyStatus, let blockingMessage = kittyStatus.blockingMessage {
                VStack(alignment: .leading, spacing: 8) {
                    messageCard(
                        title: "Kitty Remote Control Required",
                        message: blockingMessage,
                        color: TerminalColors.prompt
                    )

                    if let command = kittyStatus.suggestedLaunchCommand {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start Kitty once with remote control enabled:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.62))

                            SelectableCodeBlock(text: command)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                    }

                    HStack {
                        Spacer()

                        Button {
                            Task {
                                await refreshContent(resetDirectory: false)
                            }
                        } label: {
                            Text("Refresh Status")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Stored Workspaces")
                Spacer()

                if isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.8))
                } else {
                    Text("\(workspaceSuggestions.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            if workspaceSuggestions.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 110)
                    .overlay(alignment: .center) {
                        Text(emptyWorkspaceMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.38))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(workspaceSuggestions) { suggestion in
                            Button {
                                selectWorkspace(suggestion.path)
                            } label: {
                                workspaceRow(for: suggestion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 170)
            }
        }
    }

    @ViewBuilder
    private func workspaceRow(for suggestion: WorkspaceSuggestion) -> some View {
        let isSelected = selectedSuggestionPath == suggestion.path

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(suggestion.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(suggestion.sourceLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .black.opacity(0.75) : .white.opacity(0.42))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.08))
                    )
            }

            Text(suggestion.path)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.48))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? TerminalColors.prompt.opacity(0.2) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? TerminalColors.prompt.opacity(0.6) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Directory")

            HStack(spacing: 8) {
                TextField("Enter a custom directory", text: $directoryPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .onChange(of: directoryPath) { _, newValue in
                        if selectedSuggestionPath == newValue {
                            return
                        }
                        selectedSuggestionPath = nil
                    }

                Button {
                    browseForDirectory()
                } label: {
                    Text("Browse")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.showInstances()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                launchSelectedSession()
            } label: {
                HStack(spacing: 6) {
                    if isLaunching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: selectedKind.systemImageName)
                            .font(.system(size: 11, weight: .semibold))
                    }

                    Text(selectedKind.actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(canLaunch ? .black : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(canLaunch ? Color.white.opacity(0.92) : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)
        }
    }

    private var emptyWorkspaceMessage: String {
        switch selectedKind {
        case .codex:
            return "No stored Codex workspaces yet. Select a custom directory below."
        case .opencode:
            return "No stored OpenCode workspaces yet. Select a custom directory below."
        case .terminal:
            return "No stored terminal workspaces yet. Select a custom directory below."
        }
    }

    private var canLaunch: Bool {
        guard !trimmedDirectory.isEmpty else {
            return false
        }

        guard kittyStatus?.isReady == true else {
            return false
        }

        return !isLaunching
    }

    private var trimmedDirectory: String {
        directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.36))
    }

    private func messageCard(title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }

    private func refreshContent(resetDirectory: Bool) async {
        let requestedKind = selectedKind

        await MainActor.run {
            isLoadingSuggestions = true
            errorMessage = nil
        }

        async let statusTask = kittyRemoteControl.status()
        async let suggestionsTask = workspaceService.suggestions(for: requestedKind)

        let (status, suggestions) = await (statusTask, suggestionsTask)

        await MainActor.run {
            guard requestedKind == selectedKind else {
                return
            }

            kittyStatus = status
            workspaceSuggestions = suggestions
            isLoadingSuggestions = false

            if resetDirectory {
                if let first = suggestions.first {
                    directoryPath = first.path
                    selectedSuggestionPath = first.path
                } else {
                    directoryPath = ""
                    selectedSuggestionPath = nil
                }
            } else if let selectedSuggestionPath,
                      !suggestions.contains(where: { $0.path == selectedSuggestionPath }) {
                self.selectedSuggestionPath = nil
            }
        }
    }

    private func selectWorkspace(_ path: String) {
        directoryPath = path
        selectedSuggestionPath = path
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            directoryPath = url.path
            selectedSuggestionPath = nil
        }
    }

    private func launchSelectedSession() {
        let directory = trimmedDirectory
        guard !directory.isEmpty else {
            errorMessage = "Select or enter a workspace directory first."
            return
        }

        isLaunching = true
        errorMessage = nil

        let requestedKind = selectedKind
        Task {
            do {
                try await kittyRemoteControl.launchSession(kind: requestedKind, directory: directory)
                await workspaceService.remember(directory: directory, for: requestedKind)

                await MainActor.run {
                    isLaunching = false
                    viewModel.showInstances()
                }
            } catch {
                await MainActor.run {
                    isLaunching = false
                    errorMessage = error.localizedDescription
                }
                await refreshContent(resetDirectory: false)
            }
        }
    }
}
