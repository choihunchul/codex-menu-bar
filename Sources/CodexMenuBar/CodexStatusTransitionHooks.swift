import Foundation

struct CodexRuntimeSignalSnapshot {
    var runningAt: Date?
    var approvalAt: Date?
    var completedAt: Date?
    var waitingAt: Date?
    var messageAt: Date?
    var errorAt: Date?
}

func codexNormalizedStatus(_ status: String) -> String {
    let normalized = status
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")

    if normalized.contains("approval") {
        return "awaiting approval"
    }
    if normalized.contains("complete") || normalized.contains("done") {
        return "completed"
    }
    if normalized.contains("thinking")
        || normalized.contains("running_command")
        || normalized.contains("running command")
        || normalized.contains("working")
        || normalized == "running"
    {
        return "running"
    }
    if normalized.contains("waiting") {
        return "waiting"
    }
    if normalized.contains("message") {
        return "message"
    }
    if normalized.contains("fail") {
        return "error"
    }
    if normalized.contains("error") {
        return "error"
    }
    if normalized == "idle" {
        return "idle"
    }

    return normalized.replacingOccurrences(of: "_", with: " ")
}

func codexResolvedRuntimeStatus(from snapshot: CodexRuntimeSignalSnapshot) -> CodexStatusKind? {
    let candidates: [(CodexStatusKind, Date)] = [
        snapshot.runningAt.map { (.running, $0) },
        snapshot.approvalAt.map { (.awaitingApproval, $0) },
        snapshot.completedAt.map { (.completed, $0) },
        snapshot.waitingAt.map { (.waiting, $0) },
        snapshot.messageAt.map { (.message, $0) },
        snapshot.errorAt.map { (.error, $0) }
    ].compactMap { $0 }

    return candidates.max(by: { $0.1 < $1.1 })?.0
}

enum CodexStatusKind: String {
    case running
    case idle
    case waiting
    case message
    case error
    case awaitingApproval = "awaiting approval"
    case completed

    init(status: String) {
        self = CodexStatusKind(rawValue: codexNormalizedStatus(status)) ?? .idle
    }
}

enum CodexStatusHookName: String, CaseIterable {
    case onRunning
    case onCompleted
    case onWaiting
    case onMessage
    case onApprovalNeeded
    case onError
}

final class CodexStatusTransitionHooks {
    private let completedCooldown: TimeInterval
    private var lastStatus: CodexStatusKind?
    private var suppressAutoActiveUntil: Date?

    init(completedCooldown: TimeInterval = 8) {
        self.completedCooldown = max(0, completedCooldown)
    }

    func shouldSuppressAutoActive(at now: Date) -> Bool {
        guard let suppressAutoActiveUntil else {
            return false
        }
        return now < suppressAutoActiveUntil
    }

    func recordResolvedStatus(_ status: String, at now: Date) -> CodexStatusHookName? {
        let current = CodexStatusKind(status: status)
        defer {
            lastStatus = current
        }

        guard lastStatus != current else {
            return nil
        }

        if lastStatus == .running, current == .idle || current == .completed {
            suppressAutoActiveUntil = now.addingTimeInterval(completedCooldown)
        }

        switch current {
        case .running:
            return .onRunning
        case .idle:
            return .onCompleted
        case .waiting:
            return .onWaiting
        case .message:
            return .onMessage
        case .error:
            return .onError
        case .awaitingApproval:
            return .onApprovalNeeded
        case .completed:
            return .onCompleted
        }
    }
}
