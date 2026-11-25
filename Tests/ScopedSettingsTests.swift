// ABOUTME: Verifies settings held at more than one scope: how a strength, a minimap
// ABOUTME: height, and a name resolve, are set and reset, and survive a relaunch.

import Foundation
import Testing

@Suite struct SettingOverridesTests {
    @Test func aStrengthResolvesFromTheNarrowestScopeThatHasOne() {
        let app = AppSettings(surfaceTintStrength: 0.1)
        let repo = SettingOverrides(surfaceTintStrength: 0.2)
        let tab = SettingOverrides(surfaceTintStrength: 0.3)
        let surface = SettingOverrides(surfaceTintStrength: 0.4)
        let none = SettingOverrides()
        let setting = StrengthSetting.surfaceTint

        #expect(setting.resolve(surface: surface, tab: tab, repo: repo, app: app) == 0.4)
        #expect(setting.resolve(surface: nil, tab: tab, repo: repo, app: app) == 0.3)
        #expect(setting.resolve(surface: none, tab: none, repo: repo, app: app) == 0.2)
        #expect(setting.resolve(surface: nil, tab: none, repo: nil, app: app) == 0.1)
    }

    @Test func eachStrengthResolvesOnItsOwn() {
        let app = AppSettings(surfaceTintStrength: 0.1, tabTintStrength: 0.05)
        let tab = SettingOverrides(tabTintStrength: 0.25)

        #expect(StrengthSetting.surfaceTint.resolve(surface: nil, tab: tab, repo: nil, app: app) == 0.1)
        #expect(StrengthSetting.tabTint.resolve(surface: nil, tab: tab, repo: nil, app: app) == 0.25)
    }

    @Test func overridesRoundTripThroughJSON() throws {
        let overrides = SettingOverrides(surfaceTintStrength: 0.3, tabTintStrength: nil)
        let data = try JSONEncoder().encode(overrides)
        #expect(try JSONDecoder().decode(SettingOverrides.self, from: data) == overrides)
    }

    @Test func aValueOutsideItsRangeOrOfTheWrongTypeIsDropped() throws {
        let json = #"{"surfaceTintStrength":9,"tabTintStrength":"strong"}"#
        let decoded = try JSONDecoder().decode(SettingOverrides.self, from: Data(json.utf8))
        #expect(decoded == SettingOverrides())
        #expect(decoded.isEmpty)
    }
}

@Suite struct ScopedSettingsServiceTests {
    private let surfaceID = UUID()
    private let repoIdentity = TabColor.repoIdentity(for: GitInfo(
        repoName: "montty", branchName: "main", worktreeName: nil, repoPath: "/Users/ted/montty"
    ))

