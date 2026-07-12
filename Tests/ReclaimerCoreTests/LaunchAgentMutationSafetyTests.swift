import Foundation
import XCTest
@testable import ReclaimerCore

final class LaunchAgentMutationSafetyTests: XCTestCase {
    func testInstallRefusesToReplaceExistingLaunchAgentPlist() throws {
        let home = temporaryHome()
        let manager = LaunchAgentManager()
        let target = manager.installedPath(home: home)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep this schedule".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.install(cliPath: "/tmp/reclaimer", home: home)) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("already exists"), error.localizedDescription)
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep this schedule")
    }

    func testUninstallLeavesExistingLaunchAgentPlistForManualRemoval() throws {
        let home = temporaryHome()
        let manager = LaunchAgentManager()
        let target = manager.installedPath(home: home)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep this schedule".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.uninstall(home: home)) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("manual"), error.localizedDescription)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep this schedule")
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-agent-safety-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
    }
}
