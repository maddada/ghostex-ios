import XCTest
@testable import VVTerm

@MainActor
final class ViewTabConfigurationManagerTests: XCTestCase {
    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "VVTermTests.ViewTabConfiguration.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testHiddenDefaultFallsBackToFirstVisibleTab() {
        let manager = ViewTabConfigurationManager(defaults: makeDefaults())
        manager.setDefaultTab(ConnectionViewTab.terminal.id)
        manager.setVisibility(for: ConnectionViewTab.terminal.id, isVisible: false)

        XCTAssertEqual(manager.effectiveDefaultTab(), ConnectionViewTab.stats.id)
    }

    func testCannotHideLastVisibleTab() {
        let manager = ViewTabConfigurationManager(defaults: makeDefaults())
        manager.setVisibility(for: ConnectionViewTab.terminal.id, isVisible: false)
        manager.setVisibility(for: ConnectionViewTab.files.id, isVisible: false)
        manager.setVisibility(for: ConnectionViewTab.sessions.id, isVisible: false)
        manager.setVisibility(for: ConnectionViewTab.stats.id, isVisible: false)

        XCTAssertTrue(manager.showStatsTab)
        XCTAssertEqual(manager.currentVisibleTabs, [ConnectionViewTab.stats])
    }

    func testSessionsTabIsVisibleByDefault() {
        /*
        CDXC:iOSGhostexSessionsPage 2026-06-30-19:36:
        The Ghostex sessions list is an in-place server view, so tab configuration must treat Sessions as a default visible view instead of an external sheet action.
        */
        let manager = ViewTabConfigurationManager(defaults: makeDefaults())

        XCTAssertTrue(manager.showSessionsTab)
        XCTAssertTrue(manager.currentVisibleTabs.contains(.sessions))
    }
}
