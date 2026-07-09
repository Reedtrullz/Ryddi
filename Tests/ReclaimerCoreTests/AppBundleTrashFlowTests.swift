import XCTest
@testable import ReclaimerCore

final class AppBundleTrashFlowTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiAppBundleTrashFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testAppBundleTrashFlowBlocksRunningApp() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Running.app", isDirectory: true)
        try createAppBundle(at: app, bundleIdentifier: "com.example.running", displayName: "Running")
        let preview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: app.path))

        let receipt = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: true),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot])
        ).execute(preview: preview, mode: .perform, userConfirmed: true)

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("running"))
        XCTAssertTrue(receipt.nonClaims.contains { $0.localizedCaseInsensitiveContains("Finder") && $0.localizedCaseInsensitiveContains("Trash") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testAppBundleTrashFlowBlocksPathOutsideAllowedRoots() throws {
        let allowedRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let outsideRoot = tempRoot.appendingPathComponent("Downloads", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = outsideRoot.appendingPathComponent("Outside.app", isDirectory: true)
        try FileManager.default.createDirectory(at: allowedRoot, withIntermediateDirectories: true)
        try createAppBundle(at: app, bundleIdentifier: "com.example.outside", displayName: "Outside")
        let preview = try previewForApp(appRoot: outsideRoot, home: home, selector: AppUninstallSelector(appPath: app.path))

        let receipt = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [allowedRoot])
        ).execute(preview: preview, mode: .dryRun, userConfirmed: false)

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("allowed app roots"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testAppBundleTrashFlowRequiresDryRunAuthorizationForPerform() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Unauthorized.app", isDirectory: true)
        try createAppBundle(at: app, bundleIdentifier: "com.example.unauthorized", displayName: "Unauthorized")
        let preview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: app.path))

        let receipt = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot])
        ).execute(preview: preview, mode: .perform, userConfirmed: true)
        defer {
            if let resultingTrashPath = receipt.resultingTrashPath {
                try? FileManager.default.removeItem(atPath: resultingTrashPath)
            }
        }

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("dry-run authorization"), receipt.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testCleanMatchingDryRunAuthorizesOnlyExactAppBundle() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let trashRoot = tempRoot.appendingPathComponent("Fixture Trash", isDirectory: true)
        let app = appRoot.appendingPathComponent("Authorized.app", isDirectory: true)
        let related = home.appendingPathComponent("Library/Caches/com.example.authorized/cache.bin")
        try createAppBundle(at: app, bundleIdentifier: "com.example.authorized", displayName: "Authorized")
        try FileManager.default.createDirectory(at: related.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 128).write(to: related)
        let preview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: app.path))
        let now = Date(timeIntervalSince1970: 10_000)

        let dryRun = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot]),
            now: { now }
        ).execute(preview: preview, mode: .dryRun, userConfirmed: false)

        XCTAssertEqual(dryRun.status, "dry-run")
        XCTAssertNotNil(dryRun.authorizationDigest)

        let performed = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot]),
            appBundleTrasher: FixtureAppBundleTrasher(destinationRoot: trashRoot),
            now: { now.addingTimeInterval(1) }
        ).execute(
            preview: preview,
            mode: .perform,
            userConfirmed: true,
            authorization: AppUninstallPerformAuthorization(dryRunReceipt: dryRun)
        )

        XCTAssertEqual(performed.status, "done", performed.message)
        XCTAssertEqual(performed.authorizationDigest, dryRun.authorizationDigest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: related.path))
        XCTAssertTrue(performed.resultingTrashPath?.hasPrefix(trashRoot.path) == true)
    }

    func testDryRunAuthorizationRejectsDifferentBundle() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let first = appRoot.appendingPathComponent("First.app", isDirectory: true)
        let second = appRoot.appendingPathComponent("Second.app", isDirectory: true)
        try createAppBundle(at: first, bundleIdentifier: "com.example.first", displayName: "First")
        try createAppBundle(at: second, bundleIdentifier: "com.example.second", displayName: "Second")
        let firstPreview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: first.path))
        let secondPreview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: second.path))
        let now = Date(timeIntervalSince1970: 20_000)
        let executor = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot]),
            now: { now }
        )
        let firstDryRun = executor.execute(preview: firstPreview, mode: .dryRun, userConfirmed: false)

        let receipt = executor.execute(
            preview: secondPreview,
            mode: .perform,
            userConfirmed: true,
            authorization: AppUninstallPerformAuthorization(dryRunReceipt: firstDryRun)
        )

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("different app bundle path"), receipt.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testDryRunAuthorizationRejectsStaleReceipt() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Stale.app", isDirectory: true)
        try createAppBundle(at: app, bundleIdentifier: "com.example.stale", displayName: "Stale")
        let preview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: app.path))
        let dryRunDate = Date(timeIntervalSince1970: 30_000)
        let dryRun = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot]),
            now: { dryRunDate }
        ).execute(preview: preview, mode: .dryRun, userConfirmed: false)

        let receipt = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot]),
            now: { dryRunDate.addingTimeInterval(AppUninstallExecutorConfiguration.maximumDryRunAuthorizationAge + 1) }
        ).execute(
            preview: preview,
            mode: .perform,
            userConfirmed: true,
            authorization: AppUninstallPerformAuthorization(dryRunReceipt: dryRun)
        )

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("stale"), receipt.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testDryRunAuthorizationRejectsSamePathReplacement() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Replaced.app", isDirectory: true)
        try createAppBundle(at: app, bundleIdentifier: "com.example.replaced", displayName: "Replaced")
        let preview = try previewForApp(appRoot: appRoot, home: home, selector: AppUninstallSelector(appPath: app.path))
        let executor = AppUninstallExecutor(
            openFileChecker: NoOpenFilesChecker(),
            runningApplicationChecker: FixedRunningApplicationChecker(isRunning: false),
            configuration: AppUninstallExecutorConfiguration(allowedAppRoots: [appRoot])
        )
        let dryRun = executor.execute(preview: preview, mode: .dryRun, userConfirmed: false)

        try FileManager.default.removeItem(at: app)
        try createAppBundle(at: app, bundleIdentifier: "com.example.replaced", displayName: "Replaced")
        let receipt = executor.execute(
            preview: preview,
            mode: .perform,
            userConfirmed: true,
            authorization: AppUninstallPerformAuthorization(dryRunReceipt: dryRun)
        )

        XCTAssertEqual(receipt.status, "skipped")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("changed since preview"), receipt.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    private func previewForApp(appRoot: URL, home: URL, selector: AppUninstallSelector) throws -> AppUninstallPreview {
        let report = try AppReviewScanner().scan(
            options: AppReviewOptions(
                appRoots: [appRoot],
                home: home,
                minimumRelatedSize: 1,
                measurementDepth: 2
            )
        )
        return try AppUninstallPreviewBuilder.build(report: report, selector: selector)
    }

    private func createAppBundle(at url: URL, bundleIdentifier: String, displayName: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
            "CFBundleExecutable": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 512).write(to: macOS.appendingPathComponent(displayName))
    }
}

private struct FixedRunningApplicationChecker: RunningApplicationChecking {
    let isRunning: Bool

    func isAppRunning(bundleIdentifier: String?, executableName: String?, displayName: String) -> Bool {
        isRunning
    }
}

private struct FixtureAppBundleTrasher: AppBundleTrashing {
    let destinationRoot: URL

    func trashItem(at url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let destination = destinationRoot.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
