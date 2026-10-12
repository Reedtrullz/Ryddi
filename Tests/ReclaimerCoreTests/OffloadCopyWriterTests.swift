import XCTest
@testable import ReclaimerCore

final class OffloadCopyWriterTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var provider: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        source = root.appendingPathComponent("original")
        provider = root.appendingPathComponent("provider")
        try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testProviderReplacementDoesNotDeleteForeignDestination() throws {
        let originalProvider = provider!, moved = root.appendingPathComponent("moved-provider")
        let sourceIdentity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let providerIdentity = try XCTUnwrap(FileIdentity.capture(path: provider.path))
        let writer = OffloadCopyWriter(copyOperation: { source, destination in
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.moveItem(at: originalProvider, to: moved)
            try FileManager.default.createDirectory(at: originalProvider, withIntermediateDirectories: false)
            try Data("foreign".utf8).write(to: originalProvider.appendingPathComponent("copy"))
        })
        XCTAssertThrowsError(try writer.copy(source: source, sourceIdentity: sourceIdentity,
                                             provider: provider, providerIdentity: providerIdentity, name: "copy"))
        XCTAssertEqual(try String(contentsOf: provider.appendingPathComponent("copy"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    private func performCopy(_ writer: OffloadCopyWriter = OffloadCopyWriter(), name: String = "copy") throws -> URL {
        try writer.copy(source: source, sourceIdentity: XCTUnwrap(FileIdentity.capture(path: source.path)),
                        provider: provider, providerIdentity: XCTUnwrap(FileIdentity.capture(path: provider.path)), name: name)
    }

    func testFileCopyPublishesAndRemovesOnlyEmptyOwnedStaging() throws {
        let destination = try performCopy()
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: provider.path), ["copy"])
    }

    func testDirectoryCopyPreservesOriginalChildren() throws {
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: source.appendingPathComponent("child"))
        let destination = try performCopy()
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("child"), encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("child"), encoding: .utf8), "original")
    }

    func testExistingDestinationIsPreservedWithoutCopying() throws {
        let destination = provider.appendingPathComponent("copy")
        try Data("foreign".utf8).write(to: destination)
        XCTAssertThrowsError(try performCopy(OffloadCopyWriter(copyOperation: { _, _ in XCTFail("Must not copy") })))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "foreign")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: provider.path), ["copy"])
    }

    func testFinalNameCollisionAfterCopyKeepsForeignAndPartial() throws {
        let destination = provider.appendingPathComponent("copy")
        let writer = OffloadCopyWriter(checkpoint: { point, _ in
            if point == "copied" { try Data("foreign".utf8).write(to: destination) }
        })
        XCTAssertThrowsError(try performCopy(writer)) {
            guard case .retained(_, let path) = $0 as? OffloadCopyError else { return XCTFail("Missing retained location") }
            XCTAssertEqual(try? String(contentsOfFile: path, encoding: .utf8), "original")
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testFailedCopyRetainsPartialAndReportsLocationAndReason() throws {
        struct ExpectedFailure: LocalizedError { var errorDescription: String? { "fixture copy failure" } }
        let writer = OffloadCopyWriter(copyOperation: { _, destination in
            try Data("partial".utf8).write(to: destination)
            throw ExpectedFailure()
        })
        XCTAssertThrowsError(try performCopy(writer)) {
            guard case .retained(let reason, let path) = $0 as? OffloadCopyError else { return XCTFail("Missing retained location") }
            XCTAssertEqual(reason, "fixture copy failure")
            XCTAssertEqual(try? String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("payload"), encoding: .utf8), "partial")
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: provider.appendingPathComponent("copy").path))
    }

    func testPayloadReplacementIsNotPublishedOrDeleted() throws {
        let saved = root.appendingPathComponent("saved")
        let writer = OffloadCopyWriter(checkpoint: { point, url in
            if point == "copied" {
                try FileManager.default.moveItem(at: url, to: saved)
                try Data("foreign".utf8).write(to: url)
            }
        })
        XCTAssertThrowsError(try performCopy(writer)) {
            XCTAssertTrue($0.localizedDescription.contains(saved.path))
        }
        let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: provider, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: staging.appendingPathComponent("payload"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testProviderSymlinkReplacementBeforeCopyPreservesForeignRoot() throws {
        let originalProvider = provider!, moved = root.appendingPathComponent("moved-provider")
        let foreign = root.appendingPathComponent("foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try Data("foreign".utf8).write(to: foreign.appendingPathComponent("copy"))
        let writer = OffloadCopyWriter(copyOperation: { _, _ in XCTFail("Must not copy") }, checkpoint: { point, _ in
            if point == "reserved" {
                try FileManager.default.moveItem(at: originalProvider, to: moved)
                try FileManager.default.createSymbolicLink(at: originalProvider, withDestinationURL: foreign)
            }
        })
        XCTAssertThrowsError(try performCopy(writer)) { XCTAssertTrue($0.localizedDescription.contains(moved.path)) }
        XCTAssertEqual(try String(contentsOf: foreign.appendingPathComponent("copy"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testStagingReplacementCannotBeDeletedAsOwned() throws {
        let saved = root.appendingPathComponent("saved-staging")
        let writer = OffloadCopyWriter(checkpoint: { point, url in
            if point == "copied" {
                let directory = url.deletingLastPathComponent()
                try FileManager.default.moveItem(at: directory, to: saved)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                try Data("foreign".utf8).write(to: url)
            }
        })
        XCTAssertThrowsError(try performCopy(writer)) { XCTAssertTrue($0.localizedDescription.contains(saved.path)) }
        let replacement = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: provider, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: replacement.appendingPathComponent("payload"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: saved.appendingPathComponent("payload"), encoding: .utf8), "original")
    }

    func testProviderReplacementAfterPublishIsNotAcceptedOrRemoved() throws {
        let originalProvider = provider!, moved = root.appendingPathComponent("moved-provider")
        let writer = OffloadCopyWriter(checkpoint: { point, _ in
            if point == "published" {
                try FileManager.default.moveItem(at: originalProvider, to: moved)
                try FileManager.default.createDirectory(at: originalProvider, withIntermediateDirectories: false)
                try Data("foreign".utf8).write(to: originalProvider.appendingPathComponent("copy"))
            }
        })
        XCTAssertThrowsError(try performCopy(writer)) { XCTAssertTrue($0.localizedDescription.contains(moved.appendingPathComponent("copy").path)) }
        XCTAssertEqual(try String(contentsOf: provider.appendingPathComponent("copy"), encoding: .utf8), "foreign")
        XCTAssertEqual(try String(contentsOf: moved.appendingPathComponent("copy"), encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testEmptyForeignStagingReplacementIsNotRemovedAfterSuccess() throws {
        let currentProvider = provider!, saved = root.appendingPathComponent("owned-empty-staging")
        let writer = OffloadCopyWriter(checkpoint: { point, _ in
            if point == "published" {
                let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: currentProvider, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".ryddi-copy-") })
                try FileManager.default.moveItem(at: staging, to: saved)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            }
        })
        let destination = try performCopy(writer)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: provider.path)
            .filter { $0.hasPrefix(".ryddi-copy-") }.count, 1)
    }

    func testCopyIntoSourceIsRefusedBeforeReservingDestination() throws {
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let nested = source.appendingPathComponent("provider")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        XCTAssertThrowsError(try OffloadCopyWriter().copy(source: source,
            sourceIdentity: XCTUnwrap(FileIdentity.capture(path: source.path)), provider: nested,
            providerIdentity: XCTUnwrap(FileIdentity.capture(path: nested.path)), name: "copy"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: nested.path).isEmpty)
    }

    func testTraversalNameIsRefused() throws {
        XCTAssertThrowsError(try performCopy(name: "../foreign"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: provider.path).isEmpty)
    }
}
