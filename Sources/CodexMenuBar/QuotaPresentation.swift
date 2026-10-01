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
