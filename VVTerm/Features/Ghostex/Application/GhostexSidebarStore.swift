import Foundation
import Combine
import os.log

/*
CDXC:iOSGhostexMultiMachine 2026-07-18:
The sessions page mirrors the desktop GPUI sidebar by stacking every saved
machine at once, each with its own Quick/projects/session inventory. The
store therefore keeps one inventory per server id instead of a single
selected-host snapshot, and every action carries the explicit target server
so identical session ids on two machines can never collide or misroute.
*/
struct GhostexMachineInventory: Sendable {
    var sessions: [GhostexRemoteSession] = []
    var projectGroups: [GhostexProjectGroup] = []
    var agents: [GhostexAgentLauncher] = []
    var recentProjects: [GhostexRecentProject] = []
    var lastError: String?
    var hasLoaded = false
}

@MainActor
final class GhostexSidebarStore: ObservableObject {
    static let shared = GhostexSidebarStore()

    @Published private(set) var inventoriesByServerId: [UUID: GhostexMachineInventory] = [:]
    @Published private(set) var collapsedProjectKeys: Set<String> = []
    @Published private(set) var collapsedSessionGroupKeys: Set<String> = []
    @Published private(set) var collapsedMachineKeys: Set<String> = []
    @Published private(set) var refreshingServerIds: Set<UUID> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRunningAction = false
    /*
    CDXC:iOSGhostexSidebarParity 2026-07-12:
    New-terminal, agent, and terminal quick-action taps switch to the terminal
    page immediately while the SSH create + attach round trip continues in the
    background. `pendingCreationLabel` drives the "Creating terminal" style
    overlay on the terminal page until that background work settles.
    */
    @Published private(set) var pendingCreationLabel: String?
    @Published private(set) var lastError: String?
    @Published private(set) var logs: [String] = []

    private let logsKey = "ghostex.sidebar.logs"
    private let maxLogEntries = 80
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VVTerm", category: "GhostexSidebar")
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var submittedFirstPromptTitleCommandEnterKeys = Set<String>()
    private var knownProjectKeysByServerId: [UUID: Set<String>] = [:]
    private var lastFingerprintByServerId: [UUID: String] = [:]
    /*
    CDXC:iOSGhostexSidebar 2026-06-12-09:48:
    Session refresh cancellation is expected when a new refresh, attach, or reuse action supersedes an in-flight list request. Track concurrent refreshes so a canceled older request cannot clear the spinner for a newer request, and keep cancellation out of user-facing errors.

    CDXC:iOSRemoteSessionsPerformance 2026-06-30-04:37:
    Large Mac session inventories must publish one precomputed list snapshot instead of deriving project groups from `sessions` during SwiftUI rendering. Keep project collapse state in this shared store for the current app run so reopening the sheet preserves expanded projects without persisting that state across app restarts. Background polls should not publish spinner/log churn when the mobile summary payload is unchanged.

    CDXC:iOSRemoteAttachLatency 2026-06-30-19:07:
    Attach taps must take priority over the expensive remote inventory command. Cancel visible/background refresh tasks before opening a terminal, and slow background polling after long refreshes so a 100+ session Mac does not continuously compete with user-initiated attaches.

    CDXC:iOSGhostexMultiMachine 2026-07-18:
    Every machine refreshes concurrently: one task-group child per saved
    server, each doing its own SSH round trip, keyed spinner state, and
    per-server fingerprint so an unchanged machine publishes nothing while a
    changed one republishes only its own inventory. A slow or unreachable
    machine records its error on its own inventory instead of blocking or
    alerting over the healthy machines; the global error alert only surfaces
    for user-initiated refreshes and explicit actions.
    */
    private var activeRefreshCountsByServerId: [UUID: Int] = [:]
    private let regularPollDelaySeconds = 15
    private let slowPollDelaySeconds = 60
    private let slowPollThresholdSeconds: TimeInterval = 10

    private init() {
        logs = UserDefaults.standard.stringArray(forKey: logsKey) ?? []
    }

