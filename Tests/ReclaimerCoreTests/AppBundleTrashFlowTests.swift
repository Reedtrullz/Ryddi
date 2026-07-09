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