    private func ref(directory: String? = "/Users/ted/montty") -> SurfaceRef {
        SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: UUID(),
            tabID: UUID(), directory: directory
        )
    }

    private func state() -> ControlState {
        ControlState(
            tabName: "", displayName: "montty/", surfaceColorOverrides: [:],
            tabColorOverride: nil, repoColorOverrides: [:],
            activityStates: [:], activityWaitingSince: [:],
            activityWaitingFromControl: [:], surfaceResumeCommands: [:]
        )
    }

    private let git: (String) -> GitInfo? = { _ in
        GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
    }

    @discardableResult
    private func apply(
        _ command: ControlCommand, to subject: inout ControlState, directory: String? = "/Users/ted/montty"
    ) -> ControlResult {
        ControlService.apply(command, target: ref(directory: directory), to: &subject, gitInfoProvider: git)
    }

    private func info(_ subject: ControlState) -> ControlInfo? {
        var subject = subject
        guard case .read(let info) = apply(.info, to: &subject) else { return nil }
        return info
    }

    @Test func aStrengthIsSetAtTheScopeNamed() {
        var subject = state()
        apply(.setStrength(.surfaceTint, scope: .surface, value: 0.4), to: &subject)
        apply(.setStrength(.surfaceTint, scope: .tab, value: 0.3), to: &subject)
        apply(.setStrength(.surfaceTint, scope: .repo, value: 0.2), to: &subject)
        apply(.setStrength(.surfaceTint, scope: .app, value: 0.1), to: &subject)

        #expect(subject.surfaceSettings[surfaceID]?.surfaceTintStrength == 0.4)
        #expect(subject.tabSettings.surfaceTintStrength == 0.3)
        #expect(subject.shared.repos[repoIdentity]?.surfaceTintStrength == 0.2)
        #expect(subject.shared.app.surfaceTintStrength == 0.1)
        #expect(subject.shared.app.tabTintStrength == TabTintStrength.default)
    }

    @Test func resettingAStrengthRemovesTheOverrideAndLeavesNothingBehind() {
        var subject = state()
        apply(.setStrength(.tabTint, scope: .surface, value: 0.2), to: &subject)
        apply(.setStrength(.tabTint, scope: .repo, value: 0.2), to: &subject)
        apply(.setStrength(.tabTint, scope: .tab, value: 0.2), to: &subject)

        apply(.setStrength(.tabTint, scope: .surface, value: nil), to: &subject)
        apply(.setStrength(.tabTint, scope: .repo, value: nil), to: &subject)
        apply(.setStrength(.tabTint, scope: .tab, value: nil), to: &subject)

        #expect(subject.surfaceSettings.isEmpty)
        #expect(subject.shared.repos.isEmpty)
        #expect(subject.tabSettings.isEmpty)
    }

    @Test func resettingAStrengthAtTheAppScopeReturnsItToTheDefault() {
        var subject = state()
        apply(.setStrength(.surfaceTint, scope: .app, value: 0.4), to: &subject)
        apply(.setStrength(.surfaceTint, scope: .app, value: nil), to: &subject)
        #expect(subject.shared.app.surfaceTintStrength == SurfaceTintStrength.default)
    }

    @Test func aRepoStrengthOutsideARepoIsRejected() {
        var subject = state()
        let result = ControlService.apply(
            .setStrength(.surfaceTint, scope: .repo, value: 0.2),
            target: ref(directory: nil), to: &subject, gitInfoProvider: { _ in nil }
        )
        #expect(result == .rejected(.notInRepo))
    }

    @Test func infoReportsAStrengthAtEachScopeAndWhatTheSurfaceResolvesTo() {
        var subject = state()
        apply(.setStrength(.surfaceTint, scope: .tab, value: 0.3), to: &subject)
        apply(.setStrength(.surfaceTint, scope: .repo, value: 0.2), to: &subject)

        #expect(info(subject)?.settings.surfaceTintStrength == .init(
            tab: 0.3, repo: 0.2, app: SurfaceTintStrength.default, effective: 0.3
        ))

        apply(.setStrength(.surfaceTint, scope: .surface, value: 0.4), to: &subject)
        #expect(info(subject)?.settings.surfaceTintStrength == .init(
            surface: 0.4, tab: 0.3, repo: 0.2, app: SurfaceTintStrength.default, effective: 0.4
        ))
    }

    @Test func theMinimapHeightIsSetAndResetAtTheTabAndAppScopes() {
        var subject = state()
        apply(.setMinimapHeight(scope: .tab, value: 60), to: &subject)
        apply(.setMinimapHeight(scope: .app, value: 120), to: &subject)
        #expect(subject.tabMinimapHeight == 60)
        #expect(subject.shared.app.minimapHeight == 120)
        #expect(info(subject)?.settings.minimapHeight == .init(tab: 60, app: 120, effective: 60))

        apply(.setMinimapHeight(scope: .tab, value: nil), to: &subject)
        apply(.setMinimapHeight(scope: .app, value: nil), to: &subject)
        #expect(subject.tabMinimapHeight == nil)
        #expect(subject.shared.app.minimapHeight == MinimapHeight.default)
    }

    @Test func aSurfaceNameIsSetAndReset() {
        var subject = state()
        apply(.setSurfaceName("logs"), to: &subject)
        #expect(subject.surfaceNames[surfaceID] == "logs")
        #expect(info(subject)?.surfaceName == "logs")

        apply(.setSurfaceName(nil), to: &subject)
        #expect(subject.surfaceNames.isEmpty)
        #expect(info(subject)?.surfaceName == nil)
    }

    @Test func theTabNameInInfoIsNotTheSurfaceName() {
        var subject = state()
        subject.tabName = "MR 123"
        apply(.setSurfaceName("logs"), to: &subject)
        #expect(info(subject)?.tabName == "MR 123")
    }
}

