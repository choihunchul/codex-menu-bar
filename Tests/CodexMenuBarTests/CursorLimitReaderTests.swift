import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Cursor limit reader tests")
struct CursorLimitReaderTests {
    @Test("Separates included usage from bonus usage and on-demand charges")
    func usageSummary() throws {
        let data = Data(#"""
        {"billingCycleEnd":"2026-10-07T11:09:17.000Z","individualUsage":{
          "plan":{"used":2000,"limit":2000,"apiPercentUsed":100,"totalPercentUsed":100,
            "breakdown":{"included":2000,"bonus":47508,"total":49508}},
          "onDemand":{"used":0}
        }}
        """#.utf8)
        let state = try #require(CursorLimitReader.decodeUsageSummary(from: data))
        #expect(state.includedSpendUSD == 20)
        #expect(state.limitUSD == 20)
        #expect(state.bonusSpendUSD == 475.08)
        #expect(state.onDemandSpendUSD == 0)
        #expect(state.totalPercentUsed == 100)
        #expect(state.billingCycleEnd == ISO8601DateFormatter().date(from: "2026-10-07T11:09:17Z"))
        #expect(cursorIncludedUsageText(state) == "Included: $20.00 / $20.00 · Bonus: $475.08")
        #expect(!cursorIncludedUsageText(state).contains("$495.08"))
    }

    @Test("Preserves fractional percentages and unknown values")
    func fractionalAndUnknownUsage() throws {
        let state = try #require(CursorLimitReader.decodeUsageSummary(from: Data(
            #"{"individualUsage":{"plan":{"apiPercentUsed":0.75,"used":10,"limit":2000}}}"#.utf8)))
        #expect(state.apiPercentUsed == 0.75)
        #expect(state.totalPercentUsed == 0.5)
        #expect(state.bonusSpendUSD == nil)
        #expect(state.billingCycleEnd == nil)
        #expect(CursorLimitReader.decodeUsageSummary(from: Data(#"{}"#.utf8)) == nil)
        let unknown = try #require(CursorLimitReader.decodeUsageSummary(from: Data(
            #"{"individualUsage":{"plan":{}}}"#.utf8)))
        #expect(unknown.totalPercentUsed == nil)
        #expect(unknown.apiPercentUsed == nil)
    }

    @Test("JWT User ID parsing extracts the correct sub claim")
    func parseUserId() {
        let reader = CursorLimitReader(cursorHome: URL(fileURLWithPath: "/tmp"))
        let token = "header.eyJzdWIiOiJnb29nbGUtb2F1dGgyfHVzZXJfMTIzIiwiZXhwIjoyMDAwMDAwMDAwfQ.signature"
        let userId = reader.parseUserId(from: token)
        #expect(userId == "google-oauth2|user_123")
    }
}
