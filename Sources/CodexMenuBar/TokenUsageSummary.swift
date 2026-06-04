import Foundation

private struct ModelCachePayload: Decodable {
    var models: [ModelCacheEntry]
}

private struct ModelCacheEntry: Decodable {
    var slug: String?
    var display_name: String?
    var context_window: Int?
}

struct TokenUsageSample {
    var timestamp: TimeInterval
    var threadID: String
    var totalTokens: Int
}

struct TokenUsageSummary {
    var latestDelta: Int?
    var latestTotal: Int?
    var latestObservedAt: Date?
    var fiveHourTotal: Int
    var todayTotal: Int
    var weekTotal: Int
    var buckets: [Int]
    var observedAt: Date

    static let empty = TokenUsageSummary(
        latestDelta: nil,
        latestTotal: nil,
        latestObservedAt: nil,
        fiveHourTotal: 0,
        todayTotal: 0,
        weekTotal: 0,
        buckets: Array(repeating: 0, count: 30),
        observedAt: Date()
    )

    static func build(
        samples: [TokenUsageSample],
        now: Date,
        calendar: Calendar,
        fiveHourBucketCount: Int
    ) -> TokenUsageSummary {
        let windowSeconds: TimeInterval = 5 * 60 * 60
        let windowStart = now.timeIntervalSince1970 - windowSeconds
        let bucketWidth = windowSeconds / Double(max(fiveHourBucketCount, 1))
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 1
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart

        var previousTotals: [String: Int] = [:]
        var buckets = Array(repeating: 0, count: max(fiveHourBucketCount, 1))
        var fiveHourTotal = 0
        var todayTotal = 0
        var weekTotal = 0
        var latestDelta: Int?
        var latestTotal: Int?
        var latestObservedAt: Date?

        for sample in samples.sorted(by: { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.threadID < rhs.threadID
        }) {
            defer {
                previousTotals[sample.threadID] = sample.totalTokens
            }

            let sampleDate = Date(timeIntervalSince1970: sample.timestamp)
            let inFiveHourWindow = sample.timestamp >= windowStart
            let inTodayWindow = sampleDate >= todayStart
            let inWeekWindow = sampleDate >= weekStart

            let previous = previousTotals[sample.threadID]
            let delta: Int
            if let previous {
                delta = max(0, sample.totalTokens - previous)
            } else if inFiveHourWindow || inTodayWindow || inWeekWindow {
                delta = sample.totalTokens
            } else {
                delta = 0
            }

            guard delta > 0 else {
                if inFiveHourWindow {
                    latestTotal = sample.totalTokens
                    latestObservedAt = Date(timeIntervalSince1970: sample.timestamp)
                }
                continue
            }

            if inFiveHourWindow {
                fiveHourTotal += delta
                let rawBucket = Int((sample.timestamp - windowStart) / bucketWidth)
                let index = min(max(rawBucket, 0), buckets.count - 1)
                buckets[index] += delta
                latestDelta = delta
            }

            if inTodayWindow {
                todayTotal += delta
            }
            if inWeekWindow {
                weekTotal += delta
            }
            latestTotal = sample.totalTokens
            latestObservedAt = sampleDate
        }

        return TokenUsageSummary(
            latestDelta: latestDelta,
            latestTotal: latestTotal,
            latestObservedAt: latestObservedAt,
            fiveHourTotal: fiveHourTotal,
            todayTotal: todayTotal,
            weekTotal: weekTotal,
            buckets: buckets,
            observedAt: now
        )
    }
}

func formatTokenCount(_ value: Int) -> String {
    let absolute = abs(value)
    if absolute >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000.0)
    }
    if absolute >= 10_000 {
        return "\(Int(round(Double(value) / 1_000.0)))k"
    }
    if absolute >= 1_000 {
        return String(format: "%.1fk", Double(value) / 1_000.0)
    }
    return "\(value)"
}

func parseModelName(from logLine: String) -> String? {
    let patterns = ["model=", "slug="]
    for pattern in patterns {
        guard let range = logLine.range(of: pattern) else {
            continue
        }
        var value = ""
        var index = range.upperBound
        while index < logLine.endIndex {
            let char = logLine[index]
            if char.isWhitespace || char == "}" || char == "," || char == "\"" {
                break
            }
            value.append(char)
            index = logLine.index(after: index)
        }
        if !value.isEmpty {
            return value
        }
    }
    return nil
}

func parseContextWindow(from logLine: String) -> Int? {
    let patterns = ["model_context_window=", "context_window="]
    for pattern in patterns {
        guard let range = logLine.range(of: pattern) else {
            continue
        }
        var value = ""
        var index = range.upperBound
        while index < logLine.endIndex {
            let char = logLine[index]
            if char.isWhitespace || char == "}" || char == "," || char == "\"" {
                break
            }
            value.append(char)
            index = logLine.index(after: index)
        }
        if let window = Int(value), window > 0 {
            return window
        }
    }
    return nil
}

func formatContextWindow(_ value: Int?) -> String? {
    guard let value else {
        return nil
    }
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000.0)
    }
    if value >= 1_000 {
        return String(format: "%.1fk", Double(value) / 1_000.0)
    }
    return "\(value)"
}

func contextWindow(forModelNamed modelName: String, cacheData: Data) -> Int? {
    guard let payload = try? JSONDecoder().decode(ModelCachePayload.self, from: cacheData) else {
        return nil
    }

    let normalized = modelName.lowercased()
    return payload.models.first(where: { entry in
        entry.slug?.lowercased() == normalized || entry.display_name?.lowercased() == normalized
    })?.context_window
}
