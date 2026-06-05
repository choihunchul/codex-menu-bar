import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Cursor activity reader tests")
struct CursorActivityReaderTests {
    @Test("Cursor activity snapshot detects active window files")
    func snapshotActiveWindow() {
        let snapshot = CursorActivitySnapshot(
            lastUserActivityDate: Date(),
            lastAgentActivityDate: nil
        )
        #expect(snapshot.isActive(activeWindowSeconds: 10, now: Date()))
    }
}
