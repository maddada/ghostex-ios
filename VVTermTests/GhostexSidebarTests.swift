import Foundation
import Testing
@testable import VVTerm

struct GhostexSidebarTests {
    @Test
    func parseSessionsAllowsLeadingCommandNoise() throws {
        let output = """
        warning: shell initialized
        {"ok":true,"sessions":[{"sessionId":"s1","alias":"A","title":"Build","projectId":"p1","projectName":"App","projectPath":"/repo/app","status":"working","agent":"codex","agentIcon":"codex","providerSessionName":"zmx-a","attachCommand":"ghostex attach --session-id s1","isFocused":true}]}
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
          {"sessionId":"s1","projectId":"p1","projectName":"App","status":"working"},
          {"sessionId":"s2","projectId":"p1","projectName":"App","status":"sleep"},
          {"sessionId":"s3","projectPath":"/repo/ops","projectName":"Ops","status":"attention"}
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
    func loginShellCommandQuotesNestedArguments() {
        let command = GhostexRemoteCommand.renameSession(
            GhostexRemoteSession(json: [
                "sessionId": "abc'123",
                "title": "Old",
            ])!,
            title: "Bob's Session"
        )

        #expect(command.hasPrefix("/bin/zsh -lc "))
        #expect(command.contains("rename-session"))
        #expect(command.contains("'\"'\"'"))
    }
}
