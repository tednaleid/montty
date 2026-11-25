// ABOUTME: Verifies what the read form of a setting prints, given the info reply
// ABOUTME: a running montty sends back over the control socket.

import Foundation
import Testing

@Suite struct SettingReadoutTests {
    /// The info reply as the CLI receives it: encoded by the real wire encoder
    /// and parsed back to a plain dictionary.
    private func reply(
        tabName: String = "montty/",
        scopes: ControlInfo.Scopes = ControlInfo.Scopes(surface: nil, tab: nil, repo: nil),
        effective: PaneTint? = nil,
        status: String? = nil,
        resumeCommand: String? = nil,
        tabMinimap: String? = nil
    ) throws -> [String: Any] {
        let info = ControlInfo(
            surfaceID: "M1", leafID: "L1", tabID: "T1",
            tabName: tabName, tabNameIsOverride: false,
            scopes: scopes, effective: effective.map(TintPayload.init),
            git: nil, status: status, resumeCommand: resumeCommand,
            settings: ControlInfo.Settings(
                surfaceTintStrength: .init(app: 0.2, effective: 0.2),
                tabTintStrength: .init(app: 0.12, effective: 0.12),
                minimap: .init(tab: tabMinimap, app: "split", effective: tabMinimap ?? "split"),
                minimapHeight: .init(app: 90, effective: 90)
            )
        )
        let data = try ControlResponse.info(info).encoded()
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func text(
        _ setting: SettingName, _ scope: SettingScope, _ info: [String: Any]
    ) -> String? {
        SettingReadout.text(SettingRead(setting: setting, scope: scope), info: info)
    }

    @Test func aColorSetAtTheScopePrintsItsStops() throws {
        let tint = PaneTint(stops: [.named(.blue), .named(.green)])
        let info = try reply(
            scopes: ControlInfo.Scopes(surface: nil, tab: TintPayload(tint), repo: nil),
            effective: tint
        )
        #expect(text(.color, .tab, info) == "blue,green")
    }

    @Test func aColorNotSetAtTheScopeSaysSoAndGivesTheEffectiveColor() throws {
        let info = try reply(effective: PaneTint(stops: [.named(.cyan)]))
        #expect(text(.color, .surface, info) == "not set (effective cyan)")
    }

    @Test func nameIsTheNameTheTabShows() throws {
        #expect(text(.name, .tab, try reply(tabName: "MR 123")) == "MR 123")
    }

    @Test func statusIsTheStateOrNothing() throws {
        #expect(text(.status, .surface, try reply(status: "waiting")) == "waiting")
        #expect(text(.status, .surface, try reply()) == nil)
    }

    @Test func resumeCommandIsTheCommandOrNothing() throws {
        #expect(text(.resumeCommand, .surface, try reply(resumeCommand: "nvim -S")) == "nvim -S")
        #expect(text(.resumeCommand, .surface, try reply()) == nil)
    }

    @Test func aStrengthPrintsItsValueAtTheAppScope() throws {
        #expect(text(.surfaceTintStrength, .app, try reply()) == "0.2")
        #expect(text(.tabTintStrength, .app, try reply()) == "0.12")
    }

    @Test func aWholeNumberPrintsWithoutADecimalPoint() throws {
        #expect(text(.minimapHeight, .app, try reply()) == "90")
    }

    @Test func aScopeWithItsOwnValuePrintsIt() throws {
        #expect(text(.minimap, .tab, try reply(tabMinimap: "never")) == "never")
    }

    @Test func aScopeWithoutItsOwnValuePrintsTheNextWiderOne() throws {
        #expect(text(.minimap, .tab, try reply()) == "split")
    }

    @Test func theAppScopeIgnoresANarrowerOverride() throws {
        #expect(text(.minimap, .app, try reply(tabMinimap: "never")) == "split")
    }
}
