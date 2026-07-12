import Foundation
import XCTest
@testable import ReclaimerCore

final class SafeFileOutputTests: XCTestCase {
    func testSafeFileOutputWritesOnlyNewFileInExistingDirectory() throws {
        let directory = temporaryDirectory("safe-file-output")
        let output = directory.appendingPathComponent("report.md")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let written = try SafeFileOutput.write(Data("new report".utf8), to: output)

        XCTAssertEqual(written.standardizedFileURL.path, output.standardizedFileURL.path)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "new report")
    }

    func testSafeFileOutputRefusesExistingFileWithoutOverwritingIt() throws {
        let directory = temporaryDirectory("safe-file-output")
        let output = directory.appendingPathComponent("report.md")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "keep me".write(to: output, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SafeFileOutput.write(Data("new report".utf8), to: output)) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("already exists"), error.localizedDescription)
        }
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "keep me")
    }

    func testSafeFileOutputStaysBoundToParentDirectoryAfterVisiblePathSwap() throws {
        let base = temporaryDirectory("safe-file-output")
        let visibleParent = base.appendingPathComponent("visible", isDirectory: true)
        let movedParent = base.appendingPathComponent("moved", isDirectory: true)
        let unrelatedParent = base.appendingPathComponent("unrelated", isDirectory: true)
        let output = visibleParent.appendingPathComponent("report.md")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: visibleParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedParent, withIntermediateDirectories: true)

        _ = try SafeFileOutput.write(
            Data("bound report".utf8),
            to: output,
            beforeWrite: {
                try FileManager.default.moveItem(at: visibleParent, to: movedParent)
                try FileManager.default.createSymbolicLink(at: visibleParent, withDestinationURL: unrelatedParent)
            }
        )

        XCTAssertEqual(
            try String(contentsOf: movedParent.appendingPathComponent("report.md"), encoding: .utf8),
            "bound report"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: unrelatedParent.appendingPathComponent("report.md").path))
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
    }
}
