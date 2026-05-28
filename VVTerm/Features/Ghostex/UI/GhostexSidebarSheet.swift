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

struct GhostexSidebarSheet: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var sessionManager: ConnectionSessionManager
    @ObservedObject var store: GhostexSidebarStore
    let onOpenTerminal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detailSession: GhostexRemoteSession?
    @State private var detailProject: GhostexProjectGroup?
    @State private var renamingSession: GhostexRemoteSession?
    @State private var renameTitle = ""
    @State private var showingLogs = false

    private var selectedServer: Server? {
        store.selectedServer(from: serverManager.servers)
    }

    var body: some View {
        NavigationStack {
            List {
                hostSection
                sessionsSection
                diagnosticsSection
            }
            .navigationTitle("Ghostex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        store.refresh(using: serverManager)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing || selectedServer == nil)

                    Button {
                        showingLogs = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
            }
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
                    title: Text(session.title),
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
    }

    private var hostSection: some View {
        Section {
            if serverManager.servers.isEmpty {
                GhostexEmptyState(
                    title: "No Servers",
                    systemImage: "server.rack",
                    description: "Add a VVTerm server for the Mac that runs the Ghostex CLI."
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
            }
        } header: {
            Text("Machine")
        } footer: {
            Text("Ghostex uses the selected VVTerm server and its Keychain credentials to run the Mac-hosted Ghostex CLI.")
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if store.projectGroups.isEmpty {
            Section("Sessions") {
                if store.isRefreshing {
                    ProgressView("Loading sessions")
                } else {
                    GhostexEmptyState(
                        title: "No Sessions",
                        systemImage: "rectangle.stack",
                        description: "Refresh after selecting the Ghostex host."
                    )
                }
            }
        } else {
            ForEach(Array(store.projectGroups.enumerated()), id: \.element.id) { index, project in
                Section {
                    ForEach(project.sessions) { session in
                        GhostexSessionRow(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                attach(session)
                            }
                            .contextMenu {
                                sessionMenu(session)
                            }
                    }
                } header: {
                    GhostexProjectHeader(
                        project: project,
                        canMoveUp: index > 0,
                        canMoveDown: index < store.projectGroups.count - 1,
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

    private var diagnosticsSection: some View {
        Section {
            Button {
                showingLogs = true
            } label: {
                Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
            }

            if store.isRunningAction {
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
                dismiss()
                onOpenTerminal()
            } catch {
                store.reportError(error)
            }
        }
    }

    private func createAndAttachSession(in project: GhostexProjectGroup) {
        Task {
            do {
                try await store.createSession(in: project, using: serverManager, sessionManager: sessionManager)
                dismiss()
                onOpenTerminal()
            } catch {
                store.reportError(error)
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
}

private struct GhostexSessionRow: View {
    let session: GhostexRemoteSession

    var body: some View {
        HStack(spacing: 12) {
            GhostexAgentIconView(session: session)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.title)
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
        switch session.status {
        case "attention": return .orange
        case "sleep": return .secondary
        case "working": return .green
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

private struct GhostexProjectHeader: View {
    let project: GhostexProjectGroup
    let canMoveUp: Bool
    let canMoveDown: Bool
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
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.bold))
                Text("\(project.sessions.count) sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