@Suite struct TabScopedSettingsTests {
    private let git: (String) -> GitInfo? = { path in
        GitInfo(repoName: "repo", branchName: "main", worktreeName: nil, repoPath: path)
    }

    /// A tab with two surfaces, the first focused, and their surface ids in
    /// tree order.
    private func splitTab() -> (Tab, [UUID]) {
        let first = UUID()
        let tab = Tab(surfaceID: first)
        let second = UUID()
        let leaves = SplitTree.allLeaves(node: tab.splitRoot)
        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot, leafID: leaves[0].id, direction: .right,
            newLeafID: UUID(), newSurfaceID: second
        )
        tab.focusedLeafID = leaves[0].id
        return (tab, [first, second])
    }

    private func focus(_ surfaceID: UUID, in tab: Tab) {
        tab.focusedLeafID = SplitTree.allLeaves(node: tab.splitRoot)
            .first { $0.surfaceID == surfaceID }?.id
    }

    @Test func eachSurfaceGetsItsOwnResolvedSurfaceTintStrength() {
        let (tab, ids) = splitTab()
        let (first, second) = (ids[0], ids[1])
        tab.settings.surfaceTintStrength = 0.3
        tab.surfaceSettings[second] = SettingOverrides(surfaceTintStrength: 0.4)

        let strengths = tab.surfaceTintStrengths(shared: SharedSettings())

        #expect(strengths == [first: 0.3, second: 0.4])
    }

    @Test func aSurfaceWithNoOverridesFollowsTheAppValue() {
        let (tab, ids) = splitTab()
        let first = ids[0]
        let shared = SharedSettings(app: AppSettings(surfaceTintStrength: 0.25))
        #expect(tab.surfaceTintStrengths(shared: shared)[first] == 0.25)
    }

    @Test func aRepoOverrideAppliesToSurfacesInThatRepo() {
        let (tab, ids) = splitTab()
        let (first, second) = (ids[0], ids[1])
        tab.surfaceDirectories[first] = "/work/alpha"
        tab.surfaceDirectories[second] = "/work/beta"
        let alpha = TabColor.repoIdentity(for: git("/work/alpha")!)
        let shared = SharedSettings(repos: [alpha: SettingOverrides(surfaceTintStrength: 0.45)])

        let strengths = tab.surfaceTintStrengths(shared: shared, gitInfoProvider: git)

        #expect(strengths == [first: 0.45, second: SurfaceTintStrength.default])
    }

    @Test func theTabTintStrengthFollowsTheFocusedSurface() {
        let (tab, ids) = splitTab()
        let (first, second) = (ids[0], ids[1])
        tab.settings.tabTintStrength = 0.2
        tab.surfaceSettings[second] = SettingOverrides(tabTintStrength: 0.05)

        #expect(tab.tabTintStrength(shared: SharedSettings()) == 0.2)
        focus(second, in: tab)
        #expect(tab.tabTintStrength(shared: SharedSettings()) == 0.05)
        focus(first, in: tab)
        #expect(tab.tabTintStrength(shared: SharedSettings()) == 0.2)
    }

    @Test func theFocusedSurfacesNameBeatsTheTabName() {
        let (tab, ids) = splitTab()
        let (first, second) = (ids[0], ids[1])
        tab.name = "MR 123"
        tab.surfaceNames[second] = "logs"

        #expect(tab.tabInfo.displayName == "MR 123")
        #expect(tab.displayName == "MR 123")
        focus(second, in: tab)
        #expect(tab.tabInfo.displayName == "logs")
        #expect(tab.displayName == "logs")
        focus(first, in: tab)
        #expect(tab.tabInfo.displayName == "MR 123")
    }

    @Test func bindingSurfacesCarriesNamesAndSettingsToTheNewSurface() {
        let placeholder = UUID()
        let tab = Tab(surfaceID: placeholder)
        let leaf = SplitTree.allLeaves(node: tab.splitRoot)[0]
        tab.surfaceNames[placeholder] = "logs"
        tab.surfaceSettings[placeholder] = SettingOverrides(surfaceTintStrength: 0.4)
        let created = UUID()

        tab.bindSurfaces([leaf.id: created])

        #expect(tab.surfaceNames == [created: "logs"])
        #expect(tab.surfaceSettings == [created: SettingOverrides(surfaceTintStrength: 0.4)])
    }

    @Test func aSurfaceCommandWritesBackOntoTheTabAndTheSharedSettings() {
        let (tab, ids) = splitTab()
        let first = ids[0]
        tab.surfaceToMonttyID[first] = "M1"
        var repoColorOverrides: [String: PaneTint] = [:]
        var shared = SharedSettings()

        for command: ControlCommand in [
            .setStrength(.surfaceTint, scope: .surface, value: 0.4),
            .setStrength(.tabTint, scope: .tab, value: 0.2),
            .setStrength(.tabTint, scope: .app, value: 0.1),
            .setMinimapHeight(scope: .tab, value: 60),
            .setSurfaceName("logs")
        ] {
            tab.applyControl(
                command, surfaceID: first, repoColorOverrides: &repoColorOverrides, shared: &shared
            )
        }

        #expect(tab.surfaceSettings[first]?.surfaceTintStrength == 0.4)
        #expect(tab.settings.tabTintStrength == 0.2)
        #expect(shared.app.tabTintStrength == 0.1)
        #expect(tab.minimapHeight == 60)
        #expect(tab.surfaceNames[first] == "logs")
    }
}

