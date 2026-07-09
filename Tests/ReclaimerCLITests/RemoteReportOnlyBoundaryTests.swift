import XCTest
@testable import reclaimer

final class RemoteReportOnlyBoundaryTests: XCTestCase {
    func testRemoteDestructiveVerbsAreRejected() throws {
        for verb in ["execute", "prune", "reset", "delete", "clean", "vacuum"] {
            XCTAssertThrowsError(try ReclaimerCLI.run(arguments: ["remote", verb, "example"])) { error in
                XCTAssertTrue(error.localizedDescription.contains("Remote Targets are report-only"), "\(verb): \(error.localizedDescription)")
            }
        }
    }

    func testRemoteTargetsViewDoesNotExposeDestructiveButtons() throws {
        let source = try String(contentsOfFile: "Sources/MacDiskReclaimerApp/RemoteTargetsView.swift", encoding: .utf8)

        for label in ["Reclaim", "Delete", "Prune", "Reset", "Run Cleanup"] {
            XCTAssertFalse(source.contains("Label(\"\(label)\""), "Remote UI must not expose \(label) label")
            XCTAssertFalse(source.contains("Button(\"\(label)\""), "Remote UI must not expose \(label) button")
        }
    }
}
