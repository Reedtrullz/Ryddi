import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

struct HarnessResult: Codable {
    struct Checkpoint: Codable {
        let name: String
        let elapsedMilliseconds: Int
    }

    struct ResponsiveCheck: Codable {
        let name: String
        let width: Int
        let height: Int
        let containedElementIDs: [String]
    }

    let bundleIdentifier: String
    let processIdentifier: Int32
    let checkpoints: [Checkpoint]
    let screenshots: [String]
    let responsiveChecks: [ResponsiveCheck]
    let scanProgressVisible: Bool
    let cancelledScanBecameIdle: Bool
    let cancelledScanHadNoLateCommit: Bool
    let normalScanCompleted: Bool
    let originalCandidateMissing: Bool
    let executionResultVisible: Bool
    let verificationActionVisible: Bool
    let candidateRowRemoved: Bool
    let reclaimActionHidden: Bool
    let reclaimActionHiddenAfterVerificationScan: Bool
}

enum HarnessError: Error, CustomStringConvertible {
    case usage(String)
    case accessibilityPermission
    case appNotRunning(String)
    case missingElement(String)
    case disabledElement(String)
    case unexpectedElement(String)
    case actionFailed(String, AXError)
    case windowUnavailable
    case screenshotFailed(String)
    case candidateStillExists(String)
    case lateCancelledScanCommit(String)
    case elementOutsideWindow(String, String)

    var description: String {
        switch self {
        case .usage(let message): message
        case .accessibilityPermission:
            "Accessibility permission is required for the packaged-app AX release lane."
        case .appNotRunning(let id): "No running application found for bundle identifier \(id)."
        case .missingElement(let id): "Timed out waiting for AX identifier \(id)."
        case .disabledElement(let id): "AX element \(id) remained disabled."
        case .unexpectedElement(let id): "AX element \(id) remained visible."
        case .actionFailed(let id, let error): "AX action failed for \(id): \(error.rawValue)."
        case .windowUnavailable: "The packaged app did not expose a main AX window."
        case .screenshotFailed(let path): "Failed to capture a non-empty screenshot at \(path)."
        case .candidateStillExists(let path): "Confirmed Trash candidate still exists at \(path)."
        case .lateCancelledScanCommit(let path): "Cancelled scan committed late result evidence for \(path)."
        case .elementOutsideWindow(let id, let size): "AX element \(id) extends outside the main window at \(size)."
        }
    }
}

