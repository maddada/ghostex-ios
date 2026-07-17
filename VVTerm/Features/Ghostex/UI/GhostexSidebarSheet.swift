import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
private extension GhostexAgentIdentity {
    static func systemSymbolName(for iconId: String) -> String {
        switch iconId {
        case "codex": return "circle.hexagongrid.fill"
        case "claude": return "sparkle"
        case "cursor-cli": return "cursorarrow"
        case "gemini": return "sparkles"
        case "copilot": return "person.2.fill"
        case "factory-droid": return "gearshape.2.fill"
        case "browser": return "globe"
        case "pi": return "function"
        case "opencode": return "chevron.left.forwardslash.chevron.right"
        case "t3": return "t.circle.fill"
        case "antigravity-cli": return "arrow.up.right.circle.fill"
        case "amp-cli": return "bolt.fill"
        case "grok-build": return "xmark.circle.fill"
        default: return "terminal.fill"
        }
    }

    static func tint(for iconId: String) -> Color {
        switch iconId {
        case "antigravity-cli": return Color(red: 0.45, green: 0.61, blue: 1.0)
        case "browser": return Color(red: 0.51, green: 0.72, blue: 1.0)
        case "claude": return Color(red: 0.85, green: 0.47, blue: 0.34)
        case "cursor-cli": return Color(red: 0.93, green: 0.93, blue: 0.93)
        case "factory-droid": return Color(red: 1.0, green: 0.48, blue: 0.10)
        case "gemini": return Color(red: 0.55, green: 0.60, blue: 1.0)
        case "opencode": return Color(red: 0.43, green: 0.59, blue: 0.75)
        case "pi": return Color(red: 0.78, green: 1.0, blue: 0.38)
        case "t3": return Color(red: 1.0, green: 0.42, blue: 0.95)
        default: return .primary
        }
    }
}

