import Foundation

struct GhostexRemoteSession: Identifiable, Hashable {
    let sessionId: String
    let alias: String
    let title: String
    let projectId: String
    let groupId: String
    let projectName: String
    let projectPath: String
    let activity: String
    let status: String
    let provider: String
    let agent: String
    let agentIcon: String
    let providerSessionName: String
    let attachCommand: String
    let resumeCommand: String
    let isFocused: Bool
    let isSleeping: Bool
    let nativePaneState: String
    let providerSessionState: String
    let isLive: Bool
    let lastInteractionAt: String

    var id: String { sessionId }
    var displayStatus: String {
        if isSleeping && !isLive { return "sleep" }
        let activityState = Self.normalizedSessionState(activity)
        let statusState = Self.normalizedSessionState(status)
        if Self.isActionableStatus(activityState) { return activityState }
        if Self.isActionableStatus(statusState) { return statusState }
        if !isLive, activityState == "sleep" || statusState == "sleep" { return "sleep" }
        if !activityState.isEmpty, activityState != "running", !isLive || activityState != "sleep" { return activityState }
        if !statusState.isEmpty, statusState != "running", !isLive || statusState != "sleep" { return statusState }
        return "idle"
    }

    static func parseList(from data: Data) throws -> [GhostexRemoteSession] {
        /*
        CDXC:iOSGhostexSidebar 2026-05-28-19:43:
        The new VVTerm iOS Ghostex sidebar should ignore the ditched a-Shell fork and only show Mac-hosted ZMX-backed sessions. Parse the first complete sessions JSON object from noisy SSH/login-shell output so profile warnings or brace-like log text do not hide the usable Ghostex inventory.

        CDXC:iOSGhostexSidebar 2026-05-29-09:20:
        The Mac inventory separates native pane mount state from provider
        session existence. Parse those resource states and derived `isLive` so
        iOS keeps zmx-backed sessions visible as live even when no Mac native
        pane is currently mounted.

        CDXC:iOSGhostexSidebar 2026-05-29-06:29:
        Provider-disabled Mac sessions should parse as `providerSessionState:
        persistence-disabled`, not unknown, so iOS can tell disabled persistence
        apart from an incomplete provider existence check.

        CDXC:iOSGhostexSidebar 2026-05-29-07:19:
        Normalize provider-disabled sessions to `persistence-disabled`, not
        generic `disabled`, so the mobile contract names the exact capability
        that is off.
        */
        let jsonData = try sessionListJSONData(from: data)

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw GhostexError("Ghostex sessions output was not JSON.")
        }
        if let ok = root["ok"] as? Bool, !ok {
            throw GhostexError((root["error"] as? String) ?? "Ghostex could not list sessions.")
        }

