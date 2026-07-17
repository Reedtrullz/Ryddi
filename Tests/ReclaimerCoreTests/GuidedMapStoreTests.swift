import XCTest
@testable import ReclaimerCore

final class GuidedMapStoreTests: XCTestCase {
    func testRoundTripAndNewestValidSnapshotWins() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuidedMapStore(root: root)
        try store.save(snapshot(id: "old", date: 1))
        try store.save(snapshot(id: "new", date: 2))
        XCTAssertEqual(store.latest()?.scanID, "new")
        XCTAssertEqual(store.recent(limit: 1).map(\.scanID), ["new"])
    }

    func testCorruptAndSymlinkFilesAreIgnored() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuidedMapStore(root: root)
        let validURL = try store.save(snapshot(id: "valid", date: 1))
        try Data("not-json".utf8).write(to: root.appendingPathComponent("guided-map-new-corrupt.json"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("guided-map-link.json"),
            withDestinationURL: validURL
        )
        XCTAssertEqual(store.latest()?.scanID, "valid")
    }

    func testPrivatePermissions() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try GuidedMapStore(root: root).save(snapshot(id: "private", date: 1))
        let rootMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(rootMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)
    }

    func testSymbolicLinkRootIsRejected() throws {
        let parent = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let link = parent.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try GuidedMapStore(root: link).save(snapshot(id: "unsafe", date: 1))) { error in
            XCTAssertEqual(error as? GuidedMapStoreError, .unsafeRoot)
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-guided-map-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func snapshot(id: String, date: TimeInterval) -> GuidedMapSnapshot {
        GuidedMapSnapshot(
            scanID: id,
            capturedAt: Date(timeIntervalSince1970: date),
            scopeDescription: "Test",
            volumeCapacityBytes: 100,
            volumeAvailableBytes: 50,
            measuredAllocatedBytes: 50,
            evidenceState: .complete,
            rootID: "root",
            nodes: []
        )
    }
}
