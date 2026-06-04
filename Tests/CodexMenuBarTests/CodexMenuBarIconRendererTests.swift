import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Codex menu bar icon rendering")
struct CodexMenuBarIconRendererTests {
    @Test("Running status uses the running icon")
    func runningUsesRunningIcon() {
        #expect(codexMenuBarIconKind(status: "running", isRecentlyCompleted: false) == .running)
    }

    @Test("Completed status uses the complete icon")
    func completedUsesCompleteIcon() {
        #expect(codexMenuBarIconKind(status: "idle", isRecentlyCompleted: true) == .complete)
    }

    @Test("Approval status uses the waiting icon")
    func approvalUsesWaitingIcon() {
        #expect(codexMenuBarIconKind(status: "awaiting approval", isRecentlyCompleted: false) == .waiting)
    }

    @Test("Thinking status uses the running icon")
    func thinkingUsesRunningIcon() {
        #expect(codexMenuBarIconKind(status: "thinking", isRecentlyCompleted: false) == .running)
        #expect(codexMenuBarIconKind(status: "running_command", isRecentlyCompleted: false) == .running)
    }

    @Test("Completed status uses the complete icon directly")
    func completedUsesCompleteIconDirectly() {
        #expect(codexMenuBarIconKind(status: "completed", isRecentlyCompleted: false) == .complete)
        #expect(codexMenuBarIconKind(status: "complete", isRecentlyCompleted: false) == .complete)
    }

    @Test("Completion and attention states sparkle in the top right")
    func topRightSparkleStates() {
        #expect(codexMenuBarTopRightSparkleShouldBlink(status: "completed", isRecentlyCompleted: false))
        #expect(codexMenuBarTopRightSparkleShouldBlink(status: "approval_required", isRecentlyCompleted: false))
        #expect(codexMenuBarTopRightSparkleShouldBlink(status: "failed", isRecentlyCompleted: false))
        #expect(!codexMenuBarTopRightSparkleShouldBlink(status: "running", isRecentlyCompleted: false))
    }

    @Test("Completion sparkle sits in the upper right")
    func completionSparkleSitsInTheUpperRight() {
        let center = codexMenuBarTopRightSparkleCenter()

        #expect(center.x > 19)
        #expect(center.y < 7)
    }

    @Test("Running animation varies across frames")
    func runningAnimationVariesAcrossFrames() {
        #expect(codexMenuBarRunningFloatOffset(frameIndex: 0) != codexMenuBarRunningFloatOffset(frameIndex: 1))
        #expect(codexMenuBarBlinkOpacity(frameIndex: 0, phase: 0) != codexMenuBarBlinkOpacity(frameIndex: 1, phase: 0))
    }

    @Test("Running motion streaks move across frames")
    func runningMotionStreaksMoveAcrossFrames() {
        let first = codexMenuBarRunningMotionStreaks(frameIndex: 0)
        let second = codexMenuBarRunningMotionStreaks(frameIndex: 1)

        #expect(first.count == 3)
        #expect(first[0].x != second[0].x)
        #expect(first.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
    }

    @Test("Waiting animation varies across frames")
    func waitingAnimationVariesAcrossFrames() {
        #expect(codexMenuBarBlinkOpacity(frameIndex: 0, phase: 1) != codexMenuBarBlinkOpacity(frameIndex: 1, phase: 1))
    }

    @Test("Complete animation varies across frames")
    func completeAnimationVariesAcrossFrames() {
        #expect(codexMenuBarBlinkOpacity(frameIndex: 0, phase: 2) != codexMenuBarBlinkOpacity(frameIndex: 1, phase: 2))
    }

    @Test("agActive or agStatus triggers colored rendering and sets isTemplate to false")
    func agActiveOrStatusSetsTemplateMode() {
        let renderer = CodexMenuBarIconRenderer()
        
        // Default has no AGY active
        let imageNormal = renderer.image(
            status: "idle",
            isRecentlyCompleted: false,
            frameIndex: 0,
            fiveHourUsagePercent: nil,
            weeklyUsagePercent: nil,
            agActive: false
        )
        #expect(imageNormal.isTemplate == true)

        // agActive true should set isTemplate to false
        let imageActive = renderer.image(
            status: "idle",
            isRecentlyCompleted: false,
            frameIndex: 0,
            fiveHourUsagePercent: nil,
            weeklyUsagePercent: nil,
            agActive: true
        )
        #expect(imageActive.isTemplate == false)

        // agStatus awaiting approval should set isTemplate to false
        let imageApproval = renderer.image(
            status: "idle",
            isRecentlyCompleted: false,
            frameIndex: 0,
            fiveHourUsagePercent: nil,
            weeklyUsagePercent: nil,
            agActive: false,
            agStatus: "awaiting approval"
        )
        #expect(imageApproval.isTemplate == false)
    }
}
