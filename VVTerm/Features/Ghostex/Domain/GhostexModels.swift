import Foundation

struct GhostexRemoteSession: Identifiable, Hashable {
    let sessionId: String
    let alias: String
    let title: String
    let projectId: String
    let groupId: String
    let projectName: String
    let projectPath: String
    let status: String
    let agent: String
    let agentIcon: String
    let providerSessionName: String
    let attachCommand: String
    let resumeCommand: String
    let isFocused: Bool
    let lastInteractionAt: String

    var id: String { sessionId }
    var displayStatus: String { status.isEmpty ? "session" : status }

    static func parseList(from data: Data) throws -> [GhostexRemoteSession] {
        let jsonData: Data
        if let text = String(data: data, encoding: .utf8),
           let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start <= end {
            jsonData = Data(text[start...end].utf8)
        } else {
            jsonData = data
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw GhostexError("Ghostex sessions output was not JSON.")
        }
        if let ok = root["ok"] as? Bool, !ok {
            throw GhostexError((root["error"] as? String) ?? "Ghostex could not list sessions.")
        }

        let rawSessions = root["sessions"] as? [[String: Any]] ?? []
        return rawSessions.compactMap(Self.init(json:))
    }

    init?(json: [String: Any]) {
        let id = Self.string(json["sessionId"] ?? json["id"])
        if id.isEmpty { return nil }

        sessionId = id
        alias = Self.string(json["alias"]).isEmpty ? "#" : Self.string(json["alias"])
        title = Self.string(json["title"]).isEmpty ? "Terminal Session" : Self.string(json["title"])
        projectId = Self.string(json["projectId"]).isEmpty ? Self.string(json["projectPath"]) : Self.string(json["projectId"])
        groupId = Self.string(json["groupId"])
        projectName = Self.string(json["projectName"]).isEmpty ? "Project" : Self.string(json["projectName"])
        projectPath = Self.string(json["projectPath"])
        status = Self.string(json["status"])
        agent = Self.string(json["agent"])
        agentIcon = Self.string(json["agentIcon"])
        providerSessionName = Self.string(json["providerSessionName"])
        attachCommand = Self.string(json["attachCommand"])
        resumeCommand = Self.string(json["resumeCommand"])
        isFocused = (json["isFocused"] as? Bool) ?? false
        lastInteractionAt = Self.string(json["lastInteractionAt"])
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
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
    var workingCount: Int { sessions.filter { $0.status != "sleep" }.count }
    var sleepingCount: Int { sessions.filter { $0.status == "sleep" }.count }
    var attentionCount: Int { sessions.filter { $0.status == "attention" }.count }

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

enum GhostexRemoteCommand {
    static let sessionsList = loginShellCommand("ghostex sessions --json")

    static func attach(sessionId: String) -> String {
        loginShellCommand("ghostex attach --session-id \(shellQuote(sessionId))")
    }

    static func sessionAction(_ action: String, sessionId: String) -> String {
        loginShellCommand("ghostex \(action) --session-id \(shellQuote(sessionId)) --json")
    }

    static func createSession(project: GhostexProjectGroup) -> String {
        var command = "ghostex create-session Terminal"
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

struct GhostexError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