        let rawSessions = root["sessions"] as? [[String: Any]] ?? []
        return rawSessions.compactMap(Self.init(json:)).filter(\.isZmxBacked)
    }

    nonisolated init?(json: [String: Any]) {
        let id = Self.string(json["sessionId"] ?? json["id"])
        if id.isEmpty { return nil }

        sessionId = id
        let rawAlias = Self.string(json["alias"])
        alias = rawAlias.isEmpty ? Self.alias(from: id) : rawAlias
        title = Self.firstNonEmpty(
            Self.string(json["title"]),
            Self.string(json["primaryTitle"]),
            Self.string(json["terminalTitle"]),
            "Terminal Session"
        )
        groupId = Self.string(json["groupId"])
        projectId = Self.firstNonEmpty(Self.string(json["projectId"]), groupId, Self.string(json["projectPath"]))
        projectName = Self.firstNonEmpty(Self.string(json["projectName"]), Self.string(json["groupTitle"]), "Project")
        projectPath = Self.string(json["projectPath"])
        activity = Self.normalizedSessionState(Self.firstNonEmpty(
            Self.string(json["activity"]),
            Self.string(json["activityState"]),
            Self.string(json["activityStatus"])
        ))
        status = Self.normalizedSessionState(Self.firstNonEmpty(
            Self.string(json["status"]),
            Self.string(json["lifecycleState"])
        ))
        provider = Self.normalizedToken(Self.firstNonEmpty(
            Self.string(json["provider"]),
            Self.string(json["sessionPersistenceProvider"])
        ))
        agent = Self.string(json["agent"])
        agentIcon = Self.string(json["agentIcon"])
        providerSessionName = Self.firstNonEmpty(
            Self.string(json["providerSessionName"]),
            Self.string(json["sessionPersistenceName"])
        )
        attachCommand = Self.string(json["attachCommand"])
        resumeCommand = Self.string(json["resumeCommand"])
        isFocused = (json["isFocused"] as? Bool) ?? false
        let legacySleeping = (json["isSleeping"] as? Bool) ?? (status == "sleep")
        let parsedNativePaneState = Self.normalizedNativePaneState(
            Self.string(json["nativePaneState"]),
            isSleeping: legacySleeping,
            activity: activity,
            status: status
        )
        let parsedProviderSessionState = Self.normalizedProviderSessionState(Self.string(json["providerSessionState"]))
        let parsedIsLive = (json["isLive"] as? Bool) ?? Self.derivedIsLive(
            nativePaneState: parsedNativePaneState,
            providerSessionState: parsedProviderSessionState,
            isSleeping: legacySleeping,
            activity: activity,
            status: status
        )
        nativePaneState = parsedNativePaneState
        providerSessionState = parsedProviderSessionState
        isLive = parsedIsLive
        isSleeping = legacySleeping && !parsedIsLive
        lastInteractionAt = Self.string(json["lastInteractionAt"])
    }

    var isZmxBacked: Bool {
        provider == "zmx"
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func alias(from sessionId: String) -> String {
        String(sessionId.prefix(4))
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedSessionState(_ value: String) -> String {
        let normalized = normalizedToken(value)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "needs-attention", "attention-required":
            return "attention"
        case "active", "busy", "processing":
            return "working"
        case "sleeping":
            return "sleep"
        default:
            return normalized
        }
    }

    private static func normalizedNativePaneState(_ value: String, isSleeping: Bool, activity: String, status: String) -> String {
        let normalized = normalizedToken(value)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if ["mounted", "mounting", "unmounted"].contains(normalized) {
            return normalized
        }
        return defaultNativePaneState(isSleeping: isSleeping, activity: activity, status: status)
    }

    private static func defaultNativePaneState(isSleeping: Bool, activity: String, status: String) -> String {
        if isSleeping { return "unmounted" }
        let activityState = normalizedSessionState(activity)
        let statusState = normalizedSessionState(status)
        if isLiveActivityState(activityState) || isLiveActivityState(statusState) ||
            activityState == "running" || statusState == "running" ||
            activityState == "idle" || statusState == "idle" {
            return "mounted"
        }
        return "unmounted"
    }

    private static func normalizedProviderSessionState(_ value: String) -> String {
        let normalized = normalizedToken(value)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if ["persistence-disabled", "exists", "missing", "unknown"].contains(normalized) {
            return normalized
        }
        if ["disabled", "none", "off", "disabled-persistence"].contains(normalized) {
            return "persistence-disabled"
        }
        if normalized == "running" { return "exists" }
        return "unknown"
    }

    private static func derivedIsLive(nativePaneState: String, providerSessionState: String, isSleeping: Bool, activity: String, status: String) -> Bool {
        if nativePaneState == "mounted" || nativePaneState == "mounting" || providerSessionState == "exists" {
            return true
        }
        let activityState = normalizedSessionState(activity)
        let statusState = normalizedSessionState(status)
        if isLiveActivityState(activityState) || isLiveActivityState(statusState) { return true }
        if isSleeping || activityState == "sleep" || statusState == "sleep" ||
            activityState == "done" || statusState == "done" ||
            activityState == "error" || statusState == "error" ||
            statusState == "exited" {
            return false
        }
        return activityState == "running" || statusState == "running" ||
            activityState == "idle" || statusState == "idle"
    }

    private static func isLiveActivityState(_ value: String) -> Bool {
        value == "working" || value == "attention"
    }

    private static func isActionableStatus(_ value: String) -> Bool {
        ["attention", "working", "done", "error"].contains(value)
    }

    private static func sessionListJSONData(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        var searchStart = text.startIndex
        var sawIncompleteObject = false

        while searchStart < text.endIndex {
            guard let start = text[searchStart...].firstIndex(of: "{") else { break }
            guard let end = jsonObjectEnd(in: text, startingAt: start) else {
                sawIncompleteObject = true
                searchStart = text.index(after: start)
                continue
            }

            let candidate = Data(text[start...end].utf8)
            if let root = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any],
               root["sessions"] is [[String: Any]] {
                return candidate
            }
            searchStart = text.index(after: end)
        }

        if sawIncompleteObject {
            throw GhostexError("Ghostex CLI returned incomplete JSON.")
        }
        throw GhostexError(text.contains("{") ? "Ghostex CLI did not return a sessions JSON payload." : "Ghostex CLI did not return JSON.")
    }

    private static func jsonObjectEnd(in text: String, startingAt start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaping = false

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }

        return nil
    }
}

struct GhostexProjectGroup: Identifiable, Hashable {
    let key: String
    let projectId: String
    let groupId: String
    let name: String
    let path: String
    let sessions: [GhostexRemoteSession]

    var id: String { key }
    var workingCount: Int { sessions.filter { $0.displayStatus != "sleep" }.count }
    var sleepingCount: Int { sessions.filter { $0.displayStatus == "sleep" }.count }
    var attentionCount: Int { sessions.filter { $0.displayStatus == "attention" }.count }

    static func groups(from sessions: [GhostexRemoteSession]) -> [GhostexProjectGroup] {
        var groups: [GhostexProjectGroup] = []
        var indexes: [String: Int] = [:]

        for session in sessions {
            let key = session.projectId.isEmpty
                ? (session.projectPath.isEmpty ? session.projectName : session.projectPath)
                : session.projectId
            if let index = indexes[key] {
                let existing = groups[index]
                groups[index] = GhostexProjectGroup(
                    key: existing.key,
                    projectId: existing.projectId,
                    groupId: existing.groupId,
                    name: existing.name,
                    path: existing.path,
                    sessions: existing.sessions + [session]
                )
            } else {
                indexes[key] = groups.count
                groups.append(GhostexProjectGroup(
                    key: key,
                    projectId: session.projectId,
                    groupId: session.groupId,
                    name: session.projectName,
                    path: session.projectPath,
                    sessions: [session]
                ))
            }
        }

        return groups
    }
}

