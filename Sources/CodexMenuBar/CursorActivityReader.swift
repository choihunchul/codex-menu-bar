import Foundation

struct CursorActivitySnapshot: Sendable {
    var lastUserActivityDate: Date?
    var lastAgentActivityDate: Date?
    
    static let empty = CursorActivitySnapshot(
        lastUserActivityDate: nil,
        lastAgentActivityDate: nil
    )
    
    func isActive(activeWindowSeconds: TimeInterval, now: Date = Date()) -> Bool {
        if let lastAgentActivityDate, now.timeIntervalSince(lastAgentActivityDate) <= activeWindowSeconds {
            return true
        }
        if let lastUserActivityDate, now.timeIntervalSince(lastUserActivityDate) <= activeWindowSeconds {
            return true
        }
        return false
    }
}

final class CursorActivityReader: @unchecked Sendable {
    private let cursorHome: URL
    private let globalStorageWAL: URL
    private let logsURL: URL
    private let fileManager: FileManager

    init(cursorHome: URL, fileManager: FileManager = .default) {
        self.cursorHome = cursorHome
        self.globalStorageWAL = cursorHome.appendingPathComponent("User/globalStorage/state.vscdb-wal")
        self.logsURL = cursorHome.appendingPathComponent("logs")
        self.fileManager = fileManager
    }
    
    func readSnapshot(activeWindowSeconds: TimeInterval = 60, now: Date = Date()) -> CursorActivitySnapshot {
        let lastUserDate = fileModificationDate(globalStorageWAL)
        let lastAgentDate = findLatestAgentActivityDate()
        
        return CursorActivitySnapshot(
            lastUserActivityDate: lastUserDate,
            lastAgentActivityDate: lastAgentDate
        )
    }
    
    private func fileModificationDate(_ url: URL) -> Date? {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
    
    private func findLatestAgentActivityDate() -> Date? {
        guard fileManager.fileExists(atPath: logsURL.path) else { return nil }
        guard let enumerator = fileManager.enumerator(
            at: logsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        var latestDate: Date? = nil
        for case let fileURL as URL in enumerator {
            if fileURL.path.contains("anysphere.cursor-agent-exec"),
               fileURL.lastPathComponent.hasPrefix("Cursor Agent Exec") {
                if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modDate = values.contentModificationDate {
                    if latestDate == nil || modDate > latestDate! {
                        latestDate = modDate
                    }
                }
            }
        }
        return latestDate
    }
}
