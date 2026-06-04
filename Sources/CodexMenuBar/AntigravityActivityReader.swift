import Foundation

/// Antigravity 활동 상태 스냅샷
struct AntigravityActivitySnapshot {
    /// conversations 디렉토리에서 가장 최근에 변경된 .pb 파일의 수정 시각
    var lastActivityDate: Date?
    /// 최근 `activeWindowSeconds` 이내에 변경된 .pb 파일 수 (=활성 대화 수)
    var activeConversationCount: Int
    /// conversations 디렉토리의 전체 .pb 파일 수
    var totalConversationCount: Int

    static let empty = AntigravityActivitySnapshot(
        lastActivityDate: nil,
        activeConversationCount: 0,
        totalConversationCount: 0
    )

    /// activeWindowSeconds 이내에 활동이 있으면 true
    func isActive(activeWindowSeconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastActivityDate else { return false }
        return now.timeIntervalSince(lastActivityDate) <= activeWindowSeconds
    }
}

/// ~/.gemini/antigravity/conversations/*.pb 파일의 수정 시간을 통해
/// Antigravity 활동을 감지하는 리더.
///
/// Antigravity는 SQLite 기반 로그를 남기지 않으므로 토큰 카운팅은
/// 불가하며, 파일 시스템 타임스탬프로만 활동 여부를 판단합니다.
final class AntigravityActivityReader {
    private let conversationsURL: URL
    private let fileManager: FileManager

    init(
        antigravityHome: URL,
        fileManager: FileManager = .default
    ) {
        self.conversationsURL = antigravityHome.appendingPathComponent("conversations")
        self.fileManager = fileManager
    }

    /// conversations 디렉토리를 스캔하여 활동 스냅샷을 반환합니다.
    /// - Parameter activeWindowSeconds: 이 시간 이내 변경된 파일을 "활성"으로 간주
    func readSnapshot(activeWindowSeconds: TimeInterval = 60, now: Date = Date()) -> AntigravityActivitySnapshot {
        guard fileManager.fileExists(atPath: conversationsURL.path) else {
            return .empty
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: conversationsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        let pbFiles = contents.filter { $0.pathExtension == "pb" }
        let totalCount = pbFiles.count

        var latestDate: Date?
        var activeCount = 0

        for file in pbFiles {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate else {
                continue
            }

            if latestDate == nil || modDate > latestDate! {
                latestDate = modDate
            }

            if now.timeIntervalSince(modDate) <= activeWindowSeconds {
                activeCount += 1
            }
        }

        return AntigravityActivitySnapshot(
            lastActivityDate: latestDate,
            activeConversationCount: activeCount,
            totalConversationCount: totalCount
        )
    }

    /// conversations 디렉토리의 파일 중 최근에 수정된 파일의 날짜만 빠르게 반환합니다.
    /// 주기적인 폴링(activity watch)에 사용합니다.
    func latestActivityDate() -> Date? {
        guard fileManager.fileExists(atPath: conversationsURL.path),
              let contents = try? fileManager.contentsOfDirectory(
                at: conversationsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        return contents
            .filter { $0.pathExtension == "pb" }
            .compactMap { file -> Date? in
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                return values?.contentModificationDate
            }
            .max()
    }
}
