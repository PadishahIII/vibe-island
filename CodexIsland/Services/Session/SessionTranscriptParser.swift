//
//  SessionTranscriptParser.swift
//  CodexIsland
//
//  Provider-aware transcript parsing facade.
//

import Foundation

actor SessionTranscriptParser {
    static let shared = SessionTranscriptParser()

    private var emptyConversationInfo: ConversationInfo {
        ConversationInfo(
            summary: nil,
            lastMessage: nil,
            lastMessageRole: nil,
            lastToolName: nil,
            firstUserMessage: nil,
            lastUserMessageDate: nil
        )
    }

    private var emptyIncrementalResult: ConversationParser.IncrementalParseResult {
        ConversationParser.IncrementalParseResult(
            newMessages: [],
            allMessages: [],
            completedToolIds: [],
            toolResults: [:],
            structuredResults: [:],
            clearDetected: false
        )
    }

    func parse(session: SessionState) async -> ConversationInfo {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.parse(sessionId: session.sessionId, cwd: session.cwd)
        case .codex:
            return await CodexConversationParser.shared.parse(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.parse(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return emptyConversationInfo
        }
    }

    func parseFullConversation(session: SessionState) async -> [ChatMessage] {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.parseFullConversation(
                sessionId: session.sessionId,
                cwd: session.cwd
            )
        case .codex:
            return await CodexConversationParser.shared.parseFullConversation(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.parseFullConversation(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return []
        }
    }

    func parseIncremental(session: SessionState) async -> ConversationParser.IncrementalParseResult {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.parseIncremental(
                sessionId: session.sessionId,
                cwd: session.cwd
            )
        case .codex:
            return await CodexConversationParser.shared.parseIncremental(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.parseIncremental(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return emptyIncrementalResult
        }
    }

    func completedToolIds(session: SessionState) async -> Set<String> {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.completedToolIds(for: session.sessionId)
        case .codex:
            return await CodexConversationParser.shared.completedToolIds(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.completedToolIds(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return []
        }
    }

    func toolResults(session: SessionState) async -> [String: ConversationParser.ToolResult] {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.toolResults(for: session.sessionId)
        case .codex:
            return await CodexConversationParser.shared.toolResults(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.toolResults(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return [:]
        }
    }

    func structuredResults(session: SessionState) async -> [String: ToolResultData] {
        switch session.provider {
        case .claude:
            return await ConversationParser.shared.structuredResults(for: session.sessionId)
        case .codex:
            return await CodexConversationParser.shared.structuredResults(
                sessionId: session.sessionId,
                transcriptPath: session.transcriptPath
            )
        case .opencode:
            return await OpencodeConversationParser.shared.structuredResults(sessionId: session.sessionId)
        case .iterm2, .kitty, .alacritty:
            return [:]
        }
    }
}
