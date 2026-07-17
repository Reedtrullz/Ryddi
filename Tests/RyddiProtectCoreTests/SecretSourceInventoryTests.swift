import Darwin
import Foundation
import ReclaimerCore
import XCTest
@testable import RyddiProtectCore

final class SecretSourceInventoryTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiSecretInventory-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testScansOnlySelectedRootsAndEmitsMetadataWithoutSecretMaterial() throws {
        let selectedRoot = try makeDirectory("selected")
        let outsideRoot = try makeDirectory("outside")
        let canaryKey = "RYDDI_CONTENT_READ_TRAP_KEY"
        let canaryValue = "never-emit-this-value"
        let contents = "\(canaryKey)=\(canaryValue)\n"
        let source = try makeFile(
            at: selectedRoot,
            relativePath: ".env.production",
            data: Data(contents.utf8)
        )
        _ = try makeFile(at: outsideRoot, relativePath: ".env", data: Data("OUTSIDE=1\n".utf8))
        XCTAssertEqual(chmod(source.path, 0o600), 0)

        let modifiedAt = Date(timeIntervalSince1970: 10_000)
        let referenceDate = modifiedAt.addingTimeInterval(3_600)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: source.path
        )

        let result = SecretSourceInventory().scan(
            roots: [selectedRoot],
            referenceDate: referenceDate
        )

        let entry = try XCTUnwrap(result.entries.only)
        XCTAssertEqual(entry.path, source.standardizedFileURL.path)
        let cleanupIdentity = try FileIdentityReader().read(at: source)
        XCTAssertEqual(entry.fileIdentity.deviceID, cleanupIdentity.deviceID)
        XCTAssertEqual(entry.fileIdentity.fileID, cleanupIdentity.fileID)
        XCTAssertEqual(entry.fileIdentity.kind.rawValue, cleanupIdentity.kind.rawValue)
        XCTAssertEqual(entry.fileIdentity.standardizedPath, cleanupIdentity.standardizedPath)
        XCTAssertEqual(entry.fileSize, Int64(contents.utf8.count))
        XCTAssertEqual(entry.posixMode, 0o600)
        XCTAssertEqual(entry.age, 3_600, accuracy: 0.01)
        XCTAssertEqual(entry.sourceKind, .dotenv)
        XCTAssertEqual(entry.inspectionEligibility, .eligible)
        XCTAssertEqual(result.coverage.selectedRootCount, 1)
        XCTAssertTrue(result.coverage.isComplete)

        let fieldNames = Set(Mirror(reflecting: entry).children.compactMap { $0.label })
        XCTAssertEqual(fieldNames, [
            "age",
            "fileIdentity",
            "fileSize",
            "inspectionEligibility",
            "path",
            "posixMode",
            "sourceKind"
        ])
        let reflectedResult = String(reflecting: result)
        XCTAssertFalse(reflectedResult.contains(canaryKey))
        XCTAssertFalse(reflectedResult.contains(canaryValue))
        XCTAssertFalse(result.entries.contains { $0.path.hasPrefix(outsideRoot.path + "/") })
    }

    func testDetectsDotenvNamesButSkipsExamplesAndVendorBuildDirectories() throws {
        let selectedRoot = try makeDirectory("project")
        for name in [
            ".env",
            ".env.local",
            ".env.production.local",
            ".env.example",
            ".env.example.local",
            ".env.sample",
            ".env.sample.local",
            ".envrc",
            "env"
        ] {
            _ = try makeFile(at: selectedRoot, relativePath: name)
        }
        for directory in ["vendor", "node_modules", ".build", "build", "DerivedData"] {
            _ = try makeFile(at: selectedRoot, relativePath: "\(directory)/.env")
        }
        _ = try makeFile(at: selectedRoot, relativePath: "Sources/Feature/.env.test")

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertEqual(Set(relativePaths(in: result, root: selectedRoot)), [
            ".env",
            ".env.local",
            ".env.production.local",
            "Sources/Feature/.env.test"
        ])
        XCTAssertFalse(result.coverage.isTruncated)
    }

    func testSkipsFileAndDirectorySymlinks() throws {
        let selectedRoot = try makeDirectory("selected")
        let externalRoot = try makeDirectory("external")
        let selectedSource = try makeFile(at: selectedRoot, relativePath: ".env")
        let externalSource = try makeFile(at: externalRoot, relativePath: ".env")
        try FileManager.default.createSymbolicLink(
            at: selectedRoot.appendingPathComponent(".env.link"),
            withDestinationURL: externalSource
        )
        try FileManager.default.createSymbolicLink(
            at: selectedRoot.appendingPathComponent("linked-project"),
            withDestinationURL: externalRoot
        )

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertEqual(result.entries.map(\SecretSourceInventoryEntry.path), [
            selectedSource.standardizedFileURL.path
        ])
        XCTAssertGreaterThanOrEqual(result.coverage.skippedEntryCount, 2)
    }

    func testSkipsSelectedSymlinkRootWithoutFollowingIt() throws {
        let externalRoot = try makeDirectory("external-root")
        _ = try makeFile(at: externalRoot, relativePath: ".env")
        let selectedRoot = temporaryRoot.appendingPathComponent("selected-root")
        try FileManager.default.createSymbolicLink(
            at: selectedRoot,
            withDestinationURL: externalRoot
        )

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.coverage.skippedEntryCount, 1)
    }

    func testPreservesPrivateTmpSelectedRootNamespace() throws {
        let directoryName = "RyddiSecretInventory-" + UUID().uuidString
        let selectedPath = "/private/tmp/\(directoryName)"
        let selectedRoot = URL(fileURLWithPath: selectedPath, isDirectory: true)
        let sourcePath = selectedPath + "/.env"
        try FileManager.default.createDirectory(
            at: selectedRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(atPath: selectedPath) }
        try Data("PRIVATE_TMP=fixture\n".utf8).write(
            to: URL(fileURLWithPath: sourcePath)
        )

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertEqual(result.entries.map(\SecretSourceInventoryEntry.path), [sourcePath])
    }

    func testSkipsOversizedAndUnreadableFilesAtMetadataBoundary() throws {
        let selectedRoot = try makeDirectory("selected")
        let allowed = try makeFile(
            at: selectedRoot,
            relativePath: ".env.allowed",
            data: Data(repeating: 0x41, count: Int(SecretSourceInventory.maximumEligibleFileSize))
        )
        _ = try makeFile(
            at: selectedRoot,
            relativePath: ".env.too-large",
            data: Data(repeating: 0x42, count: Int(SecretSourceInventory.maximumEligibleFileSize + 1))
        )
        let unreadable = try makeFile(at: selectedRoot, relativePath: ".env.private")
        XCTAssertEqual(chmod(unreadable.path, 0o000), 0)
        defer { _ = chmod(unreadable.path, 0o600) }

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertEqual(result.entries.map(\SecretSourceInventoryEntry.path), [
            allowed.standardizedFileURL.path
        ])
        XCTAssertEqual(result.coverage.unreadableEntryCount, 1)
        XCTAssertFalse(result.coverage.isComplete)
    }

    func testFIFOContentReadTrapIsRejectedWithoutOpening() throws {
        let selectedRoot = try makeDirectory("selected")
        let source = try makeFile(at: selectedRoot, relativePath: ".env")
        let fifo = selectedRoot.appendingPathComponent(".env.pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)

        let result = SecretSourceInventory().scan(roots: [selectedRoot])

        XCTAssertEqual(result.entries.map(\SecretSourceInventoryEntry.path), [
            source.standardizedFileURL.path
        ])
        XCTAssertGreaterThanOrEqual(result.coverage.skippedEntryCount, 1)
    }

    func testDepthBudgetReportsTruncationAndKeepsShallowEvidence() throws {
        let selectedRoot = try makeDirectory("selected")
        let shallow = try makeFile(at: selectedRoot, relativePath: ".env")
        _ = try makeFile(at: selectedRoot, relativePath: "nested/.env.deep")

        let result = SecretSourceInventory().scan(
            roots: [selectedRoot],
            budget: SecretSourceInventoryBudget(
                maximumDepth: 1,
                maximumVisitedEntryCount: 100,
                maximumElapsedTime: 5
            )
        )

        XCTAssertEqual(result.entries.map(\SecretSourceInventoryEntry.path), [
            shallow.standardizedFileURL.path
        ])
        XCTAssertEqual(result.coverage.truncationReasons, [.maximumDepth])
    }

    func testVisitedEntryBudgetTruncatesBeforeUnboundedEnumeration() throws {
        let selectedRoot = try makeDirectory("selected")
        for index in 0..<4 {
            _ = try makeFile(at: selectedRoot, relativePath: ".env.\(index)")
        }

        let result = SecretSourceInventory().scan(
            roots: [selectedRoot],
            budget: SecretSourceInventoryBudget(
                maximumDepth: 4,
                maximumVisitedEntryCount: 2,
                maximumElapsedTime: 5
            )
        )

        XCTAssertEqual(result.coverage.visitedEntryCount, 2)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertTrue(result.coverage.truncationReasons.contains(.maximumVisitedEntryCount))
    }

    func testElapsedTimeBudgetFailsClosedBeforeFurtherMetadataWork() throws {
        let selectedRoot = try makeDirectory("selected")
        _ = try makeFile(at: selectedRoot, relativePath: ".env")
        let clock = StepClock(values: [0, 0, 2])
        let inventory = SecretSourceInventory(monotonicTime: clock.now)

        let result = inventory.scan(
            roots: [selectedRoot],
            budget: SecretSourceInventoryBudget(
                maximumDepth: 4,
                maximumVisitedEntryCount: 100,
                maximumElapsedTime: 1
            )
        )

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.coverage.visitedEntryCount, 0)
        XCTAssertEqual(result.coverage.truncationReasons, [.maximumElapsedTime])
    }

    private func makeDirectory(_ relativePath: String) throws -> URL {
        let directory = temporaryRoot.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.standardizedFileURL
    }

    @discardableResult
    private func makeFile(
        at root: URL,
        relativePath: String,
        data: Data = Data("VALUE=fixture\n".utf8)
    ) throws -> URL {
        let file = root.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
        return file.standardizedFileURL
    }

    private func relativePaths(
        in result: SecretSourceInventoryResult,
        root: URL
    ) -> [String] {
        let prefix = root.standardizedFileURL.path + "/"
        return result.entries.compactMap { entry in
            guard entry.path.hasPrefix(prefix) else { return nil }
            return String(entry.path.dropFirst(prefix.count))
        }
    }
}

private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [TimeInterval]
    private var index = 0

    init(values: [TimeInterval]) {
        self.values = values
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return 0 }
        let value = values[Swift.min(index, values.count - 1)]
        index += 1
        return value
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
