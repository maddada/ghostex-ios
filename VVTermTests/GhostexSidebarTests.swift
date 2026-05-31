import Foundation
import Testing
@testable import VVTerm

struct GhostexSidebarTests {
    @Test
    func parseSessionsAllowsLeadingCommandNoise() throws {
        let output = """
        warning: shell initialized
        {"ok":true,"sessions":[{"sessionId":"s1","alias":"A","title":"Build","projectId":"p1","projectName":"App","projectPath":"/repo/app","status":"working","provider":"zmx","agent":"codex","agentIcon":"codex","providerSessionName":"zmx-a","attachCommand":"ghostex attach --session-id s1","isFocused":true}]}
        """

        let sessions = try GhostexRemoteSession.parseList(from: Data(output.utf8))

        #expect(sessions.count == 1)
        #expect(sessions[0].sessionId == "s1")
        #expect(sessions[0].projectName == "App")
        #expect(sessions[0].isFocused)
    }

    @Test
    func groupsSessionsByProjectContract() throws {
        let output = """
        {"sessions":[
          {"sessionId":"s1","projectId":"p1","projectName":"App","status":"working","provider":"zmx"},
          {"sessionId":"s2","projectId":"p1","projectName":"App","status":"sleep","provider":"zmx"},
          {"sessionId":"s3","projectPath":"/repo/ops","projectName":"Ops","status":"attention","provider":"zmx"}
        ]}
        """

        let sessions = try GhostexRemoteSession.parseList(from: Data(output.utf8))
        let groups = GhostexProjectGroup.groups(from: sessions)

        #expect(groups.map(\.name) == ["App", "Ops"])
        #expect(groups[0].sessions.map(\.sessionId) == ["s1", "s2"])
        #expect(groups[0].workingCount == 1)
        #expect(groups[0].sleepingCount == 1)
        #expect(groups[1].attentionCount == 1)
    }

    @Test
    func providerBackedSessionDoesNotUseLegacySleepingStatus() throws {
        /*
        CDXC:iOSGhostexSidebar 2026-05-29-09:20:
        A zmx provider session can exist without a Mac native pane. The iOS
        sidebar must treat that projected resource state as live instead of
        trusting the legacy sleeping flag.
        */
        let output = """
        {"sessions":[{"sessionId":"s1","projectId":"p1","projectName":"App","status":"sleep","provider":"zmx","isSleeping":true,"nativePaneState":"unmounted","providerSessionState":"exists","isLive":true}]}
        """

        let sessions = try GhostexRemoteSession.parseList(from: Data(output.utf8))

        #expect(sessions.count == 1)
        #expect(sessions[0].isLive)
        #expect(!sessions[0].isSleeping)
        #expect(sessions[0].displayStatus == "idle")
        #expect(GhostexProjectGroup.groups(from: sessions)[0].sleepingCount == 0)
    }

    @Test
    func disabledProviderStateIsNotUnknown() {
        /*
        CDXC:iOSGhostexSidebar 2026-05-29-06:29:
        Disabled persistence is an explicit Mac-side configuration. Keep it as
        `persistence-disabled` instead of collapsing it into unknown provider
        state.
        */
        let session = GhostexRemoteSession(json: [
            "sessionId": "s1",
            "projectId": "p1",
            "projectName": "App",
            "status": "running",
            "providerSessionState": "persistence-disabled",
            "nativePaneState": "mounted",
        ])

        #expect(session?.providerSessionState == "persistence-disabled")
        #expect(session?.isLive == true)
        #expect(session?.displayStatus == "idle")
    }

    @Test
    func agentIdentityPrefersExplicitKnownIcon() {
        let icon = GhostexAgentIdentity.resolveIconId(agentIcon: "claude", agent: "Codex")
        #expect(icon == "claude")
    }

    @Test
    func agentIdentityFallsBackFromAgentName() {
        #expect(GhostexAgentIdentity.resolveIconId(agentIcon: "", agent: "Cursor Agent") == "cursor-cli")
        #expect(GhostexAgentIdentity.resolveIconId(agentIcon: "", agent: "unknown") == "terminal")
    }

    @Test
    func parseSessionsFiltersNonZmxProviders() throws {
        let output = """
        {"sessions":[
          {"sessionId":"z1","provider":"zmx","projectName":"App"},
          {"sessionId":"t1","provider":"tmux","projectName":"App"},
          {"sessionId":"o1","sessionPersistenceProvider":"off","projectName":"App"}
        ]}
        """

        let sessions = try GhostexRemoteSession.parseList(from: Data(output.utf8))

        #expect(sessions.map(\.sessionId) == ["z1"])
    }

    @Test
    func zmxViewportRefreshSequenceMatchesAndroidContract() {
        #expect(GhostexZmxViewportRefresh.sequence == "\u{001B}]1337;ZMX_REFRESH\u{0007}")
    }

    @Test
    func parseSessionsScansPastBraceNoise() throws {
        let output = """
        profile loaded {not json}
        warning {still not json
        {"ok":true,"sessions":[{"sessionId":"s1","provider":"zmx","status":"needs_attention"}]}
        """

        let sessions = try GhostexRemoteSession.parseList(from: Data(output.utf8))

        #expect(sessions.count == 1)
        #expect(sessions[0].displayStatus == "attention")
    }

    @Test
    func createSessionCommandRequestsJson() {
        let project = GhostexProjectGroup(
            key: "p1",
            projectId: "p1",
            groupId: "g1",
            name: "App",
            path: "/repo/app",
            sessions: []
        )

        let command = GhostexRemoteCommand.createSession(project: project)

        #expect(command.contains("ghostex create-session --json"))
        #expect(command.contains("--project-id"))
        #expect(command.contains("--group-id"))
    }

    @Test
    func createSessionResultParsesCreatedSessionId() {
        let output = """
        shell notice
        {"ok":true,"session":{"sessionId":"created-123"}}
        """

        #expect(GhostexCreateSessionResult.createdSessionId(from: output) == "created-123")
    }

    @Test
    func createSessionResultPrefersGhostexListIdentity() {
        let output = """
        {"ok":true,"session":{"ghostexId":"combined-session:project-1:g-1","sessionId":"g-1"}}
        """

        #expect(GhostexCreateSessionResult.createdSessionId(from: output) == "combined-session:project-1:g-1")
    }

    @Test
    func loginShellCommandQuotesNestedArguments() {
        let command = GhostexRemoteCommand.renameSession(
            GhostexRemoteSession(json: [
                "sessionId": "abc'123",
                "projectId": "p1",
                "title": "Old",
                "provider": "zmx",
            ])!,
            title: "Bob's Session"
        )

        #expect(command.hasPrefix("/bin/zsh -lc "))
        #expect(command.contains("rename-session"))
        #expect(command.contains("--project-id"))
        #expect(command.contains("'\"'\"'"))
    }

    @Test
    func sessionActionIncludesProjectIdWhenAvailable() {
        let session = GhostexRemoteSession(json: [
            "sessionId": "s1",
            "projectId": "p1",
            "title": "Work",
            "provider": "zmx",
        ])!

        let command = GhostexRemoteCommand.sessionAction("sleep", session: session)

        #expect(command.contains("ghostex sleep --session-id"))
        #expect(command.contains("--project-id"))
        #expect(command.contains("--json"))
    }
}
