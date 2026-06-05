import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Cursor limit reader tests")
struct CursorLimitReaderTests {
    @Test("JWT User ID parsing extracts the correct sub claim")
    func parseUserId() {
        let reader = CursorLimitReader(cursorHome: URL(fileURLWithPath: "/tmp"))
        let token = "header.eyJzdWIiOiJnb29nbGUtb2F1dGgyfHVzZXJfMTIzIiwiZXhwIjoyMDAwMDAwMDAwfQ.signature"
        let userId = reader.parseUserId(from: token)
        #expect(userId == "google-oauth2|user_123")
    }
}
