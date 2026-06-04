import Foundation
import Testing
@testable import CodexMenuBar

@Suite("Codex menu bar restart")
struct CodexMenuBarRestartTests {
    @Test("Executable URL prefers the bundle executable")
    func executableURLPrefersBundleExecutable() {
        let bundleURL = URL(fileURLWithPath: "/tmp/CodexMenuBar")

        let result = codexMenuBarExecutableURL(
            bundleExecutableURL: bundleURL,
            processArguments: ["/tmp/other"]
        )

        #expect(result == bundleURL)
    }

    @Test("Executable URL falls back to the process argument")
    func executableURLFallsBackToProcessArgument() {
        let result = codexMenuBarExecutableURL(
            bundleExecutableURL: nil,
            processArguments: ["~/bin/CodexMenuBar"]
        )

        #expect(result?.path.hasSuffix("/bin/CodexMenuBar") == true)
    }

    @Test("Relaunch shell command waits before executing the binary")
    func relaunchShellCommandWaitsBeforeExecutingTheBinary() {
        let result = codexMenuBarRelaunchShellCommand(
            executableURL: URL(fileURLWithPath: "/tmp/Codex Menu'Bar"),
            delaySeconds: 0.5
        )

        #expect(result == #"sleep 0.50; exec '/tmp/Codex Menu'\''Bar'"#)
    }
}