@Suite struct ScopedSettingsSessionTests {
    @Test func overridesAtEveryScopeSurviveSaveAndRestore() throws {
        let source = WindowUseCases(registry: WindowRegistry())
        let window = source.registry.add(WindowModel())
        let surfaceID = UUID()
        let tab = Tab(position: 0, surfaceID: surfaceID)
        tab.settings = SettingOverrides(tabTintStrength: 0.2)
        tab.minimapHeight = 60
        tab.surfaceSettings[surfaceID] = SettingOverrides(surfaceTintStrength: 0.4)
        tab.surfaceNames[surfaceID] = "logs"
        window.tabStore.append(tab: tab)
        let repos = ["repo-a": SettingOverrides(surfaceTintStrength: 0.3)]

        let saved = source.snapshot(
            surfaceTintEnabled: true,
            surfaceTintStrength: SurfaceTintStrength.default,
            repoColorOverrides: [:],
            frames: [:],
            directories: [:],
            repoSettingOverrides: repos
        )
        let reloaded = try JSONDecoder().decode(
            SessionSnapshot.self, from: try JSONEncoder().encode(saved)
        )

        let target = WindowUseCases()
        let outcome = target.restore(reloaded)
        let restored = try #require(target.registry.windows.first?.tabStore.tabs.first)
        let placeholder = try #require(restored.allSurfaceIDs.first)

        #expect(outcome.applySettings?.repoSettingOverrides == repos)
        #expect(restored.settings == SettingOverrides(tabTintStrength: 0.2))
        #expect(restored.minimapHeight == 60)
        #expect(restored.surfaceSettings[placeholder] == SettingOverrides(surfaceTintStrength: 0.4))
        #expect(restored.surfaceNames[placeholder] == "logs")
    }

    @Test func aSessionWithNoOverridesDecodesToNone() throws {
        let leafID = UUID()
        let json = """
        {"version":4,"windows":[{"windowID":"\(UUID())","tabs":[
          {"tabID":"\(UUID())","name":"","position":0,
           "splitLayout":{"type":"leaf","leaf":{"id":"\(leafID)","surfaceID":"\(UUID())"}},
           "leafDirectories":[]}]}]}
        """
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        let tab = try #require(decoded.windows.first?.tabs.first)

        #expect(decoded.repoSettingOverrides.isEmpty)
        #expect(tab.settingOverrides.isEmpty)
        #expect(tab.minimapHeight == nil)
        #expect(tab.leafSettingOverrides.isEmpty)
        #expect(tab.leafNames.isEmpty)
    }

    @Test func aTabMinimapHeightOutsideItsRangeIsDropped() throws {
        let leafID = UUID()
        let json = """
        {"version":4,"windows":[{"windowID":"\(UUID())","tabs":[
          {"tabID":"\(UUID())","name":"","position":0,"minimapHeight":9000,
           "splitLayout":{"type":"leaf","leaf":{"id":"\(leafID)","surfaceID":"\(UUID())"}},
           "leafDirectories":[]}]}]}
        """
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        #expect(decoded.windows.first?.tabs.first?.minimapHeight == nil)
    }
}
