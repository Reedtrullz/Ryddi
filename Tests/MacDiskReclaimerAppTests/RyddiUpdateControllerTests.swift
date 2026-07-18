import XCTest
@testable import MacDiskReclaimerApp

@MainActor
final class RyddiUpdateControllerTests: XCTestCase {
    func testManualUpdateDelegatesOnlyWhenCheckerIsReady() {
        let checker = FakeUpdateChecker(canCheckForUpdates: false)
        let controller = RyddiUpdateController(checker: checker)

        controller.updateToLatestVersion()
        XCTAssertEqual(checker.manualCheckCount, 0)

        checker.canCheckForUpdates = true
        controller.updateToLatestVersion()
        XCTAssertEqual(checker.manualCheckCount, 1)
    }

    func testAutomaticCheckPreferenceUsesUpdaterOwnedStorage() {
        let checker = FakeUpdateChecker(canCheckForUpdates: true)
        let controller = RyddiUpdateController(checker: checker)

        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        controller.automaticallyChecksForUpdates = false

        XCTAssertFalse(checker.automaticallyChecksForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }
}

@MainActor
private final class FakeUpdateChecker: RyddiUpdateChecking {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates: Bool {
        didSet { canCheckHandler?(canCheckForUpdates) }
    }
    private(set) var manualCheckCount = 0
    private var canCheckHandler: (@MainActor (Bool) -> Void)?

    init(canCheckForUpdates: Bool) {
        self.canCheckForUpdates = canCheckForUpdates
    }

    func checkForUpdates() {
        manualCheckCount += 1
    }

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> NSKeyValueObservation? {
        canCheckHandler = handler
        handler(canCheckForUpdates)
        return nil
    }
}
