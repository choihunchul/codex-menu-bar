import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Token usage summaries")
struct TokenUsageSummaryTests {
    @Test("Aggregates today and this week from local calendar boundaries")
    func aggregatesTodayAndWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let now = Date(timeIntervalSince1970: 1_715_866_800)

        let samples: [TokenUsageSample] = [
            .init(timestamp: now.timeIntervalSince1970 - 3600, threadID: "a", totalTokens: 100),
            .init(timestamp: now.timeIntervalSince1970 - 1800, threadID: "a", totalTokens: 140),
            .init(timestamp: now.timeIntervalSince1970 - 2 * 24 * 3600, threadID: "b", totalTokens: 50),
            .init(timestamp: now.timeIntervalSince1970 - 6 * 24 * 3600, threadID: "c", totalTokens: 70)
        ]

        let summary = TokenUsageSummary.build(
            samples: samples,
            now: now,
            calendar: calendar,
            fiveHourBucketCount: 30
        )

        #expect(summary.todayTotal == 140)
        #expect(summary.weekTotal == 190)
        #expect(summary.fiveHourTotal == 140)
    }

    @Test("This week starts on Monday for token summaries")
    func weekStartsOnMonday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 17,
            hour: 12
        ))!
        let saturday = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 16,
            hour: 12
        ))!

        let summary = TokenUsageSummary.build(
            samples: [
                .init(timestamp: saturday.timeIntervalSince1970, threadID: "sat", totalTokens: 579_235),
                .init(timestamp: now.timeIntervalSince1970, threadID: "sun", totalTokens: 1_197_372)
            ],
            now: now,
            calendar: calendar,
            fiveHourBucketCount: 30
        )

        #expect(summary.todayTotal == 1_197_372)
        #expect(summary.weekTotal == 1_776_607)
    }

    @Test("Parses the model name from a Codex log line")
    func parsesModelName() {
        let line = #"session_loop{thread_id=abc}: event.name="codex.user_prompt" model=gpt-5.5 slug=gpt-5.5"#

        #expect(parseModelName(from: line) == "gpt-5.5")
    }

    @Test("Parses the model context window from a log line")
    func parsesContextWindow() {
        let line = #"event.name="token_count" info.model_context_window=258400 model_context_window=258400"#

        #expect(parseContextWindow(from: line) == 258400)
    }

    @Test("Reads the context window from model cache json")
    func readsContextWindowFromCache() {
        let json = """
        {
          "models": [
            { "slug": "gpt-5.4-mini", "display_name": "GPT-5.4-Mini", "context_window": 272000 },
            { "slug": "gpt-5.5", "display_name": "GPT-5.5", "context_window": 256000 }
          ]
        }
        """

        #expect(contextWindow(forModelNamed: "gpt-5.4-mini", cacheData: json.data(using: .utf8)!) == 272000)
        #expect(contextWindow(forModelNamed: "GPT-5.4-Mini", cacheData: json.data(using: .utf8)!) == 272000)
    }
}
