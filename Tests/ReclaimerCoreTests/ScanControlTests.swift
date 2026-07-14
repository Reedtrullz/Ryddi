import Foundation
import XCTest
@testable import ReclaimerCore

final class ScanControlTests: XCTestCase {
    func testCancellationTokenIsThreadSafeAndSticky() async {
        let token = ScanCancellationToken()
        XCTAssertFalse(token.isCancelled)

        await Task.detached { token.cancel() }.value

        XCTAssertTrue(token.isCancelled)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    func testCancelledWalkerStopsBeforeBudget() throws {
        let fixture = try ScanControlFixture(fileCount: 120)
        let token = ScanCancellationToken()
        let control = ScanControl(cancellation: token) { progress in
            if progress.measuredItemCount >= 3 {
                token.cancel()
            }
        }

        let result = try FileScanner().scanWithCoverage(
            scopes: [ScanScope(name: "Fixture", root: fixture.root)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 1,
                measurementItemBudget: 100
            ),
            control: control
        )

        XCTAssertLessThan(result.coverage.measuredItemCount, 100)
        XCTAssertTrue(result.coverage.evidence.contains { $0.contains("cancelled") })
    }

    func testProgressUsesScopeNamesAndPhaseTransitions() throws {
        let fixture = try ScanControlFixture(fileCount: 2)
        let recorder = ScanProgressRecorder()

        _ = try FileScanner().scanWithCoverage(
            scopes: [ScanScope(name: "Safe label", root: fixture.root)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 1,
                measurementItemBudget: 10
            ),
            control: ScanControl(cancellation: ScanCancellationToken()) { progress in
                recorder.append(progress)
            }
        )

        XCTAssertEqual(recorder.values.first?.phase, .preparing)
        XCTAssertEqual(recorder.values.last?.phase, .finished)
        XCTAssertTrue(recorder.values.contains { $0.phase == .measuring && $0.scopeName == "Safe label" })
        XCTAssertTrue(recorder.values.contains { $0.phase == .classifying })
        XCTAssertFalse(recorder.values.contains { $0.scopeName == fixture.root.path })
    }
}

private final class ScanProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [ScanProgress]()

    var values: [ScanProgress] {
        lock.withLock { storage }
    }

    func append(_ progress: ScanProgress) {
        lock.withLock { storage.append(progress) }
    }
}

private final class ScanControlFixture {
    let root: URL

    init(fileCount: Int) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiScanControl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            try Data(repeating: 0x41, count: 32).write(
                to: root.appendingPathComponent("item-\(index).bin")
            )
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
