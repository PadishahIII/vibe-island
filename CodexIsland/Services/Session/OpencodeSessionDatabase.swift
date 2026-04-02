//
//  OpencodeSessionDatabase.swift
//  CodexIsland
//
//  Read-only access layer for local opencode session data.
//

import Foundation
import SQLite3

actor OpencodeSessionDatabase {
    static let shared = OpencodeSessionDatabase()

    struct DirectoryRecord: Sendable {
        let path: String
        let updatedAt: Int64
        let sessionCount: Int
    }

    struct SessionRecord: Sendable {
        let id: String
        let parentId: String?
        let directory: String
        let title: String
        let timeCreated: Int64
        let timeUpdated: Int64
    }

    struct MessageRecord: Sendable {
        let id: String
        let sessionId: String
        let timeCreated: Int64
        let timeUpdated: Int64
        let rawData: String
    }

    struct PartRecord: Sendable {
        let id: String
        let messageId: String
        let sessionId: String
        let timeCreated: Int64
        let timeUpdated: Int64
        let rawData: String
    }

    struct SessionPayload: Sendable {
        let session: SessionRecord
        let messages: [MessageRecord]
        let parts: [PartRecord]
    }

    private let databasePath = NSHomeDirectory() + "/.local/share/opencode/opencode.db"
    private let fileManager = FileManager.default

    private init() {}

    func latestSessions(
        for directory: String,
        limit: Int,
        topLevelOnly: Bool = false
    ) -> [SessionRecord] {
        withDatabase { db in
            let sql: String
            if topLevelOnly {
                sql = """
                SELECT id, parent_id, directory, title, time_created, time_updated
                FROM session
                WHERE directory = ? AND parent_id IS NULL
                ORDER BY time_updated DESC
                LIMIT ?
                """
            } else {
                sql = """
                SELECT id, parent_id, directory, title, time_created, time_updated
                FROM session
                WHERE directory = ?
                ORDER BY time_updated DESC
                LIMIT ?
                """
            }

            guard let statement = prepare(db: db, sql: sql) else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            bindText(directory, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(limit))

            var sessions: [SessionRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                sessions.append(SessionRecord(
                    id: text(from: statement, at: 0) ?? "",
                    parentId: text(from: statement, at: 1),
                    directory: text(from: statement, at: 2) ?? "",
                    title: text(from: statement, at: 3) ?? "",
                    timeCreated: sqlite3_column_int64(statement, 4),
                    timeUpdated: sqlite3_column_int64(statement, 5)
                ))
            }
            return sessions
        } ?? []
    }

    func recentDirectories(limit: Int) -> [DirectoryRecord] {
        withDatabase { db in
            let sql = """
            SELECT directory, MAX(time_updated) AS updated_at, COUNT(*) AS session_count
            FROM session
            GROUP BY directory
            ORDER BY updated_at DESC
            LIMIT ?
            """

            guard let statement = prepare(db: db, sql: sql) else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(limit))

            var records: [DirectoryRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let path = text(from: statement, at: 0) ?? ""
                guard directoryExists(path) else {
                    continue
                }

                records.append(
                    DirectoryRecord(
                        path: path,
                        updatedAt: sqlite3_column_int64(statement, 1),
                        sessionCount: Int(sqlite3_column_int64(statement, 2))
                    )
                )
            }

            return records
        } ?? []
    }

    func sessionPayload(sessionId: String) -> SessionPayload? {
        withDatabase { db in
            guard let session = sessionRecord(id: sessionId, db: db) else {
                return nil
            }

            let messages = messageRecords(sessionId: sessionId, db: db)
            let parts = partRecords(sessionId: sessionId, db: db)
            return SessionPayload(session: session, messages: messages, parts: parts)
        }
    }

    func phase(sessionId: String) -> SessionPhase {
        withDatabase { db in
            guard sessionRecord(id: sessionId, db: db) != nil else {
                return .idle
            }

            let recentParts = partRecords(sessionId: sessionId, limit: 64, db: db)
            if recentParts.contains(where: isActiveToolPart) {
                return .processing
            }

            guard let latestMessage = latestMessageRecord(sessionId: sessionId, db: db),
                  let data = jsonObject(from: latestMessage.rawData) else {
                return .idle
            }

            let role = (data["role"] as? String)?.lowercased()
            let finish = (data["finish"] as? String)?.lowercased()
            let completedAt = ((data["time"] as? [String: Any])?["completed"] as? Int64)
                ?? ((data["time"] as? [String: Any])?["completed"] as? NSNumber)?.int64Value

            if role == "user" {
                return .processing
            }

            if finish == "tool-calls" {
                return .processing
            }

            if role == "assistant", finish == "stop" || completedAt != nil {
                return .waitingForInput
            }

            return .idle
        } ?? .idle
    }

    // MARK: - Query Helpers

    private func sessionRecord(id: String, db: OpaquePointer) -> SessionRecord? {
        let sql = """
        SELECT id, parent_id, directory, title, time_created, time_updated
        FROM session
        WHERE id = ?
        LIMIT 1
        """

        guard let statement = prepare(db: db, sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(id, to: statement, at: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return SessionRecord(
            id: text(from: statement, at: 0) ?? "",
            parentId: text(from: statement, at: 1),
            directory: text(from: statement, at: 2) ?? "",
            title: text(from: statement, at: 3) ?? "",
            timeCreated: sqlite3_column_int64(statement, 4),
            timeUpdated: sqlite3_column_int64(statement, 5)
        )
    }

    private func latestMessageRecord(sessionId: String, db: OpaquePointer) -> MessageRecord? {
        let sql = """
        SELECT id, session_id, time_created, time_updated, data
        FROM message
        WHERE session_id = ?
        ORDER BY time_created DESC
        LIMIT 1
        """

        guard let statement = prepare(db: db, sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(sessionId, to: statement, at: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return MessageRecord(
            id: text(from: statement, at: 0) ?? "",
            sessionId: text(from: statement, at: 1) ?? "",
            timeCreated: sqlite3_column_int64(statement, 2),
            timeUpdated: sqlite3_column_int64(statement, 3),
            rawData: text(from: statement, at: 4) ?? "{}"
        )
    }

    private func messageRecords(sessionId: String, db: OpaquePointer) -> [MessageRecord] {
        let sql = """
        SELECT id, session_id, time_created, time_updated, data
        FROM message
        WHERE session_id = ?
        ORDER BY time_created ASC, id ASC
        """

        guard let statement = prepare(db: db, sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bindText(sessionId, to: statement, at: 1)

        var messages: [MessageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            messages.append(MessageRecord(
                id: text(from: statement, at: 0) ?? "",
                sessionId: text(from: statement, at: 1) ?? "",
                timeCreated: sqlite3_column_int64(statement, 2),
                timeUpdated: sqlite3_column_int64(statement, 3),
                rawData: text(from: statement, at: 4) ?? "{}"
            ))
        }
        return messages
    }

    private func partRecords(
        sessionId: String,
        limit: Int? = nil,
        db: OpaquePointer
    ) -> [PartRecord] {
        let sql: String
        if limit != nil {
            sql = """
            SELECT id, message_id, session_id, time_created, time_updated, data
            FROM part
            WHERE session_id = ?
            ORDER BY time_created DESC, id DESC
            LIMIT ?
            """
        } else {
            sql = """
            SELECT id, message_id, session_id, time_created, time_updated, data
            FROM part
            WHERE session_id = ?
            ORDER BY time_created ASC, id ASC
            """
        }

        guard let statement = prepare(db: db, sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bindText(sessionId, to: statement, at: 1)
        if let limit {
            sqlite3_bind_int64(statement, 2, Int64(limit))
        }

        var parts: [PartRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            parts.append(PartRecord(
                id: text(from: statement, at: 0) ?? "",
                messageId: text(from: statement, at: 1) ?? "",
                sessionId: text(from: statement, at: 2) ?? "",
                timeCreated: sqlite3_column_int64(statement, 3),
                timeUpdated: sqlite3_column_int64(statement, 4),
                rawData: text(from: statement, at: 5) ?? "{}"
            ))
        }
        return parts
    }

    private func isActiveToolPart(_ part: PartRecord) -> Bool {
        guard let data = jsonObject(from: part.rawData),
              (data["type"] as? String) == "tool",
              let state = data["state"] as? [String: Any],
              let status = (state["status"] as? String)?.lowercased() else {
            return false
        }

        return status == "running" || status == "pending"
    }

    // MARK: - SQLite Helpers

    private func withDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            if let db {
                sqlite3_close(db)
            }
            return nil
        }
        defer { sqlite3_close(db) }

        return body(db)
    }

    private func prepare(db: OpaquePointer, sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func text(from statement: OpaquePointer?, at index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: raw)
    }

    private func jsonObject(from rawJSON: String) -> [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

nonisolated(unsafe) private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
