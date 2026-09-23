import Foundation
import Testing
@testable import StatsyKit

@Suite("Target selection")
struct TargetSelectionTests {
    /// A fresh selection file in a directory that goes away with the test.
    private func temporarySelection() -> (TargetSelection, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("statsy-\(UUID().uuidString)", isDirectory: true)
        return (TargetSelection(url: directory.appendingPathComponent("target")), directory)
    }

    @Test("reads back what it wrote")
    func roundTrip() throws {
        let (selection, directory) = temporarySelection()
        defer { try? FileManager.default.removeItem(at: directory) }

        try selection.write(TargetRegistry.homelabAI1)
        #expect(selection.read().id == "homelab-ai-1")

        try selection.write(TargetRegistry.local)
        #expect(selection.read().id == "local")
    }

    @Test("falls back to local when nothing has been chosen")
    func missingFile() {
        let (selection, _) = temporarySelection()
        #expect(selection.read().id == "local")
    }

    @Test("falls back to local when the recorded target no longer exists")
    func unknownTarget() throws {
        let (selection, directory) = temporarySelection()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "homelab-99\n".write(to: selection.url, atomically: true, encoding: .utf8)
        #expect(selection.read().id == "local")
    }

    @Test("tolerates surrounding whitespace in the file")
    func whitespace() throws {
        let (selection, directory) = temporarySelection()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "  homelab-ai-1  \n\n".write(to: selection.url, atomically: true, encoding: .utf8)
        #expect(selection.read().id == "homelab-ai-1")
    }

    @Test("every registered target has a distinct id")
    func distinctIdentifiers() {
        let ids = TargetRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("the remote target forwards to the address its exporter is bound to")
    func exporterBinding() throws {
        let remote = try #require(TargetRegistry.homelabAI1.remote)
        // Bound to the LAN address, not loopback: a forward to 127.0.0.1 on
        // that host would connect to nothing.
        #expect(remote.exporterHost == "192.168.68.88")
        #expect(remote.exporterPort == 9100)
        #expect(remote.metricsURL?.absoluteString == "http://127.0.0.1:19100/metrics")
    }

    @Test("strix resolves, binds its exporter to its LAN address, and owns its own tunnel port")
    func strixResolves() throws {
        let target = try #require(TargetRegistry.target(id: "strix"))
        let remote = try #require(target.remote)
        // Same bind pattern as ai-1: the exporter listens on the LAN address,
        // so the tunnel lands on it from inside the host.
        #expect(remote.sshUser == "steve")
        #expect(remote.sshHost == "192.168.68.63")
        #expect(remote.exporterHost == "192.168.68.63")
        #expect(remote.exporterPort == 9100)
        #expect(remote.localPort == 19163)
        #expect(remote.localPort != TargetRegistry.homelabAI1.remote?.localPort)
        #expect(remote.metricsURL?.absoluteString == "http://127.0.0.1:19163/metrics")
    }

    @Test("strix declares unified memory; ai-1 stays discrete")
    func unifiedMemoryDeclaration() throws {
        #expect(try #require(TargetRegistry.strix.remote).unifiedMemory)
        #expect(!(try #require(TargetRegistry.homelabAI1.remote).unifiedMemory))
    }
}
