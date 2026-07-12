import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore
@testable import reclaimer

final class IssuePackageCLITests: XCTestCase {
    private var base: URL!
    private var auditRoot: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiIssuePackageCLITests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        auditRoot = base.appendingPathComponent("audit", isDirectory: true)
        try FileManager.default.createDirectory(at: auditRoot, withIntermediateDirectories: true)
        setenv("RYDDI_AUDIT_ROOT", auditRoot.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("RYDDI_AUDIT_ROOT")
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
    }

    func testIssuePackageCommandWritesManifestAndReportsJSON() throws {
        let output = base.appendingPathComponent("package", isDirectory: true)

        let stdout = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "issue", "package",
                "--path-style", "redacted",
                "--output", output.path,
                "--json"
            ])
        }

        let manifest = try JSONDecoder.ryddiIssuePackage.decode(IssuePackageManifest.self, from: Data(stdout.utf8))
        XCTAssertEqual(manifest.pathStyle, .redacted)
        XCTAssertTrue(manifest.includedFiles.contains("manifest.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("report.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("non-claims.md").path))
    }

    private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
        let original = dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(original, 0)
        var fds = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fds), 0)

        fflush(stdout)
        dup2(fds[1], STDOUT_FILENO)
        close(fds[1])

        do {
            try body()
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
        } catch {
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
            close(fds[0])
            throw error
        }

        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension JSONDecoder {
    static var ryddiIssuePackage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
