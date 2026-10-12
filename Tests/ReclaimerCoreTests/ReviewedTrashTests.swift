import XCTest
import Darwin
@testable import ReclaimerCore

final class ReviewedTrashTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var trash: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        source = root.appendingPathComponent("reviewed")
        trash = root.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("reviewed".utf8).write(to: source)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReviewedDirectoryCanUseBoundedHandoff() throws {
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("retained".utf8).write(to: source.appendingPathComponent("child"))
        let destination = trash!
        let recovery = try SessionTrashMover(trashDirectory: { _ in destination }).moveValidatedFileToTrash(
            source: source, scannedIdentity: try XCTUnwrap(FileIdentity.capture(path: source.path)))
        let received = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(recovery.resolvingSymlinksInPath().path, received.resolvingSymlinksInPath().path)
        XCTAssertEqual(try String(contentsOf: received.appendingPathComponent("child"), encoding: .utf8), "retained")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testReplacementBetweenOpeningAndStagingIsKept() throws {
        let original = source!, destination = trash!, saved = root.appendingPathComponent("saved")
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "opened" {
                try FileManager.default.moveItem(at: original, to: saved)
                try Data("replacement".utf8).write(to: original)
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "reviewed")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testFIFOReplacementIsRejectedWithoutWaitingForWriter() throws {
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path)), destination = trash!
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("saved"))
        XCTAssertEqual(mkfifo(source.path, mode_t(0o600)), 0)
        XCTAssertThrowsError(try SessionTrashMover(trashDirectory: { _ in destination }).moveValidatedFileToTrash(
            source: source, scannedIdentity: identity))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testDirectoryReplacementBeforeStagePreservesBothDirectories() throws {
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("reviewed".utf8).write(to: source.appendingPathComponent("child"))
        let original = source!, destination = trash!, saved = root.appendingPathComponent("saved")
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "opened" {
                try FileManager.default.moveItem(at: original, to: saved)
                try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
                try Data("foreign".utf8).write(to: original.appendingPathComponent("child"))
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity))
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("child"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: saved.appendingPathComponent("child"), encoding: .utf8), "reviewed")
    }

    func testSymlinkReplacementDoesNotMoveItsTarget() throws {
        let original = source!, destination = trash!, saved = root.appendingPathComponent("saved")
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "opened" {
                try FileManager.default.moveItem(at: original, to: saved)
                try FileManager.default.createSymbolicLink(at: original, withDestinationURL: saved)
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity))
        XCTAssertTrue(FileIdentity.capture(path: source.path)?.isSymbolicLink == true)
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "reviewed")
    }

    func testParentRedirectionAfterStagingReportsActualRecoveryLocation() throws {
        let parent = root.appendingPathComponent("parent"), renamed = root.appendingPathComponent("renamed")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let original = parent.appendingPathComponent("reviewed")
        try FileManager.default.moveItem(at: source, to: original)
        let destination = trash!, identity = try XCTUnwrap(FileIdentity.capture(path: original.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "staged" {
                try FileManager.default.moveItem(at: parent, to: renamed)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                try Data("foreign".utf8).write(to: original)
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: original, scannedIdentity: identity)) {
            XCTAssertTrue($0.localizedDescription.contains(renamed.appendingPathComponent("reviewed").path))
        }
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: renamed.appendingPathComponent("reviewed"), encoding: .utf8), "reviewed")
    }

    func testChangedReviewedSessionIsRejectedBeforeMove() throws {
        let reviewed = try XCTUnwrap(SessionFileFingerprint.capture(path: source.path)), destination = trash!
        try Data("new generation".utf8).write(to: source)
        XCTAssertThrowsError(try SessionTrashMover(trashDirectory: { _ in destination }).moveValidatedFileToTrash(
            source: source, scannedIdentity: reviewed.identity, reviewedFingerprint: reviewed))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new generation")
    }

    func testStagedReplacementIsRetainedWithoutMovingForeignObject() throws {
        let destination = trash!, saved = root.appendingPathComponent("saved")
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, url in
            if point == "staged" {
                try FileManager.default.moveItem(at: url, to: saved)
                try Data("foreign".utf8).write(to: url)
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity)) {
            XCTAssertTrue($0.localizedDescription.contains(saved.path))
        }
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "reviewed")
        let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix(".ryddi-trash-") })
        XCTAssertEqual(try String(contentsOf: staging.appendingPathComponent("reviewed"), encoding: .utf8), "foreign")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testAncestorSymlinkRedirectionBeforeStageIsRefused() throws {
        let parent = root.appendingPathComponent("parent"), renamed = root.appendingPathComponent("renamed")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let original = parent.appendingPathComponent("reviewed")
        try FileManager.default.moveItem(at: source, to: original)
        let destination = trash!, identity = try XCTUnwrap(FileIdentity.capture(path: original.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "opened" {
                try FileManager.default.moveItem(at: parent, to: renamed)
                try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: renamed)
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: original, scannedIdentity: identity))
        XCTAssertEqual(try String(contentsOf: renamed.appendingPathComponent("reviewed"), encoding: .utf8), "reviewed")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testSessionGenerationChangedAtTrashRollsBack() throws {
        let destination = trash!, reviewed = try XCTUnwrap(SessionFileFingerprint.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, url in
            if point == "trashed" { try Data("new generation".utf8).write(to: url) }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: reviewed.identity, reviewedFingerprint: reviewed))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new generation")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testInPlaceSessionChangeAfterOpeningIsKept() throws {
        let original = source!, destination = trash!, reviewed = try XCTUnwrap(SessionFileFingerprint.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "opened" { try Data("new generation".utf8).write(to: original) }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: reviewed.identity, reviewedFingerprint: reviewed))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new generation")
    }

    func testInPlaceSessionChangeAfterStagingRollsBack() throws {
        let destination = trash!, reviewed = try XCTUnwrap(SessionFileFingerprint.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, url in
            if point == "staged" { try Data("new generation".utf8).write(to: url) }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: reviewed.identity, reviewedFingerprint: reviewed))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new generation")
    }

    func testRollbackDoesNotOverwriteReplacementAndReportsStagedItem() throws {
        let original = source!, destination = trash!, identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "staged" { try Data("foreign".utf8).write(to: original); throw SessionTrashError.trashFailed }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity)) {
            guard case .retained(let path) = $0 as? SessionTrashError else { return XCTFail("Missing recovery location") }
            XCTAssertEqual(try? String(contentsOfFile: path, encoding: .utf8), "reviewed")
            XCTAssertTrue(path.contains(".ryddi-trash-"))
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "foreign")
    }

    func testTrashParentReplacementRollsBackWithoutTouchingForeignContents() throws {
        let destination = trash!, moved = root.appendingPathComponent("renamed-trash")
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in destination }, checkpoint: { point, _ in
            if point == "trashed" {
                try FileManager.default.moveItem(at: destination, to: moved)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                try Data("foreign".utf8).write(to: destination.appendingPathComponent("foreign"))
            }
        })
        XCTAssertThrowsError(try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "reviewed")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("foreign"), encoding: .utf8), "foreign")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }
}
