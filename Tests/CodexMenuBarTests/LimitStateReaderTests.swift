import Foundation
import SQLite3
import Testing
@testable import CodexMenuBar

@Suite("Codex limit reader tests")
struct LimitStateReaderTests {
    @Test("Reads owned reset credits independently of currently applicable credits")
    func resetCreditsCount() throws {
        let data = Data(#"{"rate_limit_reset_credits":{"available_count":2,"applicable_available_count":0}}"#.utf8)
        let state = try #require(LimitStateReader.decodeLiveUsageState(from: data))
        #expect(state.resetCreditsAvailableCount == 2)
    }

    @Test("Handles zero, missing, and null reset credits")
    func unavailableResetCredits() throws {
        for json in [#"{}"#, #"{"rate_limit_reset_credits":null}"#] {
            let state = try #require(LimitStateReader.decodeLiveUsageState(from: Data(json.utf8)))
            #expect(state.resetCreditsAvailableCount == nil)
        }
        let data = Data(#"{"rate_limit_reset_credits":{"available_count":0}}"#.utf8)
        let state = try #require(LimitStateReader.decodeLiveUsageState(from: data))
        #expect(state.resetCreditsAvailableCount == 0)
    }

    @Test("Runtime signal reader bootstraps a bounded tail then reads only appended rows")
    func runtimeSignalReaderIsIncremental() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-menu-bar-runtime-signal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let databaseURL = codexHome.appendingPathComponent("logs_2.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let openedDatabase = try #require(database)
        defer { sqlite3_close(openedDatabase) }

        #expect(sqlite3_exec(
            openedDatabase,
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, ts_nanos INTEGER NOT NULL, feedback_log_body TEXT)",
            nil,
            nil,
            nil
        ) == SQLITE_OK)

        for id in 1...600 {
            try insertLog(
                into: openedDatabase,
                id: Int64(id),
                timestamp: Int64(id),
                body: id == 550 ? #"{"status":"completed"}"# : "unrelated"
            )
        }

        let reader = LimitStateReader(codexHome: codexHome)
        let initial = try #require(reader.readRuntimeSignalSnapshot())
        #expect(initial.completedAt == Date(timeIntervalSince1970: 550))
        #expect(reader.runtimeSignalRowsReadForLastRefresh == 500)

        try insertLog(
            into: openedDatabase,
            id: 601,
            timestamp: 601,
            body: #"{"status":"in_progress"}"#
        )

        let updated = try #require(reader.readRuntimeSignalSnapshot())
        #expect(updated.completedAt == Date(timeIntervalSince1970: 550))
        #expect(updated.runningAt == Date(timeIntervalSince1970: 601))
        #expect(reader.runtimeSignalRowsReadForLastRefresh == 1)
    }

    @Test("Treats a seven-day primary window as the weekly limit")
    func weeklyOnlyPrimaryWindow() throws {
        let data = Data(#"""
        {
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": 5,
              "limit_window_seconds": 604800,
              "reset_at": 1784695749
            },
            "secondary_window": null
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "metered_feature": "codex_bengalfox",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 0,
                  "limit_window_seconds": 604800
                },
                "secondary_window": null
              }
            }
          ]
        }
        """#.utf8)

        let state = try #require(LimitStateReader.decodeLiveUsageState(from: data))

        #expect(state.primary == nil)
        #expect(state.secondary?.usedPercent == 5)
        #expect(state.secondary?.windowMinutes == 10_080)
        #expect(state.additionalLimits.count == 1)
        #expect(state.additionalLimits.first?.name == "GPT-5.3-Codex-Spark weekly")
        #expect(state.additionalLimits.first?.bucket.usedPercent == 0)
    }

    @Test("Keeps shorter and longer windows in five-hour and weekly slots")
    func fiveHourAndWeeklyWindows() throws {
        let data = Data(#"""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 12,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 34,
              "limit_window_seconds": 604800
            }
          }
        }
        """#.utf8)

        let state = try #require(LimitStateReader.decodeLiveUsageState(from: data))

        #expect(state.primary?.usedPercent == 12)
        #expect(state.primary?.windowMinutes == 300)
        #expect(state.secondary?.usedPercent == 34)
        #expect(state.secondary?.windowMinutes == 10_080)
        #expect(state.additionalLimits.isEmpty)
    }
}

private func insertLog(
    into database: OpaquePointer,
    id: Int64,
    timestamp: Int64,
    body: String
) throws {
    let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(
        database,
        "INSERT INTO logs (id, ts, ts_nanos, feedback_log_body) VALUES (?, ?, 0, ?)",
        -1,
        &statement,
        nil
    ) == SQLITE_OK)
    let preparedStatement = try #require(statement)
    defer { sqlite3_finalize(preparedStatement) }

    sqlite3_bind_int64(preparedStatement, 1, id)
    sqlite3_bind_int64(preparedStatement, 2, timestamp)
    _ = body.withCString { pointer in
        sqlite3_bind_text(preparedStatement, 3, pointer, -1, sqliteTransient)
    }
    #expect(sqlite3_step(preparedStatement) == SQLITE_DONE)
}
