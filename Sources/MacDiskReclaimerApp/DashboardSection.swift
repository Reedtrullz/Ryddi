import Foundation
import SwiftUI

enum DashboardSidebarGroup: String, CaseIterable, Identifiable {
    case start = "Start"
    case generalMac = "General Mac"
    case developer = "Developer"
    case trust = "Trust & Recovery"

    var id: String { rawValue }
}

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case summary = "Summary"
    case queues = "Queues"
    case largeOld = "LargeOld"
    case apps = "Apps"
    case downloads = "Downloads"
    case duplicates = "Duplicates"
    case browsers = "Browsers"
    case deviceBackups = "DeviceBackups"
    case trash = "Trash"
    case packages = "Packages"
    case projects = "Projects"
    case xcode = "Xcode"
    case containers = "Containers"
    case remoteTargets = "RemoteTargets"
    case agents = "Agents"
    case permissions = "Permissions"
    case active = "Active"
    case scopes = "Scopes"
    case policy = "Policy"
    case audit = "Audit"
    case recovery = "Recovery"
    case holding = "Holding"
    case automation = "Automation"
    case rules = "Rules"
    case features = "Features"
    case finding = "Finding"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .queues: "Cleanup Flow"
        case .largeOld: "Large & Old Files"
        case .apps: "Apps & Leftovers"
        case .downloads: "Downloads"
        case .duplicates: "Duplicates"
        case .browsers: "Browser Caches"
        case .deviceBackups: "Device Backups"
        case .trash: "Trash"
        case .packages: "Package Caches"
        case .projects: "Project Dependencies"
        case .xcode: "Xcode"
        case .containers: "Containers"
        case .remoteTargets: "Remote Targets"
        case .agents: "AI Agent Storage"
        case .permissions: "Permissions"
        case .active: "Active Handles"
        case .scopes: "Scope Sets"
        case .policy: "Protections"
        case .audit: "Audit History"
        case .recovery: "Recovery Center"
        case .holding: "Holding Area"
        case .automation: "Automation"
        case .rules: "Rule Catalog"
        case .features: "Feature Matrix"
        case .finding: "Finding"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "gauge.with.dots.needle"
        case .queues: "tray.full"
        case .largeOld: "archivebox"
        case .apps: "app.dashed"
        case .downloads: "arrow.down.circle"
        case .duplicates: "doc.on.doc"
        case .browsers: "globe"
        case .deviceBackups: "iphone"
        case .trash: "trash"
        case .packages: "shippingbox"
        case .projects: "folder"
        case .xcode: "hammer"
        case .containers: "cube.box"
        case .remoteTargets: "server.rack"
        case .agents: "brain.head.profile"
        case .permissions: "lock.shield"
        case .active: "waveform.path.ecg"
        case .scopes: "scope"
        case .policy: "hand.raised"
        case .audit: "clock.arrow.circlepath"
        case .recovery: "arrow.uturn.backward.circle"
        case .holding: "tray"
        case .automation: "calendar.badge.clock"
        case .rules: "list.bullet.rectangle"
        case .features: "square.grid.2x2"
        case .finding: "doc.text.magnifyingglass"
        }
    }

    var sidebarGroup: DashboardSidebarGroup? {
        switch self {
        case .summary, .queues, .largeOld:
            .start
        case .apps, .downloads, .duplicates, .browsers, .deviceBackups, .trash:
            .generalMac
        case .packages, .projects, .xcode, .containers, .remoteTargets, .agents:
            .developer
        case .permissions, .active, .scopes, .policy, .audit, .recovery, .holding, .automation, .rules, .features:
            .trust
        case .finding:
            nil
        }
    }

    static var sidebarSections: [DashboardSection] {
        allCases.filter { $0.sidebarGroup != nil }
    }

    static func fromLegacyID(_ rawValue: String) -> DashboardSection {
        DashboardSection(rawValue: rawValue) ?? .summary
    }
}

enum DashboardLaunchOptions {
    static var isE2EModeRequested: Bool {
        ProcessInfo.processInfo.environment["RYDDI_E2E_MODE"] == "1"
    }

    private static let e2eValidation: (root: URL?, error: String?) = {
        guard isE2EModeRequested else { return (nil, nil) }
        guard let rawRoot = ProcessInfo.processInfo.environment["RYDDI_E2E_SCOPE_ROOT"],
              !rawRoot.isEmpty,
              NSString(string: rawRoot).isAbsolutePath else {
            return (nil, "RYDDI_E2E_SCOPE_ROOT must be an existing absolute temporary path.")
        }

        let requestedURL = URL(fileURLWithPath: rawRoot).standardizedFileURL
        let requestedPath = requestedURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let protectedPaths: Set<String> = [
            "/",
            homePath,
            "/Users",
            "/Applications",
            "/Library",
            "/System"
        ]
        guard !protectedPaths.contains(requestedPath) else {
            return (nil, "RYDDI_E2E_SCOPE_ROOT points at a protected path.")
        }
        guard (try? requestedURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return (nil, "RYDDI_E2E_SCOPE_ROOT must not be a symbolic link.")
        }

        let resolvedURL = requestedURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPath = resolvedURL.path
        let temporaryPath = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard resolvedPath.hasPrefix(temporaryPath + "/") else {
            return (nil, "RYDDI_E2E_SCOPE_ROOT must be below the current temporary directory.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (nil, "RYDDI_E2E_SCOPE_ROOT must be an existing directory.")
        }
        return (resolvedURL, nil)
    }()

    static var e2eScopeRoot: URL? {
        e2eValidation.root
    }

    static var e2eValidationError: String? {
        e2eValidation.error
    }

    static var isScreenshotDemo: Bool {
        ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_DEMO"] == "1"
    }

    static var initialSection: DashboardSection {
        guard isScreenshotDemo else { return .summary }
        let raw = ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_SECTION"] ?? DashboardSection.summary.rawValue
        switch raw.lowercased() {
        case "queues", "review-queues":
            return .queues
        case "apps", "app-review", "apps-and-leftovers":
            return .apps
        case "remote", "remote-targets":
            return .remoteTargets
        default:
            return DashboardSection.fromLegacyID(raw)
        }
    }

    static var initialSectionID: String {
        initialSection.rawValue
    }
}
