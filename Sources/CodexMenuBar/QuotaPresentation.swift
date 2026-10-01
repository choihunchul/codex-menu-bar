import Foundation

func quotaDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

func quotaMoneyText(_ value: Double?) -> String {
    value.map { String(format: "$%.2f", $0) } ?? "-"
}

func cursorIncludedUsageText(_ state: CursorLimitState) -> String {
    "Included: \(quotaMoneyText(state.includedSpendUSD)) / \(quotaMoneyText(state.limitUSD)) · Bonus: \(quotaMoneyText(state.bonusSpendUSD))"
}

func quotaResetText(_ date: Date, now: Date = Date()) -> String {
    let days = Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: date)
    ).day ?? 0
    let remaining = days <= 0 ? "today" : "\(days)d left"
    return "\(quotaDateText(date)) (\(remaining))"
}

func codexLimitUsageText(_ tokens: Int, bucket: LimitBucket?, now: Date = Date()) -> String {
    let usage = formatTokenCount(tokens)
    guard let timestamp = bucket?.resetAt else { return usage }
    let reset = Date(timeIntervalSince1970: timestamp)
    return "\(usage) · resets \(quotaResetText(reset, now: now))"
}