@main
enum RyddiAXHarness {
    private static let logger = Logger(subsystem: "com.reidar.ryddi", category: "e2e")

    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("Ryddi AX E2E failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let options = try parseArguments()
        guard AXIsProcessTrusted() else { throw HarnessError.accessibilityPermission }
        guard let running = waitForApplication(
            bundleIdentifier: options.bundleIdentifier,
            bundlePath: options.appPath,
            timeout: 15
        ) else {
            throw HarnessError.appNotRunning(options.bundleIdentifier)
        }

        let started = Date()
        var checkpoints: [HarnessResult.Checkpoint] = []
        let app = AXUIElementCreateApplication(running.processIdentifier)
        try checkpoint("launch", started: started, into: &checkpoints) {
            _ = try waitForElement(identifier: "home.primary-action", root: app, timeout: 15, requireEnabled: true)
        }
        try checkpoint("cancelled-scan", started: started, into: &checkpoints) {
            try press("scan-button", root: app)
            _ = try waitForElement(identifier: "scan-progress", root: app, timeout: 10, requireEnabled: false)
            _ = try waitForElement(identifier: "home.scan-status", root: app, timeout: 10, requireEnabled: false)
            try press("cancel-scan-button", root: app)
            try waitForCancelledScanToBecomeIdle(root: app, timeout: 10)
            try assertNoLateCancelledScanCommit(path: options.candidatePath, root: app, quietPeriod: 1.2)
        }
        try checkpoint("scan", started: started, into: &checkpoints) {
            try press("scan-button", root: app)
            _ = try waitForElement(identifier: "scan-progress", root: app, timeout: 10, requireEnabled: false)
            _ = try waitForElement(identifier: "home.scan-status", root: app, timeout: 10, requireEnabled: false)
            _ = try waitForElement(identifier: "guided-map.breadcrumb", root: app, timeout: 90, requireEnabled: false)
            _ = try waitForElement(identifier: "home.scan-result", root: app, timeout: 20, requireEnabled: false)
            _ = try waitForElement(identifier: "home.primary-action", root: app, timeout: 20, requireEnabled: true)
        }
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        let scanResultScreenshot = options.output.appendingPathComponent("ryddi-scan-result.png")
        try captureWindow(pid: running.processIdentifier, output: scanResultScreenshot)
        var exploreScreenshots: [URL] = [scanResultScreenshot]
        try checkpoint("scoped-review", started: started, into: &checkpoints) {
            try press("home.suggestion.home-suggestion:safeMaintenance", root: app)
            let title = try waitForElement(
                identifier: "cleanup-review.title",
                root: app,
                timeout: 20,
                requireEnabled: false
            )
            guard find(named: "Safe maintenance", root: title) != nil else {
                throw HarnessError.missingElement("Safe maintenance scoped review title")
            }
            try assertEmptyCleanupSelection(root: app)
            let scopedReviewScreenshot = options.output.appendingPathComponent("ryddi-scoped-review.png")
            try captureWindow(pid: running.processIdentifier, output: scopedReviewScreenshot)
            exploreScreenshots.append(scopedReviewScreenshot)
            try press("cleanup-review.done", root: app)
            _ = try waitForElement(identifier: "home.primary-action", root: app, timeout: 20, requireEnabled: true)
        }
        try checkpoint("explore-tools", started: started, into: &checkpoints) {
            exploreScreenshots += try captureExploreToolsProof(
                app: app,
                pid: running.processIdentifier,
                output: options.output
            )
        }
        try checkpoint("review", started: started, into: &checkpoints) {
            try press("home.primary-action", root: app)
            _ = try waitForElement(identifier: "cleanup-review.select-safe", root: app, timeout: 20, requireEnabled: true)
            try assertEmptyCleanupSelection(root: app)
            try press("cleanup-review.select-safe", root: app)
            _ = try waitForElement(identifier: "cleanup-review.check-safely", root: app, timeout: 20, requireEnabled: true)
        }
        try checkpoint("dry-run", started: started, into: &checkpoints) {
            try press("cleanup-review.check-safely", root: app)
            _ = try waitForElement(identifier: "cleanup-review.move-to-trash", root: app, timeout: 60, requireEnabled: true)
        }
        try checkpoint("confirmation", started: started, into: &checkpoints) {
            try press("cleanup-review.move-to-trash", root: app)
            _ = try waitForElement(identifier: "trash-confirmation.reviewed", root: app, timeout: 20, requireEnabled: true)
            try press("trash-confirmation.reviewed", root: app)
            _ = try waitForElement(identifier: "trash-confirmation.confirm", root: app, timeout: 10, requireEnabled: true)
            try press("trash-confirmation.confirm", root: app)
        }

        let resultElement = try waitForElement(
            identifier: "trash-execution.result",
            root: app,
            timeout: 60,
            requireEnabled: false
        )
        _ = resultElement
        guard !FileManager.default.fileExists(atPath: options.candidatePath) else {
            throw HarnessError.candidateStillExists(options.candidatePath)
        }
        try press("cleanup-review.done", root: app)
        _ = try waitForElement(identifier: "home.primary-action", root: app, timeout: 30, requireEnabled: true)
        checkpoints.append(.init(name: "trash-result", elapsedMilliseconds: elapsed(started)))
        try checkpoint("verification-scan", started: started, into: &checkpoints) {
            try press("home.primary-action", root: app)
            try waitForVerificationScanCompletion(root: app, timeout: 90)
            try assertCandidateRowMissing(path: options.candidatePath, root: app, timeout: 20)
            try assertElementMissing(identifier: "cleanup-review.move-to-trash", root: app, timeout: 20)
        }

        let responsiveProof = try captureResponsiveProof(app: app, pid: running.processIdentifier, output: options.output)
        let screenshots = exploreScreenshots + responsiveProof.screenshots
        let result = HarnessResult(
            bundleIdentifier: options.bundleIdentifier,
            processIdentifier: running.processIdentifier,
            checkpoints: checkpoints,
            screenshots: screenshots.map(\.lastPathComponent),
            responsiveChecks: responsiveProof.checks,
            scanProgressVisible: true,
            cancelledScanBecameIdle: true,
            cancelledScanHadNoLateCommit: true,
            normalScanCompleted: true,
            originalCandidateMissing: true,
            executionResultVisible: true,
            verificationActionVisible: true,
            candidateRowRemoved: true,
            reclaimActionHidden: true,
            reclaimActionHiddenAfterVerificationScan: true
        )
        let data = try JSONEncoder.pretty.encode(result)
        try data.write(to: options.output.appendingPathComponent("e2e-result.json"), options: .atomic)
    }

    private struct Options {
        let bundleIdentifier: String
        let appPath: String
        let candidatePath: String
        let output: URL
    }

