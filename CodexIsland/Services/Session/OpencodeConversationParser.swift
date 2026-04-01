//
//  OpencodeConversationParser.swift
//  CodexIsland
//
//  Parses local opencode SQLite session data into chat history snapshots.
//

import Foundation

actor OpencodeConversationParser {
    static let shared = OpencodeConversationParser()

    private struct Snapshot {
        let token: Int64
        let messages: [ChatMessage]
        let messageSignatures: [String: String]
        let completedToolIds: Set<String>
        let toolResults: [String: ConversationParser.ToolResult]
        let structuredResults: [String: ToolResultData]
        let conversationInfo: ConversationInfo
        let subagentTools: [SubagentToolInfo]
    }

    private struct ParsedPart {
        let message: ChatMessage?
        let signature: String
        let completedToolId: String?
        let toolResult: (String, ConversationParser.ToolResult)?
        let structuredResult: (String, ToolResultData)?
        let subagentTool: SubagentToolInfo?
        let toolName: String?
    }

    private var snapshots: [String: Snapshot] = [:]
    private let database = OpencodeSessionDatabase.shared

    func parse(sessionId: String) async -> ConversationInfo {
        await loadSnapshot(sessionId: sessionId)?.conversationInfo ?? emptyConversationInfo
    }

    func parseFullConversation(sessionId: String) async -> [ChatMessage] {
        await loadSnapshot(sessionId: sessionId)?.messages ?? []
    }

    func parseIncremental(sessionId: String) async -> ConversationParser.IncrementalParseResult {
        guard let payload = await database.sessionPayload(sessionId: sessionId) else {
            return emptyIncrementalResult
        }

        let previous = snapshots[sessionId]
        let snapshot = buildSnapshot(from: payload)
        snapshots[sessionId] = snapshot

        let changedMessages: [ChatMessage]
        if let previous, previous.token == snapshot.token {
            changedMessages = []
        } else if let previous {
            changedMessages = snapshot.messages.filter {
                previous.messageSignatures[$0.id] != snapshot.messageSignatures[$0.id]
            }
        } else {
            changedMessages = snapshot.messages
        }

        return ConversationParser.IncrementalParseResult(
            newMessages: changedMessages,
            allMessages: snapshot.messages,
            completedToolIds: snapshot.completedToolIds,
            toolResults: snapshot.toolResults,
            structuredResults: snapshot.structuredResults,
            clearDetected: false
        )
    }

    func completedToolIds(sessionId: String) async -> Set<String> {
        await loadSnapshot(sessionId: sessionId)?.completedToolIds ?? []
    }

    func toolResults(sessionId: String) async -> [String: ConversationParser.ToolResult] {
        await loadSnapshot(sessionId: sessionId)?.toolResults ?? [:]
    }

    func structuredResults(sessionId: String) async -> [String: ToolResultData] {
        await loadSnapshot(sessionId: sessionId)?.structuredResults ?? [:]
    }

    func parseSubagentTools(sessionId: String) async -> [SubagentToolInfo] {
        await loadSnapshot(sessionId: sessionId)?.subagentTools ?? []
    }

    // MARK: - Snapshot Loading

    private func loadSnapshot(sessionId: String) async -> Snapshot? {
        guard let payload = await database.sessionPayload(sessionId: sessionId) else {
            return nil
        }

        if let cached = snapshots[sessionId], cached.token == payload.session.timeUpdated {
            return cached
        }

        let snapshot = buildSnapshot(from: payload)
        snapshots[sessionId] = snapshot
        return snapshot
    }

    private func buildSnapshot(from payload: OpencodeSessionDatabase.SessionPayload) -> Snapshot {
        let partsByMessage = Dictionary(grouping: payload.parts, by: \.messageId)

        var messages: [ChatMessage] = []
        var messageSignatures: [String: String] = [:]
        var completedToolIds: Set<String> = []
        var toolResults: [String: ConversationParser.ToolResult] = [:]
        var structuredResults: [String: ToolResultData] = [:]
        var subagentTools: [SubagentToolInfo] = []
        var lastToolName: String?

        for messageRow in payload.messages {
            let role = parseRole(from: messageRow.rawData)
            let messageParts = partsByMessage[messageRow.id] ?? []

            for partRow in messageParts {
                let parsed = parsePart(partRow, role: role)
                if let message = parsed.message {
                    messages.append(message)
                    messageSignatures[message.id] = parsed.signature
                }
                if let completedToolId = parsed.completedToolId {
                    completedToolIds.insert(completedToolId)
                }
                if let (toolId, result) = parsed.toolResult {
                    toolResults[toolId] = result
                }
                if let (toolId, structuredResult) = parsed.structuredResult {
                    structuredResults[toolId] = structuredResult
                }
                if let subagentTool = parsed.subagentTool {
                    subagentTools.append(subagentTool)
                }
                if let toolName = parsed.toolName {
                    lastToolName = toolName
                }
            }
        }

        messages.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        let conversationInfo = buildConversationInfo(
            title: payload.session.title,
            messages: messages,
            lastToolName: lastToolName
        )

        return Snapshot(
            token: payload.session.timeUpdated,
            messages: messages,
            messageSignatures: messageSignatures,
            completedToolIds: completedToolIds,
            toolResults: toolResults,
            structuredResults: structuredResults,
            conversationInfo: conversationInfo,
            subagentTools: subagentTools
        )
    }

    // MARK: - Part Parsing

    private func parsePart(_ row: OpencodeSessionDatabase.PartRecord, role: ChatRole) -> ParsedPart {
        guard let data = jsonObject(from: row.rawData),
              let type = data["type"] as? String else {
            return ParsedPart(
                message: nil,
                signature: row.rawData,
                completedToolId: nil,
                toolResult: nil,
                structuredResult: nil,
                subagentTool: nil,
                toolName: nil
            )
        }

        let timestamp = date(fromMilliseconds: row.timeCreated)

        switch type {
        case "text":
            let text = (data["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                return ParsedPart(
                    message: nil,
                    signature: row.rawData,
                    completedToolId: nil,
                    toolResult: nil,
                    structuredResult: nil,
                    subagentTool: nil,
                    toolName: nil
                )
            }

            return ParsedPart(
                message: ChatMessage(id: row.id, role: role, timestamp: timestamp, content: [.text(text)]),
                signature: row.rawData,
                completedToolId: nil,
                toolResult: nil,
                structuredResult: nil,
                subagentTool: nil,
                toolName: nil
            )

        case "reasoning":
            let text = (data["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                return ParsedPart(
                    message: nil,
                    signature: row.rawData,
                    completedToolId: nil,
                    toolResult: nil,
                    structuredResult: nil,
                    subagentTool: nil,
                    toolName: nil
                )
            }

            return ParsedPart(
                message: ChatMessage(
                    id: row.id,
                    role: .assistant,
                    timestamp: timestamp,
                    content: [.thinking(text)]
                ),
                signature: row.rawData,
                completedToolId: nil,
                toolResult: nil,
                structuredResult: nil,
                subagentTool: nil,
                toolName: nil
            )

        case "tool":
            guard let callId = data["callID"] as? String,
                  let rawToolName = data["tool"] as? String else {
                return ParsedPart(
                    message: nil,
                    signature: row.rawData,
                    completedToolId: nil,
                    toolResult: nil,
                    structuredResult: nil,
                    subagentTool: nil,
                    toolName: nil
                )
            }

            let toolName = normalizedToolName(from: rawToolName)
            let state = data["state"] as? [String: Any]
            let rawStatus = (state?["status"] as? String)?.lowercased() ?? "completed"
            let input = stringMap(from: state?["input"])
            let output = extractToolOutput(from: state)
            let exitCode = extractExitCode(from: state)
            let isCompleted = rawStatus == "completed" || rawStatus == "error" || rawStatus == "failed"
            let isError = rawStatus == "error" || rawStatus == "failed" || (exitCode != nil && exitCode != 0)

            let toolMessage = ChatMessage(
                id: row.id,
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: toolName, input: input))]
            )

            var toolResult: (String, ConversationParser.ToolResult)?
            if isCompleted {
                toolResult = (
                    callId,
                    ConversationParser.ToolResult(
                        content: output,
                        stdout: nil,
                        stderr: nil,
                        isError: isError
                    )
                )
            }

            var structuredResult: (String, ToolResultData)?
            if toolName == "Task" {
                let subSessionId = input["session_id"] ?? ""
                structuredResult = (
                    callId,
                    .task(TaskResult(
                        agentId: subSessionId,
                        status: rawStatus,
                        content: output ?? "",
                        prompt: input["prompt"],
                        totalDurationMs: extractDurationMs(from: state),
                        totalTokens: nil,
                        totalToolUseCount: nil
                    ))
                )
            }

            let subagentTool = SubagentToolInfo(
                id: callId,
                name: toolName,
                input: input,
                isCompleted: isCompleted,
                timestamp: isoTimestamp(from: timestamp)
            )

            return ParsedPart(
                message: toolMessage,
                signature: row.rawData,
                completedToolId: isCompleted ? callId : nil,
                toolResult: toolResult,
                structuredResult: structuredResult,
                subagentTool: subagentTool,
                toolName: toolName
            )

        case "step-finish":
            if (data["reason"] as? String)?.lowercased() == "interrupt" {
                return ParsedPart(
                    message: ChatMessage(
                        id: row.id,
                        role: .assistant,
                        timestamp: timestamp,
                        content: [.interrupted]
                    ),
                    signature: row.rawData,
                    completedToolId: nil,
                    toolResult: nil,
                    structuredResult: nil,
                    subagentTool: nil,
                    toolName: nil
                )
            }
            fallthrough

        default:
            return ParsedPart(
                message: nil,
                signature: row.rawData,
                completedToolId: nil,
                toolResult: nil,
                structuredResult: nil,
                subagentTool: nil,
                toolName: nil
            )
        }
    }

    // MARK: - Conversation Info

    private func buildConversationInfo(
        title: String,
        messages: [ChatMessage],
        lastToolName: String?
    ) -> ConversationInfo {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstUserMessage: String?
        var lastUserMessageDate: Date?
        var lastAssistantMessage: String?
        var lastMessageRole: String?

        for message in messages {
            switch message.role {
            case .user:
                if let text = firstText(in: message), !text.isEmpty {
                    if firstUserMessage == nil {
                        firstUserMessage = text
                    }
                    lastUserMessageDate = message.timestamp
                }
            case .assistant:
                if let text = firstText(in: message), !text.isEmpty {
                    lastAssistantMessage = text
                    lastMessageRole = "assistant"
                }
            case .system:
                continue
            }
        }

        return ConversationInfo(
            summary: trimmedTitle.isEmpty ? nil : trimmedTitle,
            lastMessage: lastAssistantMessage,
            lastMessageRole: lastMessageRole,
            lastToolName: lastToolName,
            firstUserMessage: firstUserMessage ?? (trimmedTitle.isEmpty ? nil : trimmedTitle),
            lastUserMessageDate: lastUserMessageDate
        )
    }

    private func firstText(in message: ChatMessage) -> String? {
        for block in message.content {
            switch block {
            case .text(let text), .thinking(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            case .toolUse, .interrupted:
                continue
            }
        }
        return nil
    }

    // MARK: - Value Helpers

    private func parseRole(from rawJSON: String) -> ChatRole {
        guard let data = jsonObject(from: rawJSON),
              let rawRole = (data["role"] as? String)?.lowercased(),
              let role = ChatRole(rawValue: rawRole) else {
            return .assistant
        }
        return role
    }

    private func jsonObject(from rawJSON: String) -> [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func stringMap(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in dictionary {
            if let string = value as? String {
                result[key] = string
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            } else if JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value),
                      let string = String(data: data, encoding: .utf8) {
                result[key] = string
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }

    private func normalizedToolName(from rawName: String) -> String {
        switch rawName.lowercased() {
        case "bash":
            return "Bash"
        case "read":
            return "Read"
        case "edit":
            return "Edit"
        case "write":
            return "Write"
        case "grep":
            return "Grep"
        case "glob":
            return "Glob"
        case "task":
            return "Task"
        case "todowrite":
            return "TodoWrite"
        case "webfetch":
            return "WebFetch"
        case "websearch":
            return "WebSearch"
        default:
            return rawName
                .split(separator: "_")
                .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
                .joined()
        }
    }

    private func extractToolOutput(from state: [String: Any]?) -> String? {
        if let output = state?["output"] as? String, !output.isEmpty {
            return output
        }

        if let metadata = state?["metadata"] as? [String: Any],
           let output = metadata["output"] as? String,
           !output.isEmpty {
            return output
        }

        return nil
    }

    private func extractExitCode(from state: [String: Any]?) -> Int? {
        if let metadata = state?["metadata"] as? [String: Any] {
            if let exitCode = metadata["exit"] as? Int {
                return exitCode
            }
            if let exitCode = metadata["exit"] as? NSNumber {
                return exitCode.intValue
            }
        }
        return nil
    }

    private func extractDurationMs(from state: [String: Any]?) -> Int? {
        guard let time = state?["time"] as? [String: Any] else {
            return nil
        }

        let start = (time["start"] as? NSNumber)?.intValue ?? (time["start"] as? Int)
        let end = (time["end"] as? NSNumber)?.intValue ?? (time["end"] as? Int)
        if let start, let end, end >= start {
            return end - start
        }
        return nil
    }

    private func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private func isoTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

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
}
