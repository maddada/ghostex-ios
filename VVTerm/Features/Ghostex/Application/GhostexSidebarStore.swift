import Foundation
import Combine
import os.log

@MainActor
final class GhostexSidebarStore: ObservableObject {
    static let shared = GhostexSidebarStore()

    @Published var selectedServerId: UUID? {
        didSet { persistSelectedServerId() }
    }
    @Published private(set) var sessions: [GhostexRemoteSession] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRunningAction = false
    @Published private(set) var lastError: String?
    @Published private(set) var logs: [String] = []

    private let selectedServerKey = "ghostex.sidebar.selectedServerId"
    private let logsKey = "ghostex.sidebar.logs"
    private let maxLogEntries = 80
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VVTerm", category: "GhostexSidebar")
    private var refreshTask: Task<Void, Never>?

    var projectGroups: [GhostexProjectGroup] {
        GhostexProjectGroup.groups(from: sessions)
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: selectedServerKey) {
            selectedServerId = UUID(uuidString: raw)
        }
        logs = UserDefaults.standard.stringArray(forKey: logsKey) ?? []
    }

    func selectedServer(from servers: [Server]) -> Server? {
        if let selectedServerId,
           let server = servers.first(where: { $0.id == selectedServerId }) {
            return server
        }
        return servers.first
    }

    func selectServer(_ server: Server) {
        selectedServerId = server.id
        appendLog("Selected Ghostex host \(server.displayAddress).")
    }

    func refresh(using serverManager: ServerManager) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.loadSessions(using: serverManager)
        }
    }

    func attach(
        _ session: GhostexRemoteSession,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        guard let server = selectedServer(from: serverManager.servers) else {
            throw GhostexError("Select a Ghostex host before attaching.")
        }

        /*
        CDXC:iOSGhostexSidebar 2026-05-26-14:22:
        Sidebar attach must open through VVTerm's existing terminal/session lifecycle. Create a normal VVTerm SSH session with a Ghostex startup command instead of porting the old a-Shell direct libssh2 terminal bridge.
        */
        appendLog("Opening Ghostex attach for \(session.sessionId) on \(server.displayAddress).")
        let attachSession = try await sessionManager.openConnection(
            to: server,
            forceNew: true,
            startupCommand: GhostexRemoteCommand.attach(sessionId: session.sessionId),
            title: session.title,
            skipTmuxLifecycle: true
        )
        sessionManager.selectedSessionId = attachSession.id
        sessionManager.selectedViewByServer[server.id] = ConnectionViewTab.terminal.id
    }

    func runSessionAction(
        _ action: String,
        session: GhostexRemoteSession,
        using serverManager: ServerManager
    ) {
        runRemote(
            GhostexRemoteCommand.sessionAction(action, sessionId: session.sessionId),
            description: "\(action) \(session.sessionId)",
            refreshAfter: true,
            using: serverManager
        )
    }

    func runProjectAction(
        _ action: String,
        project: GhostexProjectGroup,
        using serverManager: ServerManager
    ) {
        Task { [weak self] in
            guard let self else { return }
            await runProjectActionQueue(action, sessions: project.sessions, using: serverManager)
        }
    }

    func createSession(in project: GhostexProjectGroup, using serverManager: ServerManager) {
        runRemote(
            GhostexRemoteCommand.createSession(project: project),
            description: "create session in \(project.name)",
            refreshAfter: true,
            using: serverManager
        )
    }

    func moveProject(_ project: GhostexProjectGroup, direction: String, using serverManager: ServerManager) {
        guard !project.projectId.isEmpty else {
            lastError = "This project does not have a Ghostex project id."
            return
        }
        runRemote(
            GhostexRemoteCommand.moveProject(project, direction: direction),
            description: "move project \(direction) \(project.name)",
            refreshAfter: true,
            using: serverManager
        )
    }

    func renameSession(_ session: GhostexRemoteSession, title: String, using serverManager: ServerManager) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Session title cannot be empty."
            return
        }
        runRemote(
            GhostexRemoteCommand.renameSession(session, title: trimmed),
            description: "rename \(session.sessionId)",
            refreshAfter: true,
            using: serverManager
        )
    }

    func copyableAttachCommand(for session: GhostexRemoteSession, server: Server) -> String {
        let remoteCommand = GhostexRemoteCommand.attach(sessionId: session.sessionId)
        let portFragment = server.port == 22 ? "" : " -p \(server.port)"
        return "ssh -tt\(portFragment) \(server.username)@\(server.host) \(GhostexRemoteCommand.shellQuote(remoteCommand))"
    }

    func clearError() {
        lastError = nil
    }

    func reportError(_ error: Error) {
        lastError = error.localizedDescription
        appendLog("Error: \(error.localizedDescription)")
    }

    private func loadSessions(using serverManager: ServerManager) async {
        guard let server = selectedServer(from: serverManager.servers) else {
            sessions = []
            lastError = "Add or select a server to use as the Ghostex host."
            appendLog("Refresh skipped: no Ghostex host server is available.")
            return
        }

        isRefreshing = true
        lastError = nil
        appendLog("Refreshing Ghostex sessions from \(server.displayAddress).")

        do {
            let output = try await execute(GhostexRemoteCommand.sessionsList, on: server)
            let data = Data(output.utf8)
            let parsed = try GhostexRemoteSession.parseList(from: data)
            sessions = parsed
            selectedServerId = server.id
            appendLog("Refresh returned \(parsed.count) sessions.")
        } catch {
            let message = error.localizedDescription
            lastError = message
            appendLog("Refresh failed: \(message)")
        }

        isRefreshing = false
    }

    private func runRemote(
        _ command: String,
        description: String,
        refreshAfter: Bool,
        using serverManager: ServerManager
    ) {
        Task { [weak self] in
            guard let self else { return }
            guard let server = selectedServer(from: serverManager.servers) else {
                lastError = "Select a Ghostex host before running \(description)."
                return
            }

            isRunningAction = true
            lastError = nil
            appendLog("Running Ghostex action: \(description).")
            do {
                _ = try await execute(command, on: server)
                appendLog("Action finished: \(description).")
                if refreshAfter {
                    await loadSessions(using: serverManager)
                }
            } catch {
                lastError = error.localizedDescription
                appendLog("Action failed: \(description): \(error.localizedDescription)")
            }
            isRunningAction = false
        }
    }

    private func runProjectActionQueue(
        _ action: String,
        sessions: [GhostexRemoteSession],
        using serverManager: ServerManager
    ) async {
        guard let server = selectedServer(from: serverManager.servers) else {
            lastError = "Select a Ghostex host before running project actions."
            return
        }

        isRunningAction = true
        lastError = nil
        for session in sessions {
            do {
                appendLog("Running \(action) for \(session.sessionId).")
                _ = try await execute(
                    GhostexRemoteCommand.sessionAction(action, sessionId: session.sessionId),
                    on: server
                )
            } catch {
                lastError = error.localizedDescription
                appendLog("Project action \(action) failed for \(session.sessionId): \(error.localizedDescription)")
                break
            }
        }
        isRunningAction = false
        await loadSessions(using: serverManager)
    }

    private func execute(_ command: String, on server: Server) async throws -> String {
        let credentials = try KeychainManager.shared.getCredentials(for: server)
        logger.info("Executing Ghostex command on \(server.host, privacy: .public)")
        return try await SSHConnectionOperationService.shared.withTemporaryConnection(
            server: server,
            credentials: credentials
        ) { client in
            try await client.execute(command, timeout: .seconds(20))
        }
    }

    private func appendLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entry = "\(formatter.string(from: Date())) \(message)"
        logs.append(entry)
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
        UserDefaults.standard.set(logs, forKey: logsKey)
    }

    private func persistSelectedServerId() {
        if let selectedServerId {
            UserDefaults.standard.set(selectedServerId.uuidString, forKey: selectedServerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedServerKey)
        }
    }
}
