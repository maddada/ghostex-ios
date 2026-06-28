import Foundation

enum TmuxStartupBehavior: String, Codable, CaseIterable, Identifiable {
    /// Current behavior: always attach to a VVTerm-managed tmux session.
    case vvtermManaged
    /// Ask user on each new connection.
    case askEveryTime
    /// Start shell without tmux.
    case skipTmux

    var id: String { rawValue }

    static let configCases = allCases

    var displayName: String {
        switch self {
        case .vvtermManaged:
            return String(localized: "Create VVTerm session")
        case .askEveryTime:
            return String(localized: "Ask every time")
        case .skipTmux:
            return String(localized: "Skip tmux")
        }
    }

    var descriptionText: String {
        switch self {
        case .vvtermManaged:
            return String(localized: "Always create or attach to a VVTerm-managed tmux session for this connection.")
        case .askEveryTime:
            return String(localized: "Show a prompt on each new tab or split so you can choose a session.")
        case .skipTmux:
            return String(localized: "Start a normal shell without tmux session persistence.")
        }
    }
}

enum TmuxPersistenceDefaults {
    static let enabledKey = "terminalTmuxEnabledDefault"
    static let startupBehaviorKey = "terminalTmuxStartupBehaviorDefault"

    /*
    CDXC:iOSSessionPersistence 2026-06-28-16:22:
    iOS tmux persistence is opt-in. Unset global preferences and new server forms must resolve tmux disabled so first connections use a normal SSH shell and do not show tmux attach or install prompts by default.
    */
    static let enabledDefault = false
    static let startupBehaviorDefault = TmuxStartupBehavior.askEveryTime

    static func resolvedEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: enabledKey) != nil else {
            return enabledDefault
        }
        return defaults.bool(forKey: enabledKey)
    }

    static func resolvedStartupBehavior(defaults: UserDefaults = .standard) -> TmuxStartupBehavior {
        guard let rawValue = defaults.string(forKey: startupBehaviorKey) else {
            return startupBehaviorDefault
        }
        return TmuxStartupBehavior(rawValue: rawValue) ?? startupBehaviorDefault
    }
}