    func inventory(for server: Server) -> GhostexMachineInventory {
        inventoriesByServerId[server.id] ?? GhostexMachineInventory()
    }

    func refresh(using serverManager: ServerManager) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.loadAllInventories(using: serverManager)
        }
    }

    func attach(
        _ session: GhostexRemoteSession,
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        let shouldResumePollingOnFailure = suspendRefreshesForAttach()

        /*
        CDXC:iOSGhostexSidebar 2026-05-26-14:22:
        Sidebar attach must open through VVTerm's existing terminal/session lifecycle. Create a normal VVTerm SSH session with a Ghostex startup command instead of porting the old a-Shell direct libssh2 terminal bridge.

        CDXC:iOSGhostexSidebar 2026-05-28-17:43:
        Reopening the same Ghostex ZMX session from the iOS sidebar should select the existing VVTerm attach tab when it is still live instead of creating duplicate SSH attach terminals. This ports Android's warm-session switching intent while staying inside VVTerm's tab/session ownership model.

        CDXC:iOSGhostexSidebar 2026-05-28-20:59:
        ZMX-backed mobile attaches need the same delayed viewport refresh as Android sidebar and notification taps so the remote ZMX client repaints with the VVTerm grid after the tab becomes current.
        */
        do {
            let startupCommand = GhostexRemoteCommand.attach(session)
            if let existingSession = sessionManager.sessions.first(where: {
                $0.serverId == server.id &&
                    $0.startupCommand == startupCommand &&
                    ($0.connectionState.isConnected || $0.connectionState.isConnecting)
            }) {
                appendLog("Reusing Ghostex attach for \(session.sessionId) on \(server.displayAddress).")
                sessionManager.selectedSessionId = existingSession.id
                sessionManager.selectedViewByServer[server.id] = ConnectionViewTab.terminal.id
                scheduleViewportRefreshIfNeeded(
                    for: session,
                    localSessionId: existingSession.id,
                    sessionManager: sessionManager,
                    reason: "ghostex-warm-session-reuse"
                )
                return
            }

            appendLog("Opening Ghostex attach for \(session.sessionId) on \(server.displayAddress).")
            let attachSession = try await sessionManager.openConnection(
                to: server,
                forceNew: true,
                startupCommand: startupCommand,
                title: session.displayTitle,
                skipTmuxLifecycle: true
            )
            sessionManager.selectedSessionId = attachSession.id
            sessionManager.selectedViewByServer[server.id] = ConnectionViewTab.terminal.id
            scheduleViewportRefreshIfNeeded(
                for: session,
                localSessionId: attachSession.id,
                sessionManager: sessionManager,
                reason: "ghostex-new-ssh-attach"
            )
        } catch {
            if shouldResumePollingOnFailure {
                startPolling(using: serverManager)
            }
            throw error
        }
    }

    func runSessionAction(
        _ action: String,
        session: GhostexRemoteSession,
        on server: Server,
        using serverManager: ServerManager
    ) {
        runRemote(
            GhostexRemoteCommand.sessionAction(action, session: session),
            description: "\(action) \(session.sessionId)",
            refreshAfter: true,
            on: server,
            using: serverManager
        )
    }

    func runProjectAction(
        _ action: String,
        project: GhostexProjectGroup,
        on server: Server,
        using serverManager: ServerManager
    ) {
        Task { [weak self] in
            guard let self else { return }
            await runProjectActionQueue(action, sessions: project.sessions, on: server, using: serverManager)
        }
    }

    func createSession(
        in project: GhostexProjectGroup,
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        try await createAndAttachRemoteSession(
            command: GhostexRemoteCommand.createSession(project: project),
            description: "create session in \(project.name)",
            on: server,
            using: serverManager,
            sessionManager: sessionManager
        )
    }

    func createChatSession(
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-18:
        The Quick header "+" mirrors the desktop New Chat action: every Quick
        session gets a fresh projectless chat workspace, so this cannot go
        through `create-session --project-id`. The chat-create command makes
        the ~/ghostex/chats folder and creates its first terminal in one SSH
        round trip; the result JSON matches create-session, so the shared
        create-and-attach flow applies.
        */
        try await createAndAttachRemoteSession(
            command: GhostexRemoteCommand.createChatSession,
            description: "create Quick session",
            on: server,
            using: serverManager,
            sessionManager: sessionManager
        )
    }

    func createAgentSession(
        _ agent: GhostexAgentLauncher,
        in project: GhostexProjectGroup,
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        guard !project.projectId.isEmpty else {
            throw GhostexError("This project does not have a Ghostex project id.")
        }
        try await createAndAttachRemoteSession(
            command: GhostexRemoteCommand.createAgent(agentId: agent.agentId, project: project),
            description: "start \(agent.name) in \(project.name)",
            on: server,
            using: serverManager,
            sessionManager: sessionManager
        )
    }

    func runTerminalQuickAction(
        _ action: GhostexQuickAction,
        in project: GhostexProjectGroup,
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        guard !project.projectId.isEmpty else {
            throw GhostexError("This project does not have a Ghostex project id.")
        }
        try await createAndAttachRemoteSession(
            command: GhostexRemoteCommand.runAction(commandId: action.commandId, project: project),
            description: "run \(action.name) in \(project.name)",
            on: server,
            using: serverManager,
            sessionManager: sessionManager
        )
    }

    func beginPendingCreation(label: String) {
        pendingCreationLabel = label
    }

    func endPendingCreation() {
        pendingCreationLabel = nil
    }

    private func createAndAttachRemoteSession(
        command: String,
        description: String,
        on server: Server,
        using serverManager: ServerManager,
        sessionManager: ConnectionSessionManager
    ) async throws {
        /*
        CDXC:iOSGhostexSidebar 2026-05-28-17:43:
        Creating a project session from mobile should match Android and macOS behavior: ask the Mac app to create the ZMX-backed terminal, refresh the sidebar inventory, then attach the new session immediately when the CLI returns a stable session id.

        CDXC:iOSGhostexSidebarParity 2026-07-12:
        create-session, create-agent, and run-action (terminal) share one
        create-and-attach flow because all three return the same
        `session.sessionId` JSON shape.
        */
        isRunningAction = true
        if lastError != nil {
            lastError = nil
        }
        appendLog("Running Ghostex action: \(description) on \(server.displayAddress).")
        do {
            let output = try await execute(command, on: server)
            appendLog("Action finished: \(description).")
            await loadInventory(for: server)

            guard let createdSessionId = GhostexCreateSessionResult.createdSessionId(from: output) else {
                throw GhostexError("Ghostex created the session but did not return its session id.")
            }
            let refreshedSessions = inventoriesByServerId[server.id]?.sessions ?? []
            guard let createdSession = refreshedSessions.first(where: { $0.sessionId == createdSessionId }) else {
                throw GhostexError("Ghostex created the session, but it was not present after refresh.")
            }
            try await attach(createdSession, on: server, using: serverManager, sessionManager: sessionManager)
            isRunningAction = false
        } catch {
            isRunningAction = false
            lastError = error.localizedDescription
            appendLog("Action failed: \(description): \(error.localizedDescription)")
            throw error
        }
    }

    func moveProject(
        _ project: GhostexProjectGroup,
        direction: String,
        on server: Server,
        using serverManager: ServerManager
    ) {
        guard !project.projectId.isEmpty else {
            lastError = "This project does not have a Ghostex project id."
            return
        }
        runRemote(
            GhostexRemoteCommand.moveProject(project, direction: direction),
            description: "move project \(direction) \(project.name)",
            refreshAfter: true,
            on: server,
            using: serverManager
        )
    }

    func restoreRecentProject(
        _ project: GhostexRecentProject,
        on server: Server,
        using serverManager: ServerManager
    ) {
        runRemote(
            GhostexRemoteCommand.restoreRecentProject(project),
            description: "restore recent project \(project.title)",
            refreshAfter: true,
            on: server,
            using: serverManager
        )
    }

    func renameSession(
        _ session: GhostexRemoteSession,
        title: String,
        on server: Server,
        using serverManager: ServerManager
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Session title cannot be empty."
            return
        }
        runRemote(
            GhostexRemoteCommand.renameSession(session, title: trimmed),
            description: "rename \(session.sessionId)",
            refreshAfter: true,
            on: server,
            using: serverManager
        )
    }

    func copyableAttachCommand(for session: GhostexRemoteSession, server: Server) -> String {
        let remoteCommand = GhostexRemoteCommand.attach(session)
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

    func startPolling(using serverManager: ServerManager) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if !serverManager.servers.isEmpty {
                    let startedAt = Date()
                    await self?.loadAllInventories(using: serverManager, showsRefreshIndicator: false)
                    guard !Task.isCancelled else { break }
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let delaySeconds = elapsed >= (self?.slowPollThresholdSeconds ?? 10)
                        ? (self?.slowPollDelaySeconds ?? 60)
                        : (self?.regularPollDelaySeconds ?? 15)
                    try? await Task.sleep(for: .seconds(delaySeconds))
                } else {
                    try? await Task.sleep(for: .seconds(self?.regularPollDelaySeconds ?? 15))
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func isMachineCollapsed(_ server: Server) -> Bool {
        collapsedMachineKeys.contains(server.id.uuidString)
    }

    func toggleMachineCollapse(_ server: Server) {
        /*
        CDXC:iOSGhostexMultiMachine 2026-07-18:
        Machine sections collapse like projects and named session groups:
        state lives in this shared store for the current app run only.
        */
        let key = server.id.uuidString
        if collapsedMachineKeys.contains(key) {
            collapsedMachineKeys.remove(key)
        } else {
            collapsedMachineKeys.insert(key)
        }
    }

    func isProjectCollapsed(_ project: GhostexProjectGroup, on server: Server) -> Bool {
        collapsedProjectKeys.contains(projectCollapseKey(serverId: server.id, projectKey: project.id))
    }

    func toggleProjectCollapse(_ project: GhostexProjectGroup, on server: Server) {
        let key = projectCollapseKey(serverId: server.id, projectKey: project.id)
        if collapsedProjectKeys.contains(key) {
            collapsedProjectKeys.remove(key)
        } else {
            collapsedProjectKeys.insert(key)
        }
    }

    func isSessionGroupCollapsed(
        _ group: GhostexProjectSessionGroup,
        in project: GhostexProjectGroup,
        on server: Server
    ) -> Bool {
        collapsedSessionGroupKeys.contains(sessionGroupCollapseKey(serverId: server.id, project: project, group: group))
    }

    func toggleSessionGroupCollapse(
        _ group: GhostexProjectSessionGroup,
        in project: GhostexProjectGroup,
        on server: Server
    ) {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        Named GPUI session groups collapse like projects do: state lives in
        this shared store for the current app run, so reopening the sessions
        page preserves the expanded groups without persisting across restarts.
        */
        let key = sessionGroupCollapseKey(serverId: server.id, project: project, group: group)
        if collapsedSessionGroupKeys.contains(key) {
            collapsedSessionGroupKeys.remove(key)
        } else {
            collapsedSessionGroupKeys.insert(key)
        }
    }

    private func collapseKeyPrefix(for serverId: UUID) -> String {
        serverId.uuidString + "\u{1F}"
    }

    private func projectCollapseKey(serverId: UUID, projectKey: String) -> String {
        collapseKeyPrefix(for: serverId) + projectKey
    }

    private func sessionGroupCollapseKey(
        serverId: UUID,
        project: GhostexProjectGroup,
        group: GhostexProjectSessionGroup
    ) -> String {
        collapseKeyPrefix(for: serverId) + "\(project.id)\u{1F}\(group.id)"
    }

    private func loadAllInventories(using serverManager: ServerManager, showsRefreshIndicator: Bool = true) async {
        let servers = serverManager.servers
        guard !servers.isEmpty else {
            inventoriesByServerId = [:]
            knownProjectKeysByServerId = [:]
            lastFingerprintByServerId = [:]
            lastError = "Add a server to use as the Ghostex host."
            appendLog("Refresh skipped: no Ghostex host server is available.")
            return
        }

        let currentServerIds = Set(servers.map(\.id))
        if inventoriesByServerId.keys.contains(where: { !currentServerIds.contains($0) }) {
            inventoriesByServerId = inventoriesByServerId.filter { currentServerIds.contains($0.key) }
            knownProjectKeysByServerId = knownProjectKeysByServerId.filter { currentServerIds.contains($0.key) }
            lastFingerprintByServerId = lastFingerprintByServerId.filter { currentServerIds.contains($0.key) }
        }
        if showsRefreshIndicator, lastError != nil {
            lastError = nil
        }

        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask { @MainActor [weak self] in
                    await self?.loadInventory(for: server, showsRefreshIndicator: showsRefreshIndicator)
                }
            }
        }
    }

    private func loadInventory(for server: Server, showsRefreshIndicator: Bool = true) async {
        if showsRefreshIndicator {
            beginRefresh(for: server.id)
            appendLog("Refreshing Ghostex sessions from \(server.displayAddress).")
        }
        defer {
            if showsRefreshIndicator {
                endRefresh(for: server.id)
            }
        }

        do {
            let output = try await execute(GhostexRemoteCommand.sessionsList, on: server)
            guard !Task.isCancelled else { return }
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try GhostexSessionListSnapshot.parse(from: Data(output.utf8))
            }.value
            guard !Task.isCancelled else { return }
            let isUnchanged = snapshot.fingerprint == lastFingerprintByServerId[server.id]
            if !isUnchanged {
                publishSnapshot(snapshot, for: server)
                appendLog("Refresh returned \(snapshot.sessions.count) sessions from \(server.displayAddress).")
            } else if showsRefreshIndicator {
                appendLog("Refresh returned unchanged session snapshot from \(server.displayAddress).")
            }
            if inventoriesByServerId[server.id]?.lastError != nil {
                inventoriesByServerId[server.id]?.lastError = nil
            }
            if inventoriesByServerId[server.id]?.hasLoaded == false {
                inventoriesByServerId[server.id]?.hasLoaded = true
            }
            Task { [weak self] in
                await self?.submitStagedFirstPromptTitleCommands(from: snapshot.sessions, on: server)
            }
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            return
        } catch {
            let message = error.localizedDescription
            var inventory = inventoriesByServerId[server.id] ?? GhostexMachineInventory()
            inventory.lastError = message
            inventory.hasLoaded = true
            inventoriesByServerId[server.id] = inventory
            if showsRefreshIndicator {
                lastError = "\(server.name): \(message)"
            }
            appendLog("Refresh failed for \(server.displayAddress): \(message)")
        }
    }

    private func publishSnapshot(_ snapshot: GhostexSessionListSnapshot, for server: Server) {
        let currentProjectKeys = Set(snapshot.projectGroups.map {
            projectCollapseKey(serverId: server.id, projectKey: $0.id)
        })
        let knownKeys = knownProjectKeysByServerId[server.id] ?? []
        let serverPrefix = collapseKeyPrefix(for: server.id)
        let otherServerCollapsedKeys = collapsedProjectKeys.filter { !$0.hasPrefix(serverPrefix) }
        var nextServerCollapsedKeys = collapsedProjectKeys.intersection(currentProjectKeys)
        nextServerCollapsedKeys.formUnion(currentProjectKeys.subtracting(knownKeys))
        knownProjectKeysByServerId[server.id] = currentProjectKeys
        collapsedProjectKeys = otherServerCollapsedKeys.union(nextServerCollapsedKeys)

        var inventory = inventoriesByServerId[server.id] ?? GhostexMachineInventory()
        inventory.sessions = snapshot.sessions
        inventory.projectGroups = snapshot.projectGroups
        inventory.agents = snapshot.agents
        inventory.recentProjects = snapshot.recentProjects
        inventory.lastError = nil
        inventory.hasLoaded = true
        inventoriesByServerId[server.id] = inventory
        lastFingerprintByServerId[server.id] = snapshot.fingerprint
    }

    private func suspendRefreshesForAttach() -> Bool {
        let shouldResumePollingOnFailure = pollTask != nil
        refreshTask?.cancel()
        refreshTask = nil
        pollTask?.cancel()
        pollTask = nil
        activeRefreshCountsByServerId = [:]
        refreshingServerIds = []
        isRefreshing = false
        return shouldResumePollingOnFailure
    }

    private func submitStagedFirstPromptTitleCommands(from parsed: [GhostexRemoteSession], on server: Server) async {
        /*
        CDXC:GxserverSessionTitle 2026-06-23-08:40:
        iOS should mirror macOS first-prompt auto-naming without moving generation into the mobile app. When gxserver-rs marks a staged rename command ready, submit exactly one Enter per server/project/session over the existing SSH CLI bridge.
        */
        for session in parsed where session.shouldSubmitStagedFirstPromptTitleCommand {
            let submitKey = firstPromptTitleCommandSubmitKey(server: server, session: session)
            guard !submittedFirstPromptTitleCommandEnterKeys.contains(submitKey) else { continue }
            submittedFirstPromptTitleCommandEnterKeys.insert(submitKey)
            do {
                _ = try await execute(GhostexRemoteCommand.sendEnter(session), on: server)
                appendLog("Submitted staged first-prompt title command.")
            } catch {
                appendLog("Could not submit staged first-prompt title command: \(error.localizedDescription)")
            }
        }
    }

    private func firstPromptTitleCommandSubmitKey(server: Server, session: GhostexRemoteSession) -> String {
        "\(server.id.uuidString):\(session.projectId):\(session.sessionId)"
    }

    private func runRemote(
        _ command: String,
        description: String,
        refreshAfter: Bool,
        on server: Server,
        using serverManager: ServerManager
    ) {
        Task { [weak self] in
            guard let self else { return }

            isRunningAction = true
            lastError = nil
            appendLog("Running Ghostex action: \(description) on \(server.displayAddress).")
            do {
                _ = try await execute(command, on: server)
                appendLog("Action finished: \(description).")
                if refreshAfter {
                    await loadInventory(for: server)
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
        on server: Server,
        using serverManager: ServerManager
    ) async {
        isRunningAction = true
        lastError = nil
        for session in sessions {
            do {
                appendLog("Running \(action) for \(session.sessionId).")
                _ = try await execute(
                    GhostexRemoteCommand.sessionAction(action, session: session),
                    on: server
                )
            } catch {
                lastError = error.localizedDescription
                appendLog("Project action \(action) failed for \(session.sessionId): \(error.localizedDescription)")
                break
            }
        }
        isRunningAction = false
        await loadInventory(for: server)
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

    private func scheduleViewportRefreshIfNeeded(
        for remoteSession: GhostexRemoteSession,
        localSessionId: UUID,
        sessionManager: ConnectionSessionManager,
        reason: String
    ) {
        guard remoteSession.isZmxBacked else { return }
        sessionManager.scheduleTerminalViewportRefreshAfterSessionSwitch(
            sessionId: localSessionId,
            redrawSequence: GhostexZmxViewportRefresh.postAttachNudgeSequence,
            reason: reason
        )
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

    private func beginRefresh(for serverId: UUID) {
        activeRefreshCountsByServerId[serverId, default: 0] += 1
        refreshingServerIds.insert(serverId)
        isRefreshing = true
    }

    private func endRefresh(for serverId: UUID) {
        let next = max(0, (activeRefreshCountsByServerId[serverId] ?? 0) - 1)
        activeRefreshCountsByServerId[serverId] = next
        if next == 0 {
            refreshingServerIds.remove(serverId)
        }
        isRefreshing = !refreshingServerIds.isEmpty
    }
}
