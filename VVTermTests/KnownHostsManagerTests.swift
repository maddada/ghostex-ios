import Foundation
import Testing
@testable import VVTerm

@Suite(.serialized)
@MainActor
struct KnownHostsManagerTests {
    @Test
    func removeDeletesOnlyRequestedHostAndPort() {
        let manager = KnownHostsManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.save(entry: KnownHostsManager.Entry(
            host: "example.com",
            port: 22,
            fingerprint: "SHA256:first",
            keyType: 1,
            addedAt: Date(),
            lastSeenAt: Date()
        ))
        manager.save(entry: KnownHostsManager.Entry(
            host: "example.com",
            port: 2222,
            fingerprint: "SHA256:second",
            keyType: 1,
            addedAt: Date(),
            lastSeenAt: Date()
        ))

        manager.remove(host: "example.com", port: 22)

        #expect(manager.entry(for: "example.com", port: 22) == nil)
        #expect(manager.entry(for: "example.com", port: 2222)?.fingerprint == "SHA256:second")
    }

    @Test
    func removeAllClearsSavedHosts() {
        let manager = KnownHostsManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.save(entry: KnownHostsManager.Entry(
            host: "host.local",
            port: 22,
            fingerprint: "SHA256:host",
            keyType: 1,
            addedAt: Date(),
            lastSeenAt: Date()
        ))

        #expect(manager.entries().count == 1)

        manager.removeAll()

        #expect(manager.entries().isEmpty)
    }
}