struct GhostexSessionsView: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var sessionManager: ConnectionSessionManager
    @ObservedObject var store: GhostexSidebarStore
    let onOpenTerminal: () -> Void
    let onReturnToSessions: () -> Void

    @State private var detailSession: GhostexRemoteSession?
    @State private var detailProject: GhostexProjectGroup?
    @State private var renamingTarget: GhostexSessionServerTarget?
    @State private var renameTitle = ""
    @State private var showingLogs = false
    @State private var recentProjectsServer: Server?
    @State private var filterText = ""

    /*
    CDXC:iOSGhostexMultiMachine 2026-07-18:
    The list mirrors the desktop GPUI sidebar's stacked remote-machine
    sections: every saved server renders at once with its own machine header
    (when 2+ machines exist) followed by that machine's Quick/projects
    sections. All row actions carry the machine's server explicitly, so the
    old single-host picker is gone.
    */
    private var machineServers: [Server] {
        serverManager.servers
    }

    private var showsMachineHeaders: Bool {
        machineServers.count > 1
    }

    private var normalizedFilterText: String {
        normalizedSearchText(filterText)
    }

    private var isFiltering: Bool {
        !normalizedFilterText.isEmpty
    }

    private func displayedProjectGroups(for inventory: GhostexMachineInventory) -> [GhostexProjectGroup] {
        guard isFiltering else { return inventory.projectGroups }
        return inventory.projectGroups.compactMap { filteredProjectGroup($0, query: normalizedFilterText) }
    }

    var body: some View {
        List {
            machinesControlSection
            filterSection
            machineListSections
            runningActionSection
        }
        .listStyle(.insetGrouped)
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            store.startPolling(using: serverManager)
        }
        .onDisappear {
            store.stopPolling()
        }
        .refreshable {
            store.refresh(using: serverManager)
        }
        .sheet(isPresented: $showingLogs) {
            GhostexDiagnosticsView(logs: store.logs)
        }
        .sheet(isPresented: $showingRecentProjects) {
            GhostexRecentProjectsView(projects: store.recentProjects) { project in
                store.restoreRecentProject(project, using: serverManager)
                showingRecentProjects = false
            }
        }
        .alert("Ghostex", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.lastError ?? "")
        }
        .alert("Rename Session", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Session title", text: $renameTitle)
            Button("Cancel", role: .cancel) {
                renamingSession = nil
                renameTitle = ""
            }
            Button("Rename") {
                if let renamingSession {
                    store.renameSession(renamingSession, title: renameTitle, using: serverManager)
                }
                renamingSession = nil
                renameTitle = ""
            }
        } message: {
            Text("Update this session title in Ghostex.")
        }
        .alert(item: $detailSession) { session in
            Alert(
                title: Text(session.displayTitle),
                message: Text(sessionDetailText(session)),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $detailProject) { project in
            Alert(
                title: Text(project.name),
                message: Text(projectDetailText(project)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var hostSection: some View {
        Section {
            if serverManager.servers.isEmpty {
                GhostexEmptyState(
                    title: "No Servers",
                    systemImage: "server.rack",
                    description: "Add a Ghostex server for the Mac that runs the Ghostex CLI."
                )
            } else {
                Picker("Ghostex Host", selection: Binding(
                    get: { selectedServer?.id },
                    set: { newValue in
                        guard let newValue,
                              let server = serverManager.servers.first(where: { $0.id == newValue }) else { return }
                        store.selectServer(server)
                    }
                )) {
                    ForEach(serverManager.servers.sorted { $0.name < $1.name }) { server in
                        Text(server.name).tag(Optional(server.id))
                    }
                }

                if let selectedServer {
                    LabeledContent("Address", value: selectedServer.displayAddress)
                }

                Button {
                    store.refresh(using: serverManager)
                } label: {
                    Label(store.isRefreshing ? "Refreshing Sessions" : "Refresh Sessions", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                if !store.recentProjects.isEmpty {
                    Button {
                        showingRecentProjects = true
                    } label: {
                        Label("Recent Projects", systemImage: "clock.arrow.circlepath")
                    }
                }

                Button {
                    showingLogs = true
                } label: {
                    Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
                }
            }
        } header: {
            Text("Machine")
        }
    }

    private var filterSection: some View {
        Section {
            /*
            CDXC:iOSGhostexSessionsFilter 2026-07-01-00:08:
            The sessions filter is a full-width grouped-list row, not small footer copy. Filtering must update continuously while the user types, keep keyboard focus across result changes, expand matching projects, and use strict fuzzy matching so short unrelated strings do not match.
            */
            GhostexSessionFilterBar(text: $filterText)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if displayedProjectGroups.isEmpty {
            Section("Sessions") {
                if store.isRefreshing {
                    /*
                    CDXC:iOSRemoteSessions 2026-06-30-04:37:
                    The empty sessions loading state should read as one centered row inside the grouped list card instead of leaving the spinner and label left-biased by the default ProgressView label layout.
                    */
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading sessions")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                        .accessibilityElement(children: .combine)
                } else if isFiltering {
                    GhostexEmptyState(
                        title: "No Matches",
                        systemImage: "magnifyingglass",
                        description: "No projects contain sessions matching this filter."
                    )
                } else {
                    GhostexEmptyState(
                        title: "No Sessions",
                        systemImage: "rectangle.stack",
                        description: "Refresh after selecting the Ghostex host."
                    )
                }
            }
        } else {
            ForEach(Array(displayedProjectGroups.enumerated()), id: \.element.id) { index, project in
                Section {
                    if isFiltering || !store.isProjectCollapsed(project) {
                        if !isFiltering, !launcherAgents(for: project).isEmpty || !project.quickActions.isEmpty {
                            /*
                            CDXC:iOSGhostexSidebarParity 2026-07-12:
                            The agents isle and quick actions render as one
                            horizontally scrollable launcher row under each
                            expanded project header, mirroring the GPUI
                            desktop per-project launcher surface.
                            */
                            GhostexLauncherIsle(
                                agents: launcherAgents(for: project),
                                quickActions: project.quickActions,
                                onLaunchAgent: { launchAgent($0, in: project) },
                                onRunQuickAction: { runQuickAction($0, in: project) }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }

                        if project.sessions.isEmpty, !isFiltering {
                            Text("No sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 6)
                        }

                        ForEach(project.sessionGroups) { sessionGroup in
                            if !sessionGroup.isMain {
                                GhostexSessionGroupHeaderRow(
                                    title: sessionGroup.title,
                                    sessionCount: sessionGroup.sessions.count,
                                    isCollapsed: !isFiltering && store.isSessionGroupCollapsed(sessionGroup, in: project),
                                    onToggle: {
                                        if !isFiltering {
                                            store.toggleSessionGroupCollapse(sessionGroup, in: project)
                                        }
                                    }
                                )
                            }
                            if sessionGroup.isMain || isFiltering || !store.isSessionGroupCollapsed(sessionGroup, in: project) {
                                ForEach(sessionGroup.sessions) { session in
                                    GhostexSessionRow(session: session)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            attach(session)
                                        }
                                        .contextMenu {
                                            sessionMenu(session)
                                        }
                                }
                            }
                        }
                    }
                } header: {
                    GhostexProjectHeader(
                        project: project,
                        isCollapsed: !isFiltering && store.isProjectCollapsed(project),
                        canMoveUp: !project.isChatCollection && displayedProjectGroups.prefix(index).contains { !$0.isChatCollection },
                        canMoveDown: !project.isChatCollection && displayedProjectGroups.dropFirst(index + 1).contains { !$0.isChatCollection },
                        onToggleCollapse: {
                            if !isFiltering {
                                store.toggleProjectCollapse(project)
                            }
                        },
                        onCreate: { createAndAttachSession(in: project) },
                        onRefresh: { store.refresh(using: serverManager) },
                        onMoveUp: { store.moveProject(project, direction: "up", using: serverManager) },
                        onMoveDown: { store.moveProject(project, direction: "down", using: serverManager) },
                        onWake: { store.runProjectAction("wake", project: project, using: serverManager) },
                        onSleep: { store.runProjectAction("sleep", project: project, using: serverManager) },
                        onKill: { store.runProjectAction("kill", project: project, using: serverManager) },
                        onCopyPath: { UIPasteboard.general.string = project.path },
                        onDetails: { detailProject = project }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var runningActionSection: some View {
        if store.isRunningAction {
            Section {
                ProgressView("Running action")
            }
        }
    }

    @ViewBuilder
    private func sessionMenu(_ session: GhostexRemoteSession) -> some View {
        Button {
            attach(session)
        } label: {
            Label("Attach", systemImage: "terminal")
        }

        Button {
            store.runSessionAction("focus", session: session, using: serverManager)
        } label: {
            Label("Focus on Mac", systemImage: "scope")
        }

        Button {
            renamingSession = session
            renameTitle = session.title
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            store.runSessionAction("wake", session: session, using: serverManager)
        } label: {
            Label("Wake", systemImage: "sun.max")
        }

        Button {
            store.runSessionAction("sleep", session: session, using: serverManager)
        } label: {
            Label("Sleep", systemImage: "moon")
        }

        Button(role: .destructive) {
            store.runSessionAction("kill", session: session, using: serverManager)
        } label: {
            Label("Kill", systemImage: "xmark.octagon")
        }

        Button {
            if let selectedServer {
                UIPasteboard.general.string = store.copyableAttachCommand(for: session, server: selectedServer)
            }
        } label: {
            Label("Copy Attach Command", systemImage: "doc.on.doc")
        }

        Button {
            detailSession = session
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    private func attach(_ session: GhostexRemoteSession) {
        Task {
            do {
                try await store.attach(session, using: serverManager, sessionManager: sessionManager)
                onOpenTerminal()
            } catch {
                store.reportError(error)
            }
        }
    }

    private func launcherAgents(for project: GhostexProjectGroup) -> [GhostexAgentLauncher] {
        // Agent launches need a project id for `ghostex create-agent --project-id`.
        project.projectId.isEmpty ? [] : store.agents
    }

    private func createAndAttachSession(in project: GhostexProjectGroup) {
        runInstantCreation(label: "Creating terminal…") {
            try await store.createSession(in: project, using: serverManager, sessionManager: sessionManager)
        }
    }

    private func launchAgent(_ agent: GhostexAgentLauncher, in project: GhostexProjectGroup) {
        runInstantCreation(label: "Starting \(agent.name)…") {
            try await store.createAgentSession(agent, in: project, using: serverManager, sessionManager: sessionManager)
        }
    }

    private func runQuickAction(_ action: GhostexQuickAction, in project: GhostexProjectGroup) {
        if action.isBrowserAction {
            /*
            CDXC:iOSGhostexSidebarParity 2026-07-12:
            Browser quick actions carry their URL in the mobile summary, so
            open it directly on-device instead of asking the Mac over SSH.
            */
            guard let url = URL(string: action.url), url.scheme != nil else {
                store.reportError(GhostexError("Quick action \(action.name) does not have a valid URL."))
                return
            }
            UIApplication.shared.open(url)
            return
        }
        runInstantCreation(label: "Running \(action.name)…") {
            try await store.runTerminalQuickAction(action, in: project, using: serverManager, sessionManager: sessionManager)
        }
    }

    private func runInstantCreation(label: String, operation: @escaping () async throws -> Void) {
        /*
        CDXC:iOSGhostexSidebarParity 2026-07-12:
        Creation taps must leave the sessions list immediately: switch to the
        terminal page first with the store's pending-creation overlay visible,
        run the SSH create + attach in the background, and on failure return
        to the sessions page where the store error alert surfaces.
        */
        store.beginPendingCreation(label: label)
        onOpenTerminal()
        Task {
            do {
                try await operation()
                store.endPendingCreation()
            } catch {
                store.endPendingCreation()
                store.reportError(error)
                onReturnToSessions()
            }
        }
    }

    private func sessionDetailText(_ session: GhostexRemoteSession) -> String {
        [
            "Project: \(session.projectName)",
            "Project path: \(session.projectPath.isEmpty ? "-" : session.projectPath)",
            "Status: \(session.displayStatus)",
            "Focused on Mac: \(session.isFocused ? "Yes" : "No")",
            "Provider: zmx",
            "ZMX session: \(session.providerSessionName.isEmpty ? "-" : session.providerSessionName)",
            "Agent: \(session.agent.isEmpty ? "-" : session.agent)",
            "Session id: \(session.sessionId)",
            "Attach command: \(session.attachCommand.isEmpty ? "-" : session.attachCommand)",
        ].joined(separator: "\n")
    }

    private func projectDetailText(_ project: GhostexProjectGroup) -> String {
        [
            "Path: \(project.path.isEmpty ? "-" : project.path)",
            "Sessions: \(project.sessions.count)",
            "Working: \(project.workingCount)",
            "Attention: \(project.attentionCount)",
            "Sleeping: \(project.sleepingCount)",
        ].joined(separator: "\n")
    }

    private func filteredProjectGroup(_ project: GhostexProjectGroup, query: String) -> GhostexProjectGroup? {
        /*
        CDXC:iOSGhostexSessionsFilter 2026-07-01-00:08:
        Filters now run as users type instead of waiting for four characters. Project metadata matches still show every session in that project; otherwise fuzzy row matching keeps results helpful without turning the filter into broad substring noise.
        */
        let projectMatches = contains(query, in: [
            project.name,
            project.path,
            project.projectId,
            project.groupId,
        ])
        let filteredSessionGroups: [GhostexProjectSessionGroup] = project.sessionGroups.compactMap { sessionGroup in
            let keptSessions = projectMatches
                ? sessionGroup.sessions
                : sessionGroup.sessions.filter { matches($0, query: query) }
            guard !keptSessions.isEmpty else { return nil }
            return GhostexProjectSessionGroup(
                groupId: sessionGroup.groupId,
                title: sessionGroup.title,
                sessions: keptSessions
            )
        }
        let filteredSessions = filteredSessionGroups.flatMap(\.sessions)
        guard !filteredSessions.isEmpty else { return nil }
        return GhostexProjectGroup(
            key: project.key,
            projectId: project.projectId,
            groupId: project.groupId,
            name: project.name,
            path: project.path,
            sessions: filteredSessions,
            sessionGroups: filteredSessionGroups,
            quickActions: project.quickActions,
            isChatCollection: project.isChatCollection
        )
    }

    private func matches(_ session: GhostexRemoteSession, query: String) -> Bool {
        contains(query, in: [
            session.displayTitle,
            session.title,
            session.alias,
            session.projectName,
            session.projectPath,
            session.displayStatus,
            session.status,
            session.activity,
            session.agent,
            session.agentIcon,
            session.providerSessionName,
            session.sessionId,
        ])
    }

    private func contains(_ query: String, in values: [String]) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }

        let haystack = normalizedSearchText(values.joined(separator: " "))
        guard !haystack.isEmpty else { return false }

        return tokens.allSatisfy { token in
            tokenMatches(token, in: haystack)
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func tokenMatches(_ token: String, in haystack: String) -> Bool {
        if haystack.contains(token) {
            return true
        }

        guard token.count >= 3 else {
            return false
        }

        let words = haystack.split(separator: " ").map(String.init)
        if words.contains(where: { fuzzyOrderedMatch(token, in: $0) }) {
            return true
        }

        guard token.count >= 4 else {
            return false
        }

        return fuzzyOrderedMatch(token, in: haystack.replacingOccurrences(of: " ", with: ""))
    }

    private func fuzzyOrderedMatch(_ token: String, in candidate: String) -> Bool {
        guard token.count >= 3, candidate.count >= token.count else {
            return false
        }

        let maxSingleGap = max(2, token.count)
        let maxTotalGap = max(3, token.count * 2)
        var searchStart = candidate.startIndex
        var previousMatch: String.Index?
        var totalGap = 0

        for character in token {
            guard let match = candidate[searchStart...].firstIndex(of: character) else {
                return false
            }

            if let previousMatch {
                let gap = candidate.distance(from: candidate.index(after: previousMatch), to: match)
                guard gap <= maxSingleGap else {
                    return false
                }
                totalGap += gap
            }

            guard totalGap <= maxTotalGap else {
                return false
            }

            previousMatch = match
            searchStart = candidate.index(after: match)
        }

        return true
    }
}

private struct GhostexSessionFilterBar: View {
    @Binding var text: String
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 17, weight: .medium))

            TextField("Filter sessions", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFieldFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear filter")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .onChange(of: text) { newValue in
            guard !newValue.isEmpty else { return }
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        .textCase(nil)
    }
}

private struct GhostexSessionRow: View {
    let session: GhostexRemoteSession

    var body: some View {
        HStack(spacing: 12) {
            GhostexAgentIconView(session: session)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if session.isFocused {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(session.displayStatus)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let agent = session.agent.isEmpty ? "Terminal" : session.agent
        let alias = session.alias.isEmpty ? "#" : session.alias
        return "\(alias) · \(agent) · \(session.projectName)"
    }

    private var statusColor: Color {
        /*
         CDXC:iOSGhostexSidebar 2026-06-12-02:32:
         The rendered Ghostex row status comes from displayStatus, including normalized done and attention states. Done/attention must use #95d7f6 instead of bright green while working remains orange like the macOS and Android status indicators.
         */
        switch session.displayStatus {
        case "attention", "done": return .ghostexDoneAttentionStatus
        case "sleep": return .secondary
        case "working": return .orange
        case "error": return .red
        default: return .primary
        }
    }
}

private struct GhostexAgentIconView: View {
    let session: GhostexRemoteSession

    private var iconId: String {
        GhostexAgentIdentity.resolveIconId(agentIcon: session.agentIcon, agent: session.agent)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(GhostexAgentIdentity.tint(for: iconId).opacity(0.14))

            Image(GhostexAgentIdentity.assetName(for: iconId))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(GhostexAgentIdentity.tint(for: iconId))
                .padding(8)
                .accessibilityHidden(true)
        }
        .frame(width: 38, height: 38)
        .accessibilityLabel(session.agent.isEmpty ? "Terminal" : session.agent)
    }
}

private struct GhostexSessionGroupHeaderRow: View {
    let title: String
    let sessionCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(sessionCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(sessionCount) sessions, \(isCollapsed ? "collapsed" : "expanded")")
    }
}

private struct GhostexLauncherIsle: View {
    let agents: [GhostexAgentLauncher]
    let quickActions: [GhostexQuickAction]
    let onLaunchAgent: (GhostexAgentLauncher) -> Void
    let onRunQuickAction: (GhostexQuickAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(agents) { agent in
                    agentChip(agent)
                }

                if !agents.isEmpty && !quickActions.isEmpty {
                    Divider()
                        .frame(height: 22)
                }

                ForEach(quickActions) { action in
                    quickActionChip(action)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func agentChip(_ agent: GhostexAgentLauncher) -> some View {
        let iconId = GhostexAgentIdentity.resolveIconId(agentIcon: agent.icon, agent: agent.name)
        let tint = GhostexAgentIdentity.tint(for: iconId)
        return Button {
            onLaunchAgent(agent)
        } label: {
            HStack(spacing: 6) {
                Image(GhostexAgentIdentity.assetName(for: iconId))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(agent.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(agent.name) session")
    }

    private func quickActionChip(_ action: GhostexQuickAction) -> some View {
        Button {
            onRunQuickAction(action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.isBrowserAction ? "globe" : "play.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(action.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.isBrowserAction ? "Open \(action.name)" : "Run \(action.name)")
    }
}

private struct GhostexProjectHeader: View {
    let project: GhostexProjectGroup
    let isCollapsed: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggleCollapse: () -> Void
    let onCreate: () -> Void
    let onRefresh: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onWake: () -> Void
    let onSleep: () -> Void
    let onKill: () -> Void
    let onCopyPath: () -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleCollapse) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.subheadline.weight(.bold))
                        Text("\(project.sessions.count) sessions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !project.isChatCollection {
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Menu {
                    Button("Refresh Sessions", systemImage: "arrow.clockwise", action: onRefresh)
                    Button("Wake Project Sessions", systemImage: "sun.max", action: onWake)
                    Button("Sleep Project Sessions", systemImage: "moon", action: onSleep)
                    Button(role: .destructive) {
                        onKill()
                    } label: {
                        Label("Kill Project Sessions", systemImage: "xmark.octagon")
                    }
                    if canMoveUp {
                        Button("Move Project Up", systemImage: "arrow.up", action: onMoveUp)
                    }
                    if canMoveDown {
                        Button("Move Project Down", systemImage: "arrow.down", action: onMoveDown)
                    }
                    Button("Copy Project Path", systemImage: "doc.on.doc", action: onCopyPath)
                    Button("Details", systemImage: "info.circle", action: onDetails)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct GhostexRecentProjectsView: View {
    let projects: [GhostexRecentProject]
    let onRestore: (GhostexRecentProject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(projects) { project in
                Button {
                    onRestore(project)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(project.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(project.sessionCount == 1 ? "1 session" : "\(project.sessionCount) sessions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Restores this project to the active sidebar")
            }
            .navigationTitle("Recent Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct GhostexEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            VStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

private struct GhostexDiagnosticsView: View {
    let logs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logs.isEmpty ? "No Ghostex diagnostics yet." : logs.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = logs.joined(separator: "\n")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}
#endif
