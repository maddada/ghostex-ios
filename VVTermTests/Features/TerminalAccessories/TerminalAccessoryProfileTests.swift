import XCTest
@testable import VVTerm

final class TerminalAccessoryProfileTests: XCTestCase {
    func testDefaultRowsUseShiftInsteadOfCtrlU() {
        /*
        CDXC:iOSTerminalAccessories 2026-06-23-08:40:
        iOS's default accessory toolbar should match Android by exposing Shift where the old Ctrl-U shortcut lived.
        */
        XCTAssertEqual(TerminalAccessoryProfile.defaultActiveRows[0][1], .system(.shiftModifier))
        XCTAssertFalse(TerminalAccessoryProfile.defaultActiveItems.contains(.system(.ctrlU)))
    }

    func testNormalizedMigratesPreviousCtrlUDefaultRowsToShift() {
        /*
        CDXC:iOSTerminalAccessories 2026-06-23-08:40:
        Existing saved default-shaped accessory profiles should migrate from Ctrl-U to Shift while preserving custom layouts.
        */
        let profile = TerminalAccessoryProfile(
            schemaVersion: TerminalAccessoryProfile.schemaVersion,
            layout: TerminalAccessoryLayout(
                version: 1,
                activeItems: [],
                activeRows: [
                    [
                        .system(.escape),
                        .system(.ctrlU),
                        .system(.ctrlJ),
                        .system(.home),
                        .system(.arrowUp),
                        .system(.end),
                        .system(.pageUp)
                    ],
                    [
                        .system(.tab),
                        .system(.controlModifier),
                        .system(.alternateModifier),
                        .system(.arrowLeft),
                        .system(.arrowDown),
                        .system(.arrowRight),
                        .system(.pageDown)
                    ]
                ],
                updatedAt: Date()
            ),
            customActions: [],
            updatedAt: Date(),
            lastWriterDeviceId: "test-device"
        )

        let normalized = profile.normalized()

        XCTAssertEqual(normalized.layout.activeRows[0][1], .system(.shiftModifier))
        XCTAssertFalse(normalized.layout.activeItems.contains(.system(.ctrlU)))
    }

    func testNormalizedRemovesDuplicateActiveItems() {
        let profile = TerminalAccessoryProfile(
            schemaVersion: TerminalAccessoryProfile.schemaVersion,
            layout: TerminalAccessoryLayout(
                version: 1,
                activeItems: [
                    .system(.escape),
                    .system(.escape),
                    .system(.tab)
                ],
                updatedAt: Date()
            ),
            customActions: [],
            updatedAt: Date(),
            lastWriterDeviceId: "test-device"
        )

        let normalized = profile.normalized()

        XCTAssertEqual(
            normalized.layout.activeItems,
            [TerminalAccessoryItemRef.system(.escape), TerminalAccessoryItemRef.system(.tab)]
        )
    }

    func testNormalizedDropsDeletedCustomActionReferences() {
        let deletedAction = TerminalAccessoryCustomAction(
            id: UUID(),
            title: "Deleted",
            kind: .command,
            commandContent: "ls",
            commandSendMode: .insert,
            shortcutKey: .a,
            shortcutModifiers: .none,
            updatedAt: Date(),
            deletedAt: Date()
        )
        let profile = TerminalAccessoryProfile(
            schemaVersion: TerminalAccessoryProfile.schemaVersion,
            layout: TerminalAccessoryLayout(
                version: 1,
                activeItems: [.custom(deletedAction.id)],
                updatedAt: Date()
            ),
            customActions: [deletedAction],
            updatedAt: Date(),
            lastWriterDeviceId: "test-device"
        )

        let normalized = profile.normalized()

        XCTAssertTrue(normalized.layout.activeItems.isEmpty)
    }
}
