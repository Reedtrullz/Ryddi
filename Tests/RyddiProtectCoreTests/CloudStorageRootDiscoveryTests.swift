import Foundation
import XCTest
@testable import RyddiProtectCore

final class CloudStorageRootDiscoveryTests: XCTestCase {
    func testDiscoversImmediateProviderRootsWithoutTraversingContents() throws {
        let home = try temporaryDirectory()
        let cloud = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let dropbox = cloud.appendingPathComponent("Dropbox", isDirectory: true)
        let google = cloud.appendingPathComponent("GoogleDrive-example", isDirectory: true)
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: google, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: dropbox.appendingPathComponent("must-not-be-read.txt"))

        let report = CloudStorageRootDiscovery().discover(home: home)

        XCTAssertEqual(report.candidates.map(\.provider), [.dropbox, .googleDrive])
        XCTAssertTrue(report.candidates.allSatisfy(\.requiresConfirmation))
        XCTAssertTrue(report.nonClaims.contains { $0.contains("does not traverse") })
    }

    func testRejectsSymlinkAndAcceptsExplicitMegaDirectoryAsUnconfirmedCandidate() throws {
        let home = try temporaryDirectory()
        let cloud = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let target = home.appendingPathComponent("real-dropbox", isDirectory: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: cloud.appendingPathComponent("Dropbox"),
            withDestinationURL: target
        )
        let mega = home.appendingPathComponent("My MEGA Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: mega, withIntermediateDirectories: true)

        let report = CloudStorageRootDiscovery().discover(home: home, userSelectedMegaRoots: [mega])

        XCTAssertEqual(report.rejectedSymlinks.count, 1)
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates.first?.provider, .mega)
        XCTAssertEqual(report.candidates.first?.origin, .userSelected)
    }

    func testProviderRecognitionRequiresKnownNameBoundary() {
        XCTAssertEqual(CloudStorageRootDiscovery.provider(forRootName: "Dropbox"), .dropbox)
        XCTAssertEqual(CloudStorageRootDiscovery.provider(forRootName: "Dropbox-Personal"), .dropbox)
        XCTAssertEqual(CloudStorageRootDiscovery.provider(forRootName: "GoogleDrive-user"), .googleDrive)
        XCTAssertNil(CloudStorageRootDiscovery.provider(forRootName: "NotDropbox"))
        XCTAssertNil(CloudStorageRootDiscovery.provider(forRootName: "DropboxArchive"))
        XCTAssertNil(CloudStorageRootDiscovery.provider(forRootName: "GoogleDriveBackup"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
