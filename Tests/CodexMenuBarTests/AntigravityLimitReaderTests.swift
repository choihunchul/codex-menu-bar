import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Antigravity quota reports")
struct AntigravityLimitReaderTests {
    @Test("Suspension prevents launching quota commands and cancels an active command")
    func sleepSuspension() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("quota-sleep-\(UUID().uuidString)")
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = bin.appendingPathComponent("agy")
        let marker = home.appendingPathComponent("started")
        let script = "#!/bin/sh\n/usr/bin/touch '\(marker.path)'\nexec /bin/sleep 30\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let reader = AntigravityLimitReader(home: home)
        reader.setSuspended(true)
        #expect(reader.readLatest() == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        reader.setSuspended(false)
        let started = Date()
        let task = Task.detached { reader.readLatest() != nil }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let didLaunch = FileManager.default.fileExists(atPath: marker.path)
        reader.setSuspended(true)
        #expect(didLaunch)
        #expect(await task.value == false)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("Parses official usage groups and reset dates without inferring quotas from activity")
    func usageReport() throws {
        let data = Data(#"""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
          {"name":"Gemini Models","buckets":[
            {"name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9,"reset_time":"2026-10-07T02:30:52Z"},
            {"name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-10-01T05:34:11.000Z"}
          ]},
          {"name":"Claude and GPT models","buckets":[
            {"name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.76},
            {"name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0}
          ]}
        ]}}}
        """#.utf8)
        let now = Date(timeIntervalSince1970: 100)
        let state = try #require(AntigravityLimitReader.decodeUsageReport(from: data, observedAt: now))
        #expect(state.limits.count == 4)
        #expect(abs(state.limits[0].bucket.remainingPercent - 90) < 0.001)
        #expect(state.limits[0].bucket.windowMinutes == 10_080)
        #expect(state.limits[1].bucket.windowMinutes == 300)
        #expect(state.limits[1].bucket.resetAt == ISO8601DateFormatter().date(from: "2026-10-01T05:34:11Z")?.timeIntervalSince1970)
        #expect(state.limits[3].bucket.remainingPercent == 0)
        #expect(state.observedAt == now)
    }

    @Test("Rejects unsuccessful commands and unmeasured, disabled, or invalid buckets")
    func noMeasuredQuota() {
        for json in [
            #"{"status":"ERROR","command":{"name":"usage","data":{"groups":[]}}}"#,
            #"{"status":"SUCCESS","command":{"name":"other","data":{"groups":[]}}}"#,
            #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"name":"missing"},{"name":"invalid","remaining_fraction":2},{"name":"disabled","remaining_fraction":1,"disabled":true}]}]}}}"#
        ] {
            #expect(AntigravityLimitReader.decodeUsageReport(from: Data(json.utf8)) == nil)
        }
    }
}
