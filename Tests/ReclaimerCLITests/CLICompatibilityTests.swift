import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore
@testable import reclaimer

final class CLICompatibilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiCLICompatibility-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func testHelpKeepsPrimaryCommandFamiliesAndSafetyBoundary() throws {
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["help"])
        }

        for command in ["overview", "audit summary", "report", "remote targets list", "execute --dry-run"] {
            XCTAssertTrue(output.contains(command), command)
        }
        XCTAssertTrue(output.contains("Core execution is dry-run-only"))
    }

    func testReviewJSONRemainsDecodableAfterCommandExtraction() throws {
        try Data("fixture".utf8).write(to: root.appendingPathComponent("fixture.bin"))
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "overview",
                "--path", root.path,
                "--min-size", "1",
                "--json"
            ])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ScanOverview.self, from: Data(output.utf8))
        XCTAssertFalse(report.topFindings.isEmpty)
        XCTAssertEqual(report.scopeSummaries.first?.path, root.path)
    }

    func testUnknownCommandErrorTextRemainsStable() {
        XCTAssertThrowsError(try ReclaimerCLI.run(arguments: ["not-a-command"])) { error in
            XCTAssertEqual(error.localizedDescription, "Unknown command: not-a-command")
        }
    }

    private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
        let original = dup(STDOUT_FILENO)
        guard original >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var descriptors = [Int32](repeating: 0, count: 2)
        guard pipe(&descriptors) == 0 else {
            close(original)
            throw CocoaError(.fileWriteUnknown)
        }
        fflush(stdout)
        guard dup2(descriptors[1], STDOUT_FILENO) >= 0 else {
            close(original)
            close(descriptors[0])
            close(descriptors[1])
            throw CocoaError(.fileWriteUnknown)
        }
        close(descriptors[1])

        do {
            try body()
            fflush(stdout)
            _ = dup2(original, STDOUT_FILENO)
            close(original)
        } catch {
            fflush(stdout)
            _ = dup2(original, STDOUT_FILENO)
            close(original)
            close(descriptors[0])
            throw error
        }

        let data = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true).readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
