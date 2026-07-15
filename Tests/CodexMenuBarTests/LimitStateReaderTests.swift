import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Codex limit reader tests")
struct LimitStateReaderTests {
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