enum GhostexAgentIdentity {
    private static let knownIconIds: Set<String> = [
        "amp-cli", "antigravity-cli", "browser", "claude", "cursor-cli", "codex", "copilot",
        "factory-droid", "gemini", "grok-build", "opencode", "pi", "t3", "terminal",
    ]

    static func resolveIconId(agentIcon: String, agent: String) -> String {
        let icon = agentIcon.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if knownIconIds.contains(icon) { return icon }

        let normalized = agent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "t3", "t3 code": return "t3"
        case "codex", "codex cli": return "codex"
        case "claude", "claude code": return "claude"
        case "cursor", "cursor cli", "cursor agent", "cursor-agent": return "cursor-cli"
        case "pi", "pi agent", "π": return "pi"
        case "opencode", "open code": return "opencode"
        case "gemini": return "gemini"
        case "copilot", "github copilot": return "copilot"
        case "droid", "factory droid": return "factory-droid"
        case "grok", "grok build": return "grok-build"
        case "antigravity", "antigravity cli", "agy": return "antigravity-cli"
        case "amp", "amp cli": return "amp-cli"
        case "browser": return "browser"
        default: return knownIconIds.contains(normalized) ? normalized : "terminal"
        }
    }

    static func assetName(for iconId: String) -> String {
        "ghostex-agent-\(iconId)"
    }
}

enum GhostexZmxViewportRefresh {
    /*
    CDXC:iOSGhostexSidebar 2026-05-28-20:59:
    ZMX-backed mobile attaches need Android's post-switch redraw OSC after VVTerm reports the current grid, otherwise the remote ZMX client can keep stale dimensions after the iOS tab becomes visible.
    */
    static let sequence = "\u{001B}]1337;ZMX_REFRESH\u{0007}"
}

enum GhostexRemoteCommand {
    static let sessionsList = loginShellCommand("ghostex sessions --json")

    static func attach(sessionId: String) -> String {
        loginShellCommand("ghostex attach --session-id \(shellQuote(sessionId))")
    }

    static func sessionAction(_ action: String, sessionId: String) -> String {
        loginShellCommand("ghostex \(action) --session-id \(shellQuote(sessionId)) --json")
    }

    static func createSession(project: GhostexProjectGroup) -> String {
        var command = "ghostex create-session --json"
        if !project.projectId.isEmpty { command += " --project-id \(shellQuote(project.projectId))" }
        if !project.groupId.isEmpty { command += " --group-id \(shellQuote(project.groupId))" }
        return loginShellCommand(command)
    }

    static func moveProject(_ project: GhostexProjectGroup, direction: String) -> String {
        loginShellCommand("ghostex move-project --project-id \(shellQuote(project.projectId)) --direction \(direction)")
    }

    static func renameSession(_ session: GhostexRemoteSession, title: String) -> String {
        loginShellCommand("ghostex rename-session --session-id \(shellQuote(session.sessionId)) --title \(shellQuote(title)) --json")
    }

    static func loginShellCommand(_ command: String) -> String {
        /*
        CDXC:iOSRemoteSessions 2026-05-26-14:22:
        The VVTerm-based sidebar still talks to the Mac-hosted Ghostex CLI over SSH exec. Invoke commands through the user's zsh login environment so Homebrew and user-managed PATH entries resolve without reintroducing the old a-Shell command runner.
        */
        "/bin/zsh -lc \(shellQuote(command))"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

enum GhostexCreateSessionResult {
    static func createdSessionId(from output: String) -> String? {
        /*
        CDXC:iOSGhostexSidebar 2026-05-28-20:37:
        Ghostex create-session returns the underlying ZMX sessionId plus the sidebar/list identity as ghostexId. Match the list identity first so create-and-attach can find the refreshed session instead of reporting a false missing-session error.
        */
        guard let data = try? jsonData(from: output),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["ok"] as? Bool) != false,
              let session = root["session"] as? [String: Any] else {
            return nil
        }
        let sessionId = string(session["ghostexId"] ?? session["sessionId"] ?? session["id"])
        return sessionId.isEmpty ? nil : sessionId
    }

    private static func jsonData(from output: String) throws -> Data {
        var searchStart = output.startIndex
        while searchStart < output.endIndex {
            guard let start = output[searchStart...].firstIndex(of: "{") else { break }
            guard let end = jsonObjectEnd(in: output, startingAt: start) else {
                searchStart = output.index(after: start)
                continue
            }
            let candidate = Data(output[start...end].utf8)
            if let root = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any],
               root["session"] is [String: Any] {
                return candidate
            }
            searchStart = output.index(after: end)
        }
        throw GhostexError("Ghostex create-session did not return JSON.")
    }

    private static func jsonObjectEnd(in text: String, startingAt start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaping = false

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }
}

struct GhostexError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