    private static func parseArguments() throws -> Options {
        var values: [String: String] = [:]
        var index = 1
        while index < CommandLine.arguments.count {
            let key = CommandLine.arguments[index]
            guard key.hasPrefix("--"), index + 1 < CommandLine.arguments.count else {
                throw HarnessError.usage("Usage: RyddiAXHarness --bundle-id ID --app APP --candidate PATH --output DIR")
            }
            values[key] = CommandLine.arguments[index + 1]
            index += 2
        }
        guard let bundleIdentifier = values["--bundle-id"],
              let appPath = values["--app"],
              let candidate = values["--candidate"],
              let output = values["--output"] else {
            throw HarnessError.usage("Usage: RyddiAXHarness --bundle-id ID --app APP --candidate PATH --output DIR")
        }
        return Options(
            bundleIdentifier: bundleIdentifier,
            appPath: URL(fileURLWithPath: appPath).standardizedFileURL.path,
            candidatePath: candidate,
            output: URL(fileURLWithPath: output)
        )
    }

    private static func waitForApplication(
        bundleIdentifier: String,
        bundlePath: String,
        timeout: TimeInterval
    ) -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: {
                $0.bundleURL?.standardizedFileURL.path == bundlePath
            }) {
                return app
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private static func waitForElement(
        identifier: String,
        root: AXUIElement,
        timeout: TimeInterval,
        requireEnabled: Bool
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var foundDisabled = false
        repeat {
            if let element = find(identifier: identifier, root: root) {
                if !requireEnabled || boolAttribute(kAXEnabledAttribute as String, element: element) == true {
                    return element
                }
                foundDisabled = true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        dumpTree(root: root)
        if foundDisabled { throw HarnessError.disabledElement(identifier) }
        throw HarnessError.missingElement(identifier)
    }

    private static func waitForVerificationScanCompletion(
        root: AXUIElement,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let verificationFinished = find(identifier: "scan-progress", root: root) == nil
            let scanEnabled = find(identifier: "scan-button", root: root).map {
                boolAttribute(kAXEnabledAttribute as String, element: $0) == true
            } ?? false
            let primaryEnabled = find(identifier: "home.primary-action", root: root).map {
                boolAttribute(kAXEnabledAttribute as String, element: $0) == true
            } ?? false
            if verificationFinished, scanEnabled, primaryEnabled {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        dumpTree(root: root)
        throw HarnessError.missingElement("fresh verification scan completion")
    }

    private static func waitForCancelledScanToBecomeIdle(
        root: AXUIElement,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let scanEnabled = find(identifier: "scan-button", root: root).map {
                boolAttribute(kAXEnabledAttribute as String, element: $0) == true
            } ?? false
            let progressHidden = find(identifier: "scan-progress", root: root) == nil
            let cancelHidden = find(identifier: "cancel-scan-button", root: root) == nil
            if scanEnabled, progressHidden, cancelHidden {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        dumpTree(root: root)
        throw HarnessError.missingElement("cancelled scan idle state")
    }

    private static func assertNoLateCancelledScanCommit(
        path: String,
        root: AXUIElement,
        quietPeriod: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(quietPeriod)
        repeat {
            let mapVisible = find(identifier: "guided-map.breadcrumb", root: root) != nil
            if mapVisible || findText(path, root: root) != nil {
                dumpTree(root: root)
                throw HarnessError.lateCancelledScanCommit(path)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
    }

    private static func find(identifier: String, root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var queueIndex = 0
        var visited = 0
        while queueIndex < queue.count && visited < 8_000 {
            let element = queue[queueIndex]
            queueIndex += 1
            visited += 1
            if stringAttribute(kAXIdentifierAttribute as String, element: element) == identifier {
                return element
            }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute as String, element: element))
        }
        return nil
    }

    private static func find(named name: String, root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var queueIndex = 0
        var visited = 0
        while queueIndex < queue.count && visited < 8_000 {
            let element = queue[queueIndex]
            queueIndex += 1
            visited += 1
            let values = [
                stringAttribute(kAXTitleAttribute as String, element: element),
                stringAttribute(kAXDescriptionAttribute as String, element: element),
                stringAttribute(kAXValueAttribute as String, element: element)
            ]
            if values.compactMap({ $0 }).contains(name) {
                return element
            }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute as String, element: element))
        }
        return nil
    }

    private static func assertElementMissing(
        identifier: String,
        root: AXUIElement,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if find(identifier: identifier, root: root) == nil {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        throw HarnessError.unexpectedElement(identifier)
    }

    private static func assertCandidateRowMissing(
        path: String,
        root: AXUIElement,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if findText(path, root: root) == nil {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        if let element = findText(path, root: root) {
            let role = stringAttribute(kAXRoleAttribute as String, element: element) ?? "?"
            let identifier = stringAttribute(kAXIdentifierAttribute as String, element: element) ?? ""
            let title = stringAttribute(kAXTitleAttribute as String, element: element) ?? ""
            let description = stringAttribute(kAXDescriptionAttribute as String, element: element) ?? ""
            let value = stringAttribute(kAXValueAttribute as String, element: element) ?? ""
            let line = "Stale candidate AX element role=\(role) id=\(identifier) title=\(title) desc=\(description) value=\(value)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        dumpTree(root: root)
        throw HarnessError.candidateStillExists(path)
    }

    private static func findText(_ text: String, root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var queueIndex = 0
        var visited = 0
        while queueIndex < queue.count && visited < 8_000 {
            let element = queue[queueIndex]
            queueIndex += 1
            visited += 1
            let values = [
                stringAttribute(kAXTitleAttribute as String, element: element),
                stringAttribute(kAXDescriptionAttribute as String, element: element),
                stringAttribute(kAXValueAttribute as String, element: element)
            ]
            if values.compactMap({ $0 }).contains(where: { $0.contains(text) }) {
                return element
            }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute as String, element: element))
        }
        return nil
    }

    private static func dumpTree(root: AXUIElement) {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var queueIndex = 0
        var visited = 0
        FileHandle.standardError.write(Data("AX hierarchy dump:\n".utf8))
        while queueIndex < queue.count && visited < 400 {
            let (element, depth) = queue[queueIndex]
            queueIndex += 1
            visited += 1
            let role = stringAttribute(kAXRoleAttribute as String, element: element) ?? "?"
            let title = stringAttribute(kAXTitleAttribute as String, element: element) ?? ""
            let description = stringAttribute(kAXDescriptionAttribute as String, element: element) ?? ""
            let identifier = stringAttribute(kAXIdentifierAttribute as String, element: element) ?? ""
            let line = "\(String(repeating: "  ", count: min(depth, 8)))\(role) id=\(identifier) title=\(title) desc=\(description)\n"
            FileHandle.standardError.write(Data(line.utf8))
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute as String, element: element).map { ($0, depth + 1) })
        }
    }

    private static func press(_ identifier: String, root: AXUIElement) throws {
        let element = try waitForElement(identifier: identifier, root: root, timeout: 20, requireEnabled: true)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw HarnessError.actionFailed(identifier, result) }
    }

    private static func selectSidebarDestination(_ identifier: String, root: AXUIElement) throws {
        var element = try waitForElement(identifier: identifier, root: root, timeout: 20, requireEnabled: false)
        for _ in 0..<6 {
            if stringAttribute(kAXRoleAttribute as String, element: element) == kAXRowRole as String {
                let result = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedAttribute as CFString,
                    kCFBooleanTrue
                )
                guard result == .success else { throw HarnessError.actionFailed(identifier, result) }
                return
            }
            guard let parent = elementAttribute(kAXParentAttribute as String, element: element) else { break }
            element = parent
        }
        throw HarnessError.actionFailed(identifier, .actionUnsupported)
    }

    private static func captureResponsiveProof(
        app: AXUIElement,
        pid: pid_t,
        output: URL
    ) throws -> (screenshots: [URL], checks: [HarnessResult.ResponsiveCheck]) {
        guard let window = elementArrayAttribute(kAXWindowsAttribute as String, element: app).first else {
            throw HarnessError.windowUnavailable
        }
        let sizes: [(String, CGSize)] = [
            ("minimum", CGSize(width: 820, height: 620)),
            ("regular", CGSize(width: 1_180, height: 760)),
            ("wide", CGSize(width: 1_440, height: 900))
        ]
        var screenshots: [URL] = []
        var checks: [HarnessResult.ResponsiveCheck] = []
        for (name, size) in sizes {
            try setSize(size, window: window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let containedIDs = try assertResponsiveContainment(app: app, window: window, sizeName: name)
            let screenshot = output.appendingPathComponent("ryddi-\(name).png")
            try captureWindow(pid: pid, output: screenshot)
            screenshots.append(screenshot)
            checks.append(.init(
                name: name,
                width: Int(size.width),
                height: Int(size.height),
                containedElementIDs: containedIDs
            ))
        }
        return (screenshots, checks)
    }

    private static func captureExploreToolsProof(
        app: AXUIElement,
        pid: pid_t,
        output: URL
    ) throws -> [URL] {
        try selectSidebarDestination("sidebar.explore", root: app)
        let modePicker = try waitForElement(identifier: "explore.mode", root: app, timeout: 20, requireEnabled: true)
        guard let toolsSegment = find(named: "Tools", root: modePicker) else {
            throw HarnessError.missingElement("Explore Tools segment")
        }
        let result = AXUIElementPerformAction(toolsSegment, kAXPressAction as CFString)
        guard result == .success else { throw HarnessError.actionFailed("Explore Tools", result) }
        _ = try waitForElement(identifier: "explore.tools", root: app, timeout: 20, requireEnabled: false)
        for identifier in ["explore.tool.applications", "explore.tool.cloudFootprint", "explore.tool.containers"] {
            _ = try waitForElement(identifier: identifier, root: app, timeout: 20, requireEnabled: true)
        }

        let toolsScreenshot = output.appendingPathComponent("ryddi-explore-tools.png")
        try captureWindow(pid: pid, output: toolsScreenshot)

        try press("explore.tool.cloudFootprint", root: app)
        _ = try waitForElement(identifier: "cloud-footprint.discover", root: app, timeout: 20, requireEnabled: true)
        _ = try waitForElement(identifier: "cloud-footprint.setup-guide", root: app, timeout: 20, requireEnabled: false)
        let cloudScreenshot = output.appendingPathComponent("ryddi-cloud-footprint.png")
        try captureWindow(pid: pid, output: cloudScreenshot)
        if let done = find(identifier: "storage-review.done", root: app) ?? find(named: "Done", root: app) {
            let result = AXUIElementPerformAction(done, kAXPressAction as CFString)
            guard result == .success else { throw HarnessError.actionFailed("Storage review Done", result) }
        } else {
            throw HarnessError.missingElement("Storage review Done")
        }
        _ = try waitForElement(identifier: "explore.tools", root: app, timeout: 20, requireEnabled: false)

        try selectSidebarDestination("sidebar.home", root: app)
        _ = try waitForElement(identifier: "home.primary-action", root: app, timeout: 20, requireEnabled: true)
        return [toolsScreenshot, cloudScreenshot]
    }

    private static func assertResponsiveContainment(
        app: AXUIElement,
        window: AXUIElement,
        sizeName: String
    ) throws -> [String] {
        guard let windowFrame = frame(of: window) else { throw HarnessError.windowUnavailable }
        let fixedIDs = ["dashboard-sidebar", "scan-button", "home.primary-action"]
        let elements: [(String, AXUIElement)] = try fixedIDs.map { id in
            (id, try waitForElement(identifier: id, root: app, timeout: 10, requireEnabled: false))
        }

        for (id, element) in elements {
            guard let elementFrame = frame(of: element),
                  windowFrame.insetBy(dx: -1, dy: -1).contains(elementFrame) else {
                throw HarnessError.elementOutsideWindow(id, sizeName)
            }
        }
        return elements.map(\.0)
    }

    private static func assertEmptyCleanupSelection(root: AXUIElement) throws {
        let count = try waitForElement(
            identifier: "cleanup-review.selection-count",
            root: root,
            timeout: 20,
            requireEnabled: false
        )
        guard find(named: "0 selected", root: count) != nil else {
            throw HarnessError.missingElement("Empty cleanup selection")
        }
    }

    private static func setSize(_ size: CGSize, window: AXUIElement) throws {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else { throw HarnessError.windowUnavailable }
        guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success else {
            throw HarnessError.windowUnavailable
        }
    }

    private static func captureWindow(pid: pid_t, output: URL) throws {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let id = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        })?[kCGWindowNumber as String] as? NSNumber else {
            throw HarnessError.windowUnavailable
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", id.stringValue, output.path]
        try process.run()
        process.waitUntilExit()
        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard process.terminationStatus == 0, size > 10_000 else {
            throw HarnessError.screenshotFailed(output.path)
        }
    }

    private static func checkpoint(
        _ name: String,
        started: Date,
        into checkpoints: inout [HarnessResult.Checkpoint],
        operation: () throws -> Void
    ) rethrows {
        try operation()
        let milliseconds = elapsed(started)
        checkpoints.append(.init(name: name, elapsedMilliseconds: milliseconds))
        logger.info("checkpoint=\(name, privacy: .public) elapsed_ms=\(milliseconds, privacy: .public)")
    }

    private static func elapsed(_ started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1_000)
    }

    private static func stringAttribute(_ name: String, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ name: String, element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if let bool = value as? Bool {
            return bool
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func elementArrayAttribute(_ name: String, element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func elementAttribute(_ name: String, element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let positionAX = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAX = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
