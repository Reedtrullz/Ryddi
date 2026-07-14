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
    let originalCandidateMissing: Bool
    let executionResultVisible: Bool
    let verificationActionVisible: Bool
    let candidateRowRemoved: Bool
    let reclaimActionHidden: Bool
}

enum HarnessError: Error, CustomStringConvertible {
    case usage(String)
    case accessibilityPermission
    case appNotRunning(String)
    case missingElement(String)
    case disabledElement(String)
    case actionFailed(String, AXError)
    case windowUnavailable
    case screenshotFailed(String)
    case candidateStillExists(String)
    case elementOutsideWindow(String, String)

    var description: String {
        switch self {
        case .usage(let message): message
        case .accessibilityPermission:
            "Accessibility permission is required for the packaged-app AX release lane."
        case .appNotRunning(let id): "No running application found for bundle identifier \(id)."
        case .missingElement(let id): "Timed out waiting for AX identifier \(id)."
        case .disabledElement(let id): "AX element \(id) remained disabled."
        case .actionFailed(let id, let error): "AX action failed for \(id): \(error.rawValue)."
        case .windowUnavailable: "The packaged app did not expose a main AX window."
        case .screenshotFailed(let path): "Failed to capture a non-empty screenshot at \(path)."
        case .candidateStillExists(let path): "Confirmed Trash candidate still exists at \(path)."
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
            _ = try waitForElement(identifier: "summary.scan-button", root: app, timeout: 15, requireEnabled: true)
        }
        try checkpoint("scan", started: started, into: &checkpoints) {
            try press("summary.scan-button", root: app)
            _ = try waitForElement(identifier: "summary.plan-button", root: app, timeout: 90, requireEnabled: true)
        }
        try checkpoint("plan", started: started, into: &checkpoints) {
            try press("summary.plan-button", root: app)
            _ = try waitForElement(identifier: "summary.dry-run-button", root: app, timeout: 45, requireEnabled: true)
        }
        try checkpoint("dry-run", started: started, into: &checkpoints) {
            try press("summary.dry-run-button", root: app)
            _ = try waitForElement(identifier: "summary.reclaim-button", root: app, timeout: 60, requireEnabled: true)
            _ = try waitForText(options.candidatePath, root: app, timeout: 20)
        }
        try checkpoint("confirmation", started: started, into: &checkpoints) {
            try press("summary.reclaim-button", root: app)
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
        _ = try waitForElement(
            identifier: "summary.verify-cleanup-button",
            root: app,
            timeout: 30,
            requireEnabled: true
        )
        try assertCandidateRowMissing(path: options.candidatePath, root: app, timeout: 20)
        try assertElementMissing(identifier: "summary.reclaim-button", root: app, timeout: 20)
        guard !FileManager.default.fileExists(atPath: options.candidatePath) else {
            throw HarnessError.candidateStillExists(options.candidatePath)
        }
        checkpoints.append(.init(name: "trash-result", elapsedMilliseconds: elapsed(started)))

        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        let responsiveProof = try captureResponsiveProof(app: app, pid: running.processIdentifier, output: options.output)
        let result = HarnessResult(
            bundleIdentifier: options.bundleIdentifier,
            processIdentifier: running.processIdentifier,
            checkpoints: checkpoints,
            screenshots: responsiveProof.screenshots.map(\.lastPathComponent),
            responsiveChecks: responsiveProof.checks,
            originalCandidateMissing: true,
            executionResultVisible: true,
            verificationActionVisible: true,
            candidateRowRemoved: true,
            reclaimActionHidden: true
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

    private static func find(identifier: String, root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty && visited < 8_000 {
            let element = queue.removeFirst()
            visited += 1
            if stringAttribute(kAXIdentifierAttribute as String, element: element) == identifier {
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
        throw HarnessError.disabledElement(identifier)
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
        var visited = 0
        while !queue.isEmpty && visited < 8_000 {
            let element = queue.removeFirst()
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

    private static func waitForText(
        _ text: String,
        root: AXUIElement,
        timeout: TimeInterval
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = findText(text, root: root) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        throw HarnessError.missingElement(text)
    }

    private static func dumpTree(root: AXUIElement) {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        FileHandle.standardError.write(Data("AX hierarchy dump:\n".utf8))
        while !queue.isEmpty && visited < 400 {
            let (element, depth) = queue.removeFirst()
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

    private static func captureResponsiveProof(
        app: AXUIElement,
        pid: pid_t,
        output: URL
    ) throws -> (screenshots: [URL], checks: [HarnessResult.ResponsiveCheck]) {
        guard let window = elementArrayAttribute(kAXWindowsAttribute as String, element: app).first else {
            throw HarnessError.windowUnavailable
        }
        let sizes: [(String, CGSize)] = [
            ("minimum", CGSize(width: 980, height: 680)),
            ("regular", CGSize(width: 1_280, height: 800)),
            ("wide", CGSize(width: 1_600, height: 1_000))
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

    private static func assertResponsiveContainment(
        app: AXUIElement,
        window: AXUIElement,
        sizeName: String
    ) throws -> [String] {
        guard let windowFrame = frame(of: window) else { throw HarnessError.windowUnavailable }
        let fixedIDs = ["dashboard-sidebar", "scan-button", "cleanup-flow-status"]
        let primaryIDs = [
            "summary.verify-cleanup-button",
            "summary.reclaim-button",
            "summary.manual-review-button",
            "summary.dry-run-button",
            "summary.plan-button",
            "summary.scan-button"
        ]
        var elements: [(String, AXUIElement)] = try fixedIDs.map { id in
            (id, try waitForElement(identifier: id, root: app, timeout: 10, requireEnabled: false))
        }
        if let primaryID = primaryIDs.first(where: { find(identifier: $0, root: app) != nil }),
           let primary = find(identifier: primaryID, root: app) {
            elements.append((primaryID, primary))
        } else {
            throw HarnessError.missingElement("summary primary action")
        }

        for (id, element) in elements {
            guard let elementFrame = frame(of: element),
                  windowFrame.insetBy(dx: -1, dy: -1).contains(elementFrame) else {
                throw HarnessError.elementOutsideWindow(id, sizeName)
            }
        }
        return elements.map(\.0)
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
        return value as? Bool
    }

    private static func elementArrayAttribute(_ name: String, element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
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
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
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
