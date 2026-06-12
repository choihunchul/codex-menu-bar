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
        
        // Shallow scan logs directory to find session subdirectories
        guard let contents = try? fileManager.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        let now = Date()
        // Filter to directories modified in the last 1 hour
        var dirsToScan = contents
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = values.contentModificationDate else {
                    return nil
                }
                return (url, modDate)
            }
            .filter { _, modDate in
                now.timeIntervalSince(modDate) <= 3600.0
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        
        // Fallback to the single most recently modified directory if none modified in the last hour
        if dirsToScan.isEmpty {
            if let latestDir = contents
                .compactMap({ url -> (URL, Date)? in
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                          let modDate = values.contentModificationDate else {
                        return nil
                      }
                    return (url, modDate)
                })
                .sorted(by: { $0.1 > $1.1 })
                .first?.0 {
                dirsToScan = [latestDir]
            }
        }
        
        var latestDate: Date? = nil
        for dir in dirsToScan {
            // Shallow scan the session directory to find window subdirectories
            guard let windowContents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            
            for windowURL in windowContents {
                guard windowURL.lastPathComponent.hasPrefix("window") else {
                    continue
                }
                
                let agentExecURL = windowURL.appendingPathComponent("exthost/anysphere.cursor-agent-exec")
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: agentExecURL.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                
                // Shallow scan the agent exec directory
                guard let files = try? fileManager.contentsOfDirectory(
                    at: agentExecURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                
                for fileURL in files {
                    if fileURL.lastPathComponent.hasPrefix("Cursor Agent Exec") {
                        if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                           let modDate = values.contentModificationDate {
                            if latestDate == nil || modDate > latestDate! {
                                latestDate = modDate
                            }
                        }
                    }
                }
            }
        }
        
        return latestDate
    }
}
