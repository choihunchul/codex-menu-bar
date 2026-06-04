import AppKit
import Foundation

struct StatusPopoverPresentation {
    var badge: String
    var title: String
    var body: String
    var contentSize: NSSize
}

func statusPopoverPresentation(status: String, detail: String) -> StatusPopoverPresentation? {
    switch CodexStatusKind(status: status) {
    case .waiting:
        return StatusPopoverPresentation(
            badge: "INPUT REQUIRED",
            title: "Codex is waiting for input",
            body: detail.isEmpty ? "Open the conversation and respond when you're ready." : detail,
            contentSize: NSSize(width: 360, height: 180)
        )
    case .awaitingApproval:
        return StatusPopoverPresentation(
            badge: "AWAITING APPROVAL",
            title: "Codex is awaiting approval",
            body: detail.isEmpty ? "Open the conversation and approve when you're ready." : detail,
            contentSize: NSSize(width: 360, height: 180)
        )
    case .message:
        return StatusPopoverPresentation(
            badge: "NEW MESSAGE",
            title: "Codex has a message",
            body: detail.isEmpty ? "There is a new message waiting." : detail,
            contentSize: NSSize(width: 360, height: 180)
        )
    default:
        return nil
    }
}
