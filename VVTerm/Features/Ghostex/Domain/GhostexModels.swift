import Foundation

struct GhostexRemoteSession: Identifiable, Hashable, Sendable {
    let sessionId: String
    let alias: String
    let title: String
    let displayTitle: String
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
    let lastInteractionDate: Date?
    let displayStatus: String
    let displaySortPriority: Int
    let shouldSubmitStagedFirstPromptTitleCommand: Bool
    let sortOrder: Int?

    var id: String { sessionId }

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

        CDXC:GxserverSessionTitles 2026-06-07-09:33:
        iOS displays gxserver's `displayTitle` and keeps raw `title` for rename/session commands. The mobile client must not recompute unsynced markers or placeholder titles from title provenance fields.

        CDXC:iOSRemoteSessions 2026-06-11-23:52:
        iOS status refresh must require only SSH plus the remote gxserver-backed Ghostex CLI. `ghostex sessions --json` receives agent working/attention/idle state from gxserver list and presentation snapshot APIs, so the macOS app does not need to be running.

        CDXC:GxserverSessionTitle 2026-06-23-08:40:
        gxserver-rs owns first-prompt auto-name generation and staged rename text. iOS only parses the projected staged-command flag so the mobile SSH bridge can submit Enter when gxserver asks for it.
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
        displayTitle = Self.firstNonEmpty(Self.string(json["displayTitle"]), title)
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
        lastInteractionDate = Self.date(from: lastInteractionAt)
        displayStatus = Self.resolvedDisplayStatus(
            isSleeping: legacySleeping && !parsedIsLive,
            isLive: parsedIsLive,
            activity: activity,
            status: status
        )
        displaySortPriority = Self.sortPriority(forDisplayStatus: displayStatus)
        shouldSubmitStagedFirstPromptTitleCommand = (json["shouldSubmitStagedFirstPromptTitleCommand"] as? Bool) ?? false
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        The mobile summary now pre-sorts `sessions[]` to match the GPUI desktop
        sidebar and marks that with per-session `sortOrder`. Keep the field
        optional so older CLIs without it fall back to the legacy status/date
        display sort.
        */
        sortOrder = (json["sortOrder"] as? NSNumber)?.intValue
    }

    nonisolated var isZmxBacked: Bool {
        provider == "zmx"
    }

    nonisolated private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    nonisolated private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated private static func alias(from sessionId: String) -> String {
        String(sessionId.prefix(4))
    }

    nonisolated private static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        guard let rawTimeInterval = TimeInterval(trimmed) else { return nil }
        let timeInterval = rawTimeInterval > 10_000_000_000
            ? rawTimeInterval / 1_000
            : rawTimeInterval
        return Date(timeIntervalSince1970: timeInterval)
    }

    nonisolated private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func normalizedSessionState(_ value: String) -> String {
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

    nonisolated private static func normalizedNativePaneState(_ value: String, isSleeping: Bool, activity: String, status: String) -> String {
        let normalized = normalizedToken(value)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if ["mounted", "mounting", "unmounted"].contains(normalized) {
            return normalized
        }
        return defaultNativePaneState(isSleeping: isSleeping, activity: activity, status: status)
    }

    nonisolated private static func defaultNativePaneState(isSleeping: Bool, activity: String, status: String) -> String {
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

    nonisolated private static func normalizedProviderSessionState(_ value: String) -> String {
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

    nonisolated private static func derivedIsLive(nativePaneState: String, providerSessionState: String, isSleeping: Bool, activity: String, status: String) -> Bool {
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

    nonisolated private static func isLiveActivityState(_ value: String) -> Bool {
        value == "working" || value == "attention"
    }

    nonisolated private static func isActionableStatus(_ value: String) -> Bool {
        ["attention", "working", "done", "error"].contains(value)
    }

    nonisolated private static func resolvedDisplayStatus(
        isSleeping: Bool,
        isLive: Bool,
        activity: String,
        status: String
    ) -> String {
        if isSleeping && !isLive { return "sleep" }
        let activityState = normalizedSessionState(activity)
        let statusState = normalizedSessionState(status)
        if isActionableStatus(activityState) { return activityState }
        if isActionableStatus(statusState) { return statusState }
        if !isLive, activityState == "sleep" || statusState == "sleep" { return "sleep" }
        if !activityState.isEmpty, activityState != "running", !isLive || activityState != "sleep" { return activityState }
        if !statusState.isEmpty, statusState != "running", !isLive || statusState != "sleep" { return statusState }
        return "idle"
    }

    nonisolated private static func sortPriority(forDisplayStatus status: String) -> Int {
        switch status {
        case "done": return 0
        case "working": return 1
        default: return 2
        }
    }

    nonisolated fileprivate static func sessionListJSONData(from data: Data) throws -> Data {
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

    nonisolated private static func jsonObjectEnd(in text: String, startingAt start: String.Index) -> String.Index? {
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

struct GhostexRemoteProject: Identifiable, Hashable, Sendable {
    let projectId: String
    let name: String
    let path: String

    var id: String { projectId }

    nonisolated init?(json: [String: Any]) {
        let id = GhostexJSONValue.string(json["projectId"] ?? json["id"])
        guard !id.isEmpty else { return nil }
        projectId = id
        path = GhostexJSONValue.string(json["path"] ?? json["projectPath"])
        let rawName = GhostexJSONValue.string(json["name"] ?? json["projectName"])
        if !rawName.isEmpty {
            name = rawName
        } else if let lastPathComponent = path.split(separator: "/").last, !lastPathComponent.isEmpty {
            name = String(lastPathComponent)
        } else {
            name = "Project"
        }
    }
}

struct GhostexNamedSessionGroup: Identifiable, Hashable, Sendable {
    let groupId: String
    let title: String
    let sessionIds: [String]

    var id: String { groupId }

    nonisolated init?(json: [String: Any]) {
        let id = GhostexJSONValue.string(json["groupId"] ?? json["id"])
        guard !id.isEmpty else { return nil }
        groupId = id
        let rawTitle = GhostexJSONValue.string(json["title"] ?? json["name"])
        title = rawTitle.isEmpty ? id : rawTitle
        sessionIds = GhostexJSONValue.stringArray(json["sessionIds"])
    }
}

struct GhostexWorkspaceGroups: Hashable, Sendable {
    nonisolated static let empty = GhostexWorkspaceGroups(projectOrder: [], groupsByProject: [:])

    let projectOrder: [String]
    let groupsByProject: [String: [GhostexNamedSessionGroup]]

    nonisolated init(projectOrder: [String], groupsByProject: [String: [GhostexNamedSessionGroup]]) {
        self.projectOrder = projectOrder
        self.groupsByProject = groupsByProject
    }

    nonisolated init(json: [String: Any]?) {
        guard let json else {
            self = .empty
            return
        }
        projectOrder = GhostexJSONValue.stringArray(json["projectOrder"])
        var byProject: [String: [GhostexNamedSessionGroup]] = [:]
        if let projects = json["projects"] as? [String: Any] {
            for (projectId, value) in projects {
                guard let projectJSON = value as? [String: Any],
                      let rawGroups = projectJSON["groups"] as? [[String: Any]] else { continue }
                let groups = rawGroups.compactMap(GhostexNamedSessionGroup.init(json:))
                if !groups.isEmpty {
                    byProject[projectId] = groups
                }
            }
        }
        groupsByProject = byProject
    }
}

struct GhostexAgentLauncher: Identifiable, Hashable, Sendable {
    let agentId: String
    let icon: String
    let name: String

    var id: String { agentId }

    nonisolated init?(json: [String: Any]) {
        let id = GhostexJSONValue.string(json["agentId"] ?? json["id"])
        guard !id.isEmpty else { return nil }
        agentId = id
        icon = GhostexJSONValue.string(json["icon"])
        let rawName = GhostexJSONValue.string(json["name"])
        name = rawName.isEmpty ? id : rawName
    }
}

struct GhostexQuickAction: Identifiable, Hashable, Sendable {
    let actionType: String
    let commandId: String
    let icon: String
    let name: String
    let url: String

    var id: String { commandId.isEmpty ? "\(actionType):\(name):\(url)" : commandId }
    var isBrowserAction: Bool { actionType == "browser" }

    nonisolated init?(json: [String: Any]) {
        let type = GhostexJSONValue.string(json["actionType"] ?? json["type"]).lowercased()
        guard type == "terminal" || type == "browser" else { return nil }
        actionType = type
        commandId = GhostexJSONValue.string(json["commandId"] ?? json["id"])
        icon = GhostexJSONValue.string(json["icon"])
        url = GhostexJSONValue.string(json["url"])
        let rawName = GhostexJSONValue.string(json["name"] ?? json["title"])
        name = rawName.isEmpty ? (type == "browser" ? "Open URL" : "Run Action") : rawName
        if type == "terminal" && commandId.isEmpty { return nil }
        if type == "browser" && url.isEmpty { return nil }
    }
}

enum GhostexJSONValue {
    nonisolated static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    nonisolated static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.map(string).filter { !$0.isEmpty }
    }
}

struct GhostexSessionListSnapshot: Hashable, Sendable {
    static let empty = GhostexSessionListSnapshot(
        revision: "",
        sessions: [],
        projectGroups: [],
        agents: [],
        fingerprint: ""
    )

    let revision: String
    let sessions: [GhostexRemoteSession]
    let projectGroups: [GhostexProjectGroup]
    let agents: [GhostexAgentLauncher]
    let fingerprint: String

    nonisolated static func parse(from data: Data) throws -> GhostexSessionListSnapshot {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        The mobile summary also carries the desktop workspace shape: the full
        active-project list (including zero-session projects), the GPUI project
        order, per-project named session groups, the global agent launcher
        list, and per-project quick actions. All of these are optional so older
        CLIs keep the previous sessions-only rendering.
        */
        let jsonData = try GhostexRemoteSession.sessionListJSONData(from: data)
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw GhostexError("Ghostex sessions output was not JSON.")
        }
        if let ok = root["ok"] as? Bool, !ok {
            throw GhostexError((root["error"] as? String) ?? "Ghostex could not list sessions.")
        }

        let rawSessions = root["sessions"] as? [[String: Any]] ?? []
        let sessions = rawSessions.compactMap(GhostexRemoteSession.init(json:)).filter(\.isZmxBacked)

        let rawProjects = root["projects"] as? [[String: Any]] ?? []
        let projects = rawProjects.compactMap(GhostexRemoteProject.init(json:))

        let workspaceGroups = GhostexWorkspaceGroups(json: root["workspaceGroups"] as? [String: Any])

        let rawAgents = root["agents"] as? [[String: Any]] ?? []
        let agents = rawAgents.compactMap(GhostexAgentLauncher.init(json:))

        var quickActionsByProject: [String: [GhostexQuickAction]] = [:]
        if let rawQuickActions = root["quickActionsByProject"] as? [String: Any] {
            for (projectId, value) in rawQuickActions {
                guard let rawActions = value as? [[String: Any]] else { continue }
                let actions = rawActions.compactMap(GhostexQuickAction.init(json:))
                if !actions.isEmpty {
                    quickActionsByProject[projectId] = actions
                }
            }
        }

        let projectGroups = GhostexProjectGroup.groups(
            from: sessions,
            projects: projects,
            workspaceGroups: workspaceGroups,
            quickActionsByProject: quickActionsByProject
        )
        return GhostexSessionListSnapshot(
            revision: string(root["revision"] ?? root["snapshotRevision"] ?? root["requestId"]),
            sessions: sessions,
            projectGroups: projectGroups,
            agents: agents,
            fingerprint: fingerprint(
                for: sessions,
                projects: projects,
                workspaceGroups: workspaceGroups,
                agents: agents,
                quickActionsByProject: quickActionsByProject
            )
        )
    }

    nonisolated private static func string(_ value: Any?) -> String {
        GhostexJSONValue.string(value)
    }

    nonisolated private static func fingerprint(
        for sessions: [GhostexRemoteSession],
        projects: [GhostexRemoteProject],
        workspaceGroups: GhostexWorkspaceGroups,
        agents: [GhostexAgentLauncher],
        quickActionsByProject: [String: [GhostexQuickAction]]
    ) -> String {
        let sessionsFingerprint = sessions.map { session in
            [
                session.sessionId,
                session.projectId,
                session.groupId,
                session.projectName,
                session.projectPath,
                session.displayTitle,
                session.title,
                session.alias,
                session.displayStatus,
                session.agent,
                session.agentIcon,
                session.providerSessionName,
                session.providerSessionState,
                session.isFocused ? "1" : "0",
                session.isLive ? "1" : "0",
                session.isSleeping ? "1" : "0",
                session.lastInteractionAt,
                session.shouldSubmitStagedFirstPromptTitleCommand ? "1" : "0",
                session.sortOrder.map(String.init) ?? "",
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")

        let projectsFingerprint = projects.map {
            [$0.projectId, $0.name, $0.path].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")

        let groupsFingerprint = workspaceGroups.groupsByProject.keys.sorted().map { projectId in
            let groups = (workspaceGroups.groupsByProject[projectId] ?? []).map {
                ([$0.groupId, $0.title] + $0.sessionIds).joined(separator: "\u{1F}")
            }.joined(separator: "\u{1E}")
            return projectId + "\u{1E}" + groups
        }.joined(separator: "\u{1D}")

        let agentsFingerprint = agents.map {
            [$0.agentId, $0.icon, $0.name].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")

        let quickActionsFingerprint = quickActionsByProject.keys.sorted().map { projectId in
            let actions = (quickActionsByProject[projectId] ?? []).map {
                [$0.actionType, $0.commandId, $0.icon, $0.name, $0.url].joined(separator: "\u{1F}")
            }.joined(separator: "\u{1E}")
            return projectId + "\u{1E}" + actions
        }.joined(separator: "\u{1D}")

        return [
            sessionsFingerprint,
            projectsFingerprint,
            workspaceGroups.projectOrder.joined(separator: "\u{1F}"),
            groupsFingerprint,
            agentsFingerprint,
            quickActionsFingerprint,
        ].joined(separator: "\u{1C}")
    }
}

struct GhostexProjectSessionGroup: Identifiable, Hashable, Sendable {
    /*
    CDXC:iOSGhostexSidebarParity 2026-07-12:
    A project renders as ordered session sections: the implicit main group
    first (all project sessions no named group claims, in payload order), then
    each GPUI named group in `workspaceGroups` order with its sessions in the
    group's `sessionIds` order. The main group has no header; named groups get
    a collapsible header row.
    */
    let groupId: String
    let title: String
    let sessions: [GhostexRemoteSession]

    var isMain: Bool { groupId.isEmpty }
    var id: String { groupId.isEmpty ? "__main__" : groupId }
}

struct GhostexProjectGroup: Identifiable, Hashable, Sendable {
    let key: String
    let projectId: String
    let groupId: String
    let name: String
    let path: String
    let sessions: [GhostexRemoteSession]
    let sessionGroups: [GhostexProjectSessionGroup]
    let quickActions: [GhostexQuickAction]
    let workingCount: Int
    let sleepingCount: Int
    let attentionCount: Int

    var id: String { key }

    nonisolated init(
        key: String,
        projectId: String,
        groupId: String,
        name: String,
        path: String,
        sessions: [GhostexRemoteSession],
        sessionGroups: [GhostexProjectSessionGroup]? = nil,
        quickActions: [GhostexQuickAction] = [],
        workingCount: Int? = nil,
        sleepingCount: Int? = nil,
        attentionCount: Int? = nil
    ) {
        self.key = key
        self.projectId = projectId
        self.groupId = groupId
        self.name = name
        self.path = path
        self.sessions = sessions
        self.sessionGroups = sessionGroups ?? [GhostexProjectSessionGroup(groupId: "", title: "", sessions: sessions)]
        self.quickActions = quickActions
        self.workingCount = workingCount ?? sessions.filter { $0.displayStatus != "sleep" }.count
        self.sleepingCount = sleepingCount ?? sessions.filter { $0.displayStatus == "sleep" }.count
        self.attentionCount = attentionCount ?? sessions.filter { $0.displayStatus == "attention" }.count
    }

    nonisolated static func groups(
        from sessions: [GhostexRemoteSession],
        projects: [GhostexRemoteProject] = [],
        workspaceGroups: GhostexWorkspaceGroups = .empty,
        quickActionsByProject: [String: [GhostexQuickAction]] = [:]
    ) -> [GhostexProjectGroup] {
        struct Accumulator {
            let key: String
            let projectId: String
            let groupId: String
            let name: String
            let path: String
            var sessions: [GhostexRemoteSession]
            var workingCount: Int
            var sleepingCount: Int
            var attentionCount: Int

            init(session: GhostexRemoteSession, key: String) {
                self.key = key
                projectId = session.projectId
                groupId = session.groupId
                name = session.projectName
                path = session.projectPath
                sessions = []
                workingCount = 0
                sleepingCount = 0
                attentionCount = 0
                append(session)
            }

            mutating func append(_ session: GhostexRemoteSession) {
                sessions.append(session)
                if session.displayStatus == "sleep" {
                    sleepingCount += 1
                } else {
                    workingCount += 1
                }
                if session.displayStatus == "attention" {
                    attentionCount += 1
                }
            }
        }

        var groups: [Accumulator] = []
        var indexes: [String: Int] = [:]

        for session in sessions {
            let key = session.projectId.isEmpty
                ? (session.projectPath.isEmpty ? session.projectName : session.projectPath)
                : session.projectId
            if let index = indexes[key] {
                groups[index].append(session)
            } else {
                indexes[key] = groups.count
                groups.append(Accumulator(session: session, key: key))
            }
        }

        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        Every active project must render a section, including projects with
        zero sessions, so mobile can create the first terminal or agent there.
        Session-derived groups come first in payload order; the mobile summary
        `projects` array only appends the projects no session referenced.
        */
        var mergedGroups = groups.map { group -> GhostexProjectGroup in
            GhostexProjectGroup(
                key: group.key,
                projectId: group.projectId,
                groupId: group.groupId,
                name: group.name,
                path: group.path,
                sessions: displaySessions(for: group.sessions),
                quickActions: quickActionsByProject[group.projectId] ?? []
            )
        }
        let knownKeys = Set(mergedGroups.map(\.key))
        let knownPaths = Set(mergedGroups.map(\.path).filter { !$0.isEmpty })
        for project in projects
        where !knownKeys.contains(project.projectId) && (project.path.isEmpty || !knownPaths.contains(project.path)) {
            mergedGroups.append(GhostexProjectGroup(
                key: project.projectId,
                projectId: project.projectId,
                groupId: "",
                name: project.name,
                path: project.path,
                sessions: [],
                quickActions: quickActionsByProject[project.projectId] ?? []
            ))
        }

        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        Project sections follow the GPUI desktop order from
        `workspaceGroups.projectOrder`; projects the desktop payload does not
        list keep their current relative order after the ordered ones.
        */
        var orderIndexByProjectId: [String: Int] = [:]
        for (index, projectId) in workspaceGroups.projectOrder.enumerated() where orderIndexByProjectId[projectId] == nil {
            orderIndexByProjectId[projectId] = index
        }
        let orderedGroups = mergedGroups.enumerated().sorted { lhs, rhs in
            switch (orderIndexByProjectId[lhs.element.projectId], orderIndexByProjectId[rhs.element.projectId]) {
            case let (lhsOrder?, rhsOrder?):
                return lhsOrder < rhsOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)

        return orderedGroups.map { group in
            GhostexProjectGroup(
                key: group.key,
                projectId: group.projectId,
                groupId: group.groupId,
                name: group.name,
                path: group.path,
                sessions: group.sessions,
                sessionGroups: sessionGroups(
                    for: group.sessions,
                    namedGroups: workspaceGroups.groupsByProject[group.projectId] ?? []
                ),
                quickActions: group.quickActions
            )
        }
    }

    nonisolated private static func displaySessions(for sessions: [GhostexRemoteSession]) -> [GhostexRemoteSession] {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        When the CLI marks the payload as pre-sorted (any session carries
        `sortOrder`), preserve the array order so mobile matches the GPUI
        desktop sidebar. Older CLIs keep the legacy status/date sort.
        */
        sessions.contains { $0.sortOrder != nil } ? sessions : sortedSessionsForDisplay(sessions)
    }

    nonisolated private static func sessionGroups(
        for sessions: [GhostexRemoteSession],
        namedGroups: [GhostexNamedSessionGroup]
    ) -> [GhostexProjectSessionGroup] {
        guard !namedGroups.isEmpty else {
            return [GhostexProjectSessionGroup(groupId: "", title: "", sessions: sessions)]
        }

        var sessionsById: [String: GhostexRemoteSession] = [:]
        for session in sessions where !sessionsById.keys.contains(session.sessionId) {
            sessionsById[session.sessionId] = session
        }

        var claimedSessionIds = Set<String>()
        var namedSections: [GhostexProjectSessionGroup] = []
        for namedGroup in namedGroups {
            var resolved: [GhostexRemoteSession] = []
            for sessionId in namedGroup.sessionIds {
                guard let session = sessionsById[sessionId], !claimedSessionIds.contains(sessionId) else { continue }
                claimedSessionIds.insert(sessionId)
                resolved.append(session)
            }
            guard !resolved.isEmpty else { continue }
            namedSections.append(GhostexProjectSessionGroup(
                groupId: namedGroup.groupId,
                title: namedGroup.title,
                sessions: resolved
            ))
        }

        let mainSessions = sessions.filter { !claimedSessionIds.contains($0.sessionId) }
        return [GhostexProjectSessionGroup(groupId: "", title: "", sessions: mainSessions)] + namedSections
    }

    nonisolated private static func sortedSessionsForDisplay(_ sessions: [GhostexRemoteSession]) -> [GhostexRemoteSession] {
        sessions.sorted { lhs, rhs in
            let lhsPriority = lhs.displaySortPriority
            let rhsPriority = rhs.displaySortPriority
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            switch (lhs.lastInteractionDate, rhs.lastInteractionDate) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            let titleComparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.sessionId < rhs.sessionId
        }
    }
}

enum GhostexAgentIdentity {
    private static let knownIconIds: Set<String> = [
        "amp-cli", "antigravity-cli", "browser", "claude", "cursor-cli", "codex", "copilot",
        "factory-droid", "gemini", "grok-build", "hermes-agent", "opencode", "pi", "t3",
        "terminal",
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
        case "hermes", "hermes agent", "hermes-agent": return "hermes-agent"
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

    CDXC:iOSGhostexViewportRefresh 2026-06-22-05:48:
    After a Ghostex ZMX attach is visible and has stayed ready for the two-second post-attach delay, iOS should send the same PageUp/PageDown nudge users apply manually, in addition to the private redraw OSC. Keep the raw OSC sequence separately testable so the Android/iOS ZMX contract stays stable.
    */
    static let sequence = "\u{001B}]1337;ZMX_REFRESH\u{0007}"
    static let pageUpSequence = "\u{001B}[5~"
    static let pageDownSequence = "\u{001B}[6~"
    static let postAttachNudgeSequence = sequence + pageUpSequence + pageDownSequence
}

enum GhostexRemoteCommand {
    /*
    CDXC:iOSRemoteSessionsPerformance 2026-06-30-04:37:
    iOS opens the sessions sheet over SSH, so large Mac inventories should request the CLI's mobile summary payload instead of transferring desktop-only presentation fields that the mobile sidebar never renders.
    */
    static let sessionsList = loginShellCommand("ghostex sessions --json --mobile-summary")

    static func attach(sessionId: String, projectId: String = "") -> String {
        /*
        CDXC:iOSRemoteAttach 2026-06-04-02:22:
        gxserver session ids are scoped by project. Include projectId when the
        mobile inventory has it so `ghostex attach` resolves the full
        server/project/session zmx route instead of a bare G id.
        */
        var command = "ghostex attach --session-id \(shellQuote(sessionId))"
        if !projectId.isEmpty { command += " --project-id \(shellQuote(projectId))" }
        return loginShellCommand(command)
    }

    static func attach(_ session: GhostexRemoteSession) -> String {
        /*
        CDXC:iOSRemoteAttachLatency 2026-06-30-19:07:
        Mobile attach taps already receive the zmx provider session identity in the session list row. Use it directly for live zmx rows so opening a terminal does not run `ghostex attach --session-id`, which first performs a full inventory lookup and can add tens of seconds on large Mac hosts.
        */
        if session.isZmxBacked,
           !session.providerSessionName.isEmpty,
           session.providerSessionState == "exists" || session.isLive {
            return loginShellCommand("exec zmx attach \(shellQuote(session.providerSessionName))")
        }
        return attach(sessionId: session.sessionId, projectId: session.projectId)
    }

    static func sessionAction(_ action: String, session: GhostexRemoteSession) -> String {
        /*
        CDXC:iOSRemoteSessions 2026-05-31-08:45:
        gxserver lifecycle RPCs are project-scoped. iOS already has projectId
        from the shared `ghostex sessions --json` inventory, so context actions
        should send both ids and avoid depending on a Mac-side selector lookup.
        */
        var command = "ghostex \(action) --session-id \(shellQuote(session.sessionId))"
        if !session.projectId.isEmpty { command += " --project-id \(shellQuote(session.projectId))" }
        command += " --json"
        return loginShellCommand(command)
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

    static func createAgent(agentId: String, project: GhostexProjectGroup) -> String {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        `ghostex create-agent` creates and starts an agent session on the Mac
        host in one call; the result JSON matches create-session, so the
        existing created-session-id extraction and attach flow apply.
        */
        var command = "ghostex create-agent \(shellQuote(agentId))"
        if !project.projectId.isEmpty { command += " --project-id \(shellQuote(project.projectId))" }
        command += " --json"
        return loginShellCommand(command)
    }

    static func runAction(commandId: String, project: GhostexProjectGroup) -> String {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        `ghostex run-action` always prints JSON. iOS only routes terminal quick
        actions through SSH; browser quick actions open their summary-provided
        URL on-device without a round trip.
        */
        var command = "ghostex run-action \(shellQuote(commandId))"
        if !project.projectId.isEmpty { command += " --project-id \(shellQuote(project.projectId))" }
        return loginShellCommand(command)
    }

    static func sendEnter(_ session: GhostexRemoteSession) -> String {
        /*
        CDXC:GxserverSessionTitle 2026-06-23-08:40:
        iOS does not generate or stage first-prompt title commands. When gxserver-rs projects that the staged command is ready, route only the Enter submission through the Mac-hosted Ghostex CLI with project-scoped session identity.
        */
        var command = "ghostex send-enter --session-id \(shellQuote(session.sessionId))"
        if !session.projectId.isEmpty { command += " --project-id \(shellQuote(session.projectId))" }
        command += " --json"
        return loginShellCommand(command)
    }

    static func moveProject(_ project: GhostexProjectGroup, direction: String) -> String {
        loginShellCommand("ghostex move-project --project-id \(shellQuote(project.projectId)) --direction \(direction)")
    }

    static func renameSession(_ session: GhostexRemoteSession, title: String) -> String {
        var command = "ghostex rename-session --session-id \(shellQuote(session.sessionId))"
        if !session.projectId.isEmpty { command += " --project-id \(shellQuote(session.projectId))" }
        command += " --title \(shellQuote(title)) --json"
        return loginShellCommand(command)
    }

    static func loginShellCommand(_ command: String) -> String {
        /*
        CDXC:iOSRemoteSessions 2026-05-26-14:22:
        The VVTerm-based sidebar still talks to the Mac-hosted Ghostex CLI over SSH exec. Invoke commands through the user's zsh login environment so Homebrew and user-managed PATH entries resolve without reintroducing the old a-Shell command runner.

        CDXC:iOSRemoteSessions 2026-06-11-23:52:
        The Mac-hosted CLI is only the SSH entry point; session inventory and status must come from gxserver, not from a running macOS app or retired sidebar persistence bridge.
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
