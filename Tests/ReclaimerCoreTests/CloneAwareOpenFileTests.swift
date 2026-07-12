import Foundation
import XCTest
@testable import ReclaimerCore

final class CloneAwareOpenFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-clone-aware-open-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testSharedHardLinkOpenIdentityIsAllowedWhenPreservedSiblingRemains() throws {
        let preserved = root.appendingPathComponent("preserved-helper")
        let candidate = root.appendingPathComponent("code_sign_clone")
        try Data(repeating: 0x41, count: 32).write(to: preserved)
        try FileManager.default.linkItem(at: preserved, to: candidate)

        let identity = try FilesystemIdentity.capture(at: candidate)
        let status = OpenFileStatus(
            isOpen: true,
            processSummary: ["Google Chrome pid 42"],
            checkedPath: candidate.path,
            openHits: [OpenFileHit(path: preserved.path, fileIdentityKey: identity.fileIdentityKey)]
        )

        let evidence = FilesystemLinkInspector().inspect(
            candidateURL: candidate,
            plannedIdentity: identity,
            openStatus: status,
            selectedPaths: [candidate.path],
            knownPaths: [candidate.path, preserved.path]
        )

        XCTAssertTrue(evidence.sharedOpenIdentityOnly)
        XCTAssertNil(evidence.blockReason)
        XCTAssertEqual(evidence.preservedSiblingPaths, [preserved.path])
        XCTAssertEqual(evidence.openIdentityKeys, [identity.fileIdentityKey].compactMap { $0 })
    }

    func testSharedHardLinkOpenIdentityBlocksWhenAllSiblingsAreSelected() throws {
        let first = root.appendingPathComponent("clone-a")
        let second = root.appendingPathComponent("clone-b")
        try Data(repeating: 0x42, count: 32).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)

        let identity = try FilesystemIdentity.capture(at: first)
        let status = OpenFileStatus(
            isOpen: true,
            checkedPath: first.path,
            openHits: [OpenFileHit(path: second.path, fileIdentityKey: identity.fileIdentityKey)]
        )

        let evidence = FilesystemLinkInspector().inspect(
            candidateURL: first,
            plannedIdentity: identity,
            openStatus: status,
            selectedPaths: [first.path, second.path],
            knownPaths: [first.path, second.path]
        )

        XCTAssertFalse(evidence.sharedOpenIdentityOnly)
        XCTAssertTrue(evidence.blockReason?.localizedCaseInsensitiveContains("preserved") ?? false)
    }

    func testUniqueOpenIdentityBlocksEvenWhenAnotherSiblingIsPreserved() throws {
        let preserved = root.appendingPathComponent("preserved")
        let candidate = root.appendingPathComponent("candidate")
        let unique = root.appendingPathComponent("unique-open")
        try Data(repeating: 0x43, count: 32).write(to: preserved)
        try FileManager.default.linkItem(at: preserved, to: candidate)
        try Data(repeating: 0x44, count: 16).write(to: unique)

        let identity = try FilesystemIdentity.capture(at: candidate)
        let uniqueIdentity = try FilesystemIdentity.capture(at: unique)
        let status = OpenFileStatus(
            isOpen: true,
            checkedPath: candidate.path,
            openHits: [
                OpenFileHit(path: preserved.path, fileIdentityKey: identity.fileIdentityKey),
                OpenFileHit(path: unique.path, fileIdentityKey: uniqueIdentity.fileIdentityKey)
            ]
        )

        let evidence = FilesystemLinkInspector().inspect(
            candidateURL: candidate,
            plannedIdentity: identity,
            openStatus: status,
            selectedPaths: [candidate.path],
            knownPaths: [candidate.path, preserved.path, unique.path]
        )

        XCTAssertFalse(evidence.sharedOpenIdentityOnly)
        XCTAssertTrue(evidence.blockReason?.localizedCaseInsensitiveContains("unique") ?? false)
    }

    func testFailedHitIdentityResolutionBlocksConservatively() throws {
        let preserved = root.appendingPathComponent("preserved")
        let candidate = root.appendingPathComponent("candidate")
        try Data(repeating: 0x45, count: 32).write(to: preserved)
        try FileManager.default.linkItem(at: preserved, to: candidate)

        let identity = try FilesystemIdentity.capture(at: candidate)
        let status = OpenFileStatus(
            isOpen: true,
            checkedPath: candidate.path,
            openHits: [OpenFileHit(path: preserved.path, fileIdentityKey: nil, identityResolutionFailed: true)]
        )

        let evidence = FilesystemLinkInspector().inspect(
            candidateURL: candidate,
            plannedIdentity: identity,
            openStatus: status,
            selectedPaths: [candidate.path],
            knownPaths: [candidate.path, preserved.path]
        )

        XCTAssertTrue(evidence.blockReason?.localizedCaseInsensitiveContains("identity") ?? false)
    }

    func testChangedHardLinkCountBlocksBeforePerform() throws {
        let sibling = root.appendingPathComponent("sibling")
        let candidate = root.appendingPathComponent("candidate")
        try Data(repeating: 0x46, count: 32).write(to: sibling)
        try FileManager.default.linkItem(at: sibling, to: candidate)
        let plannedIdentity = try FilesystemIdentity.capture(at: candidate)
        try FileManager.default.removeItem(at: sibling)

        let currentIdentity = try FilesystemIdentity.capture(at: candidate)
        XCTAssertNotEqual(plannedIdentity.hardLinkCount, currentIdentity.hardLinkCount)

        let evidence = FilesystemLinkInspector().inspect(
            candidateURL: candidate,
            plannedIdentity: plannedIdentity,
            openStatus: OpenFileStatus(isOpen: false, checkedPath: candidate.path),
            selectedPaths: [candidate.path],
            knownPaths: [candidate.path]
        )

        XCTAssertTrue(evidence.blockReason?.localizedCaseInsensitiveContains("identity") ?? false)
    }

    func testSymlinkAndRecursiveOpenFailureBlock() throws {
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("link")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let symlinkEvidence = FilesystemLinkInspector().inspect(
            candidateURL: link,
            plannedIdentity: nil,
            openStatus: OpenFileStatus(isOpen: false, checkedPath: link.path),
            selectedPaths: [link.path],
            knownPaths: [link.path]
        )
        XCTAssertTrue(symlinkEvidence.blockReason?.localizedCaseInsensitiveContains("symbolic") ?? false)

        let directory = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recursiveFailure = FilesystemLinkInspector().inspect(
            candidateURL: directory,
            plannedIdentity: nil,
            openStatus: OpenFileStatus(
                isOpen: false,
                checkFailed: "permission denied",
                checkedRecursively: true,
                checkedPath: directory.path
            ),
            selectedPaths: [directory.path],
            knownPaths: [directory.path]
        )
        XCTAssertTrue(recursiveFailure.blockReason?.localizedCaseInsensitiveContains("open-file") ?? false)
    }

    func testPlanBuilderRequiresRecursiveEvidenceForDirectory() throws {
        let directory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x47, count: 16).write(to: directory.appendingPathComponent("cache.bin"))
        let finding = Finding(
            scopeName: "Fixture",
            path: directory.path,
            displayName: directory.lastPathComponent,
            logicalSize: 16,
            allocatedSize: 16,
            isDirectory: true,
            filesystemIdentity: try FilesystemIdentity.capture(at: directory),
            safetyClass: .autoSafe,
            actionKind: .deleteCache,
            ruleMatches: [],
            evidence: [],
            openFileStatus: OpenFileStatus(isOpen: false, checkedRecursively: false, checkedPath: directory.path)
        )

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [finding])
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertFalse(item.selected)
        XCTAssertTrue(item.conditions.contains {
            $0.kind == .recursiveOpenFileClear && !$0.isSatisfied
        })
    }
}
