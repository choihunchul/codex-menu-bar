import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Status popover presentation")
struct StatusPopoverPresentationTests {
    @Test("Waiting status shows the emphasized popover")
    func waitingShowsEmphasizedPopover() {
        let presentation = statusPopoverPresentation(status: "waiting", detail: "Please respond")

        #expect(presentation != nil)
        #expect(presentation?.badge == "INPUT REQUIRED")
        #expect(presentation?.title == "Codex is waiting for input")
        #expect(presentation?.contentSize.width == 360)
        #expect(presentation?.contentSize.height == 180)
    }

    @Test("Awaiting approval status shows the emphasized popover")
    func awaitingApprovalShowsEmphasizedPopover() {
        let presentation = statusPopoverPresentation(status: "awaiting approval", detail: "Please approve this change")

        #expect(presentation != nil)
        #expect(presentation?.badge == "AWAITING APPROVAL")
        #expect(presentation?.title == "Codex is awaiting approval")
        #expect(presentation?.contentSize.width == 360)
        #expect(presentation?.contentSize.height == 180)
    }

    @Test("Approval required status shows the emphasized popover")
    func approvalRequiredShowsEmphasizedPopover() {
        let presentation = statusPopoverPresentation(status: "approval_required", detail: "Please approve this change")

        #expect(presentation != nil)
        #expect(presentation?.badge == "AWAITING APPROVAL")
        #expect(presentation?.title == "Codex is awaiting approval")
    }

    @Test("Idle status does not show the popover")
    func idleDoesNotShowPopover() {
        #expect(statusPopoverPresentation(status: "idle", detail: "Ready") == nil)
    }
}
