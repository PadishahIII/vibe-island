//
//  CodexSessionDatabase.swift
//  CodexIsland
//
//  Read-only access layer for local codex thread metadata.
//

import Foundation
import SQLite3

actor CodexSessionDatabase {
    static let shared = CodexSessionDatabase()

    struct DirectoryRecord: Sendable {
        let path: String
        let updatedAt: Int64
        let sessionCount: Int
    }

    struct ThreadRecord: Sendable {
        let id: String
        let cwd: String
        let title: String
        let rolloutPath: String
        let createdAt: Int64
        let updatedAt: Int64
    }

    private let databasePath = NSHomeDirectory() + "/.codex/state_5.sqlite"
    private let fileManager = FileManager.default

    private init() {}

    func latestThreads(for directory: String, limit: Int) -> [ThreadRecord] {
        withDatabase { db in
            let sql = """
            SELECT id, cwd, title, rollout_path, created_at, updated_at
            FROM threads
            WHERE cwd = ? AND archived = 0
            ORDER BY updated_at DESC
            LIMIT ?
            """

            guard let statement = prepare(db: db, sql: sql) else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            bindText(directory, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(limit))

            var threads: [ThreadRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                threads.append(ThreadRecord(
                    id: text(from: statement, at: 0) ?? "",
                    cwd: text(from: statement, at: 1) ?? "",
                    title: text(from: statement, at: 2) ?? "",
                    rolloutPath: text(from: statement, at: 3) ?? "",
                    createdAt: sqlite3_column_int64(statement, 4),
                    updatedAt: sqlite3_column_int64(statement, 5)
                ))
            }

            return threads.filter {
                !$0.rolloutPath.isEmpty && FileManager.default.fileExists(atPath: $0.rolloutPath)
            }
        } ?? []
    }

    func recentDirectories(limit: Int) -> [DirectoryRecord] {
        withDatabase { db in
            let sql = """
            SELECT cwd, MAX(updated_at) AS updated_at, COUNT(*) AS session_count
            FROM threads
            WHERE archived = 0
            GROUP BY cwd
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
        sqlite3_bind_text(statement, index, value, -1, codexSQLiteTransient)
    }

    private func text(from statement: OpaquePointer?, at index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: raw)
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

nonisolated(unsafe) private let codexSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
