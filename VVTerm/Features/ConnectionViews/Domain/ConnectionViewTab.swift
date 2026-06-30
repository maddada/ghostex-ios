import Foundation

struct ConnectionViewTab: Identifiable, Hashable, Codable, Equatable {
    let id: String
    let localizedKey: String
    let icon: String

    static let stats = ConnectionViewTab(
        id: "stats",
        localizedKey: "Stats",
        icon: "chart.bar.xaxis"
    )

    static let terminal = ConnectionViewTab(
        id: "terminal",
        localizedKey: "Terminal",
        icon: "terminal"
    )

    static let files = ConnectionViewTab(
        id: "files",
        localizedKey: "Files",
        icon: "folder"
    )

    /*
    CDXC:iOSGhostexSessionsPage 2026-06-30-19:36:
    Ghostex sessions must be a first-class server view like Stats, Terminal, and Files so switching to it renders an in-place page instead of presenting a bottom drawer.

    CDXC:iOSGhostexSessionsPage 2026-06-30-22:01:
    The Sessions tab should use a chat-bubble icon so the control reads as conversations/sessions rather than a robot-specific agent affordance.
    */
    static let sessions = ConnectionViewTab(
        id: "sessions",
        localizedKey: "Sessions",
        icon: "bubble.left.and.bubble.right"
    )

    static let defaultOrder: [ConnectionViewTab] = [.stats, .terminal, .files, .sessions]
    static let allTabs: [ConnectionViewTab] = defaultOrder

    static func from(id: String) -> ConnectionViewTab? {
        allTabs.first { $0.id == id }
    }
}
