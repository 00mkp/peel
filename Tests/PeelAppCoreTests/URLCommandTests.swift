import ConvertKit
import Foundation
import Testing
@testable import PeelAppCore

@Suite struct URLCommandTests {
    @Test func parses() {
        #expect(PeelURLCommand(url: URL(string: "peel://login/on")!) == .login(true))
        #expect(PeelURLCommand(url: URL(string: "peel://login/off")!) == .login(false))
        #expect(PeelURLCommand(url: URL(string: "peel://panel")!) == .panel)
        #expect(PeelURLCommand(url: URL(string: "peel://nope")!) == nil)
        #expect(PeelURLCommand(url: URL(fileURLWithPath: "/tmp/a.pdf")) == nil)
    }

    @MainActor @Test func stateForTheCLI() {
        let item = FakeLoginItem()
        let model = AppModel(loginItem: item)
        #expect(model.stateValues == ["version": PeelVersion.current, "login": "off"])
        model.setLaunchAtLogin(true)
        #expect(model.stateValues["login"] == "on")
        item.enabled = false
        item.approvalNeeded = true
        model.refreshLoginItem()
        #expect(model.stateValues["login"] == "needs-approval")
    }
}
