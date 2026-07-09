import CryptoKit
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct AppUninstallSelector: Codable, Hashable, Sendable {
    public let appPath: String?
    public let bundleIdentifier: String?
    public let displayName: String?

    public init(appPath: String? = nil, bundleIdentifier: String? = nil, displayName: String? = nil) {
        self.appPath = appPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool {
        [appPath, bundleIdentifier, displayName].allSatisfy { ($0 ?? "").isEmpty }
    }
}

public enum AppUninstallDisposition: String, Codable, Hashable, Sendable {
    case trashPreview
    case protectedAppBlocked
    case manualReviewOnly

    public var label: String {
        switch self {
        case .trashPreview: "Trash preview"
        case .protectedAppBlocked: "Protected app blocked"
        case .manualReviewOnly: "Manual review only"
        }
    }
}

public struct AppUninstallCandidate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let isDirectory: Bool
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let disposition: AppUninstallDisposition
    public let evidence: [Evidence]
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        isDirectory: Bool,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        disposition: AppUninstallDisposition,
        evidence: [Evidence],
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.disposition = disposition
        self.evidence = evidence
        self.guidance = guidance
    }
}

public struct AppUninstallPreview: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let selectedApp: InstalledApp
    public let selector: AppUninstallSelector
    public let bundleCandidate: AppUninstallCandidate
    public let bundleAuthorizationDigest: String?
    public let relatedItems: [AppReviewItem]
    public let relatedReviewBytes: Int64
    public let explicitTrashPreviewBytes: Int64
    public let totalBytesUnderReview: Int64
    public let notes: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        selectedApp: InstalledApp,
        selector: AppUninstallSelector,
        bundleCandidate: AppUninstallCandidate,
        bundleAuthorizationDigest: String? = nil,
        relatedItems: [AppReviewItem],
        notes: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.selectedApp = selectedApp
        self.selector = selector
        self.bundleCandidate = bundleCandidate
        self.bundleAuthorizationDigest = bundleAuthorizationDigest
        self.relatedItems = relatedItems.sorted { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        self.relatedReviewBytes = relatedItems.reduce(0) { $0 + $1.allocatedSize }
        self.explicitTrashPreviewBytes = bundleCandidate.disposition == .trashPreview ? bundleCandidate.allocatedSize : 0
        self.totalBytesUnderReview = bundleCandidate.allocatedSize + relatedItems.reduce(0) { $0 + $1.allocatedSize }
        self.notes = notes
        self.nonClaims = nonClaims
    }
}

public enum AppUninstallPreviewError: LocalizedError {
    case missingSelector
    case appNotFound(AppUninstallSelector)

    public var errorDescription: String? {
        switch self {
        case .missingSelector:
            "apps uninstall-preview requires --app PATH, --bundle-id ID, or --name NAME."
        case .appNotFound(let selector):
            "No installed app matched selector: \(selectorSummary(selector))."
        }
    }

    private func selectorSummary(_ selector: AppUninstallSelector) -> String {
        [
            selector.appPath.map { "app=\($0)" },
            selector.bundleIdentifier.map { "bundle-id=\($0)" },
            selector.displayName.map { "name=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

public enum AppUninstallProtection {
    public static func reason(for app: InstalledApp) -> String? {
        let lowerPath = app.path.lowercased()
        let lowerName = app.displayName.lowercased()
        let lowerBundle = app.bundleIdentifier?.lowercased() ?? ""
        if lowerPath.hasPrefix("/system/applications/") || lowerPath.hasPrefix("/system/library/") {
            return "System application bundle is outside Ryddi's uninstall scope."
        }
        if lowerBundle.hasPrefix("com.apple.") {
            return "Apple app bundle is protected by default."
        }
        if lowerName.contains("garageband") || lowerName.contains("logic") {
            return "GarageBand and Logic apps/assets are protected by default."
        }
        if lowerName == "photos" || lowerName == "music" || lowerName.contains("keychain") {
            return "Personal media, music, photo, and credential apps are protected by default."
        }
        return nil
    }
}

public enum AppUninstallPreviewBuilder {
    public static func build(
        report: AppReviewReport,
        selector: AppUninstallSelector,
        generatedAt: Date = Date()
    ) throws -> AppUninstallPreview {
        guard !selector.isEmpty else {
            throw AppUninstallPreviewError.missingSelector
        }
        guard let app = matchApp(in: report.installedApps, selector: selector) else {
            throw AppUninstallPreviewError.appNotFound(selector)
        }

        let related = report.installedAppGroups
            .first { group in
                group.appPath == app.path
                    || group.bundleIdentifier == app.bundleIdentifier
                    || group.id == app.id
            }?
            .items ?? []
        let bundleCandidate = bundleCandidate(for: app)
        let bundleURL = URL(fileURLWithPath: app.path).standardizedFileURL
        let bundleAuthorizationDigest = try? AppUninstallAuthorizationDigest.capture(
            app: app,
            bundleURL: bundleURL
        )
        let protected = bundleCandidate.disposition != .trashPreview
        let notes = [
            protected
                ? "The selected app bundle is protected or requires manual/vendor review; Ryddi will not present it as a Trash candidate."
                : "The selected app bundle can be reviewed as an explicit user-confirmed Trash candidate.",
            "Related support files are shown as context only. They are not selected for deletion by this preview.",
            "Use Finder, vendor uninstallers, and app-specific documentation for helpers, extensions, licenses, or background components."
        ]
        let nonClaims = [
            "No app bundle or related file was removed by this uninstall preview.",
            "Only the selected app bundle can be modeled as an explicit Trash candidate; related files remain review-only/manual.",
            "This preview does not quit the app, unload launch agents, stop helpers, revoke login items, or prove the app is inactive.",
            "Vendor uninstallers may be required for apps with privileged helpers, extensions, licenses, or background services.",
            "GarageBand, Logic, Photos, Music, Keychain, browser profiles, creative assets, and unknown app state stay protected or review-only."
        ]
        return AppUninstallPreview(
            createdAt: generatedAt,
            selectedApp: app,
            selector: selector,
            bundleCandidate: bundleCandidate,
            bundleAuthorizationDigest: bundleAuthorizationDigest,
            relatedItems: related,
            notes: notes,
            nonClaims: nonClaims
        )
    }

    private static func matchApp(in apps: [InstalledApp], selector: AppUninstallSelector) -> InstalledApp? {
        if let appPath = selector.appPath, !appPath.isEmpty {
            let standardized = URL(fileURLWithPath: appPath).standardizedFileURL.path
            if let app = apps.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == standardized }) {
                return app
            }
        }
        if let bundleIdentifier = selector.bundleIdentifier, !bundleIdentifier.isEmpty {
            if let app = apps.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
                return app
            }
        }
        if let displayName = selector.displayName, !displayName.isEmpty {
            let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = apps.first(where: { $0.displayName.caseInsensitiveCompare(normalized) == .orderedSame }) {
                return exact
            }
            return apps.first {
                $0.displayName.localizedCaseInsensitiveContains(normalized)
                    || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(normalized) ?? false)
            }
        }
        return nil
    }

    private static func bundleCandidate(for app: InstalledApp) -> AppUninstallCandidate {
        let url = URL(fileURLWithPath: app.path).standardizedFileURL
        let measurement = measure(url: url)
        let protection = AppUninstallProtection.reason(for: app)
        if let protection {
            return AppUninstallCandidate(
                path: app.path,
                displayName: app.displayName,
                logicalSize: measurement.logicalSize,
                allocatedSize: measurement.allocatedSize,
                isDirectory: measurement.isDirectory,
                safetyClass: .preserveByDefault,
                actionKind: .reportOnly,
                disposition: .protectedAppBlocked,
                evidence: [
                    Evidence(kind: "app-uninstall.protected", message: protection),
                    Evidence(kind: "app-uninstall.size", message: "Allocated size: \(ByteFormat.string(measurement.allocatedSize)); logical size: \(ByteFormat.string(measurement.logicalSize)).")
                ],
                guidance: [
                    "Do not uninstall this app through Ryddi's preview.",
                    "Use Apple's or the vendor's documented uninstall path if removal is truly intended."
                ]
            )
        }
        return AppUninstallCandidate(
            path: app.path,
            displayName: app.displayName,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            isDirectory: measurement.isDirectory,
            safetyClass: .reviewRequired,
            actionKind: .trash,
            disposition: .trashPreview,
            evidence: [
                Evidence(kind: "app-uninstall.bundle", message: "Selected installed app bundle; explicit user review is required before moving it to Trash."),
                Evidence(kind: "app-uninstall.size", message: "Allocated size: \(ByteFormat.string(measurement.allocatedSize)); logical size: \(ByteFormat.string(measurement.logicalSize)).")
            ],
            guidance: [
                "Quit the app and review open handles before moving the app bundle to Trash.",
                "Keep related support files until you confirm whether preferences, licenses, projects, or user data should be preserved."
            ]
        )
    }

    private struct Measurement {
        let logicalSize: Int64
        let allocatedSize: Int64
        let isDirectory: Bool
    }

    private static func measure(url: URL) -> Measurement {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return Measurement(logicalSize: 0, allocatedSize: 0, isDirectory: false)
        }
        if values.isSymbolicLink == true {
            return Measurement(logicalSize: 0, allocatedSize: 0, isDirectory: false)
        }
        guard values.isDirectory == true else {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return Measurement(logicalSize: logical, allocatedSize: allocated, isDirectory: false)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return Measurement(logicalSize: 0, allocatedSize: 0, isDirectory: true)
        }
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: keys) else { continue }
            if childValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if childValues.isDirectory == true { continue }
            logical += Int64(childValues.fileSize ?? 0)
            allocated += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return Measurement(logicalSize: logical, allocatedSize: allocated, isDirectory: true)
    }
}

private enum AppUninstallAuthorizationDigest {
    static func capture(app: InstalledApp, bundleURL: URL) throws -> String {
        let normalizedURL = bundleURL.standardizedFileURL
        let bundleIdentity = try FilesystemIdentity.capture(at: normalizedURL)
        guard bundleIdentity.isDirectory,
              !bundleIdentity.isSymbolicLink,
              !bundleIdentity.isVolume else {
            throw FilesystemIdentityError.missingStableIdentifier(normalizedURL.path)
        }

        let infoURL = normalizedURL.appendingPathComponent("Contents/Info.plist")
        let infoIdentity = try FilesystemIdentity.capture(at: infoURL)
        guard infoIdentity.isRegularFile,
              !infoIdentity.isSymbolicLink,
              !infoIdentity.isPackage,
              !infoIdentity.isVolume else {
            throw FilesystemIdentityError.missingStableIdentifier(infoURL.path)
        }

        let executableIdentity: String
        if let executableName = app.executableName, !executableName.isEmpty {
            let executableURL = normalizedURL.appendingPathComponent("Contents/MacOS/\(executableName)")
            let identity = try FilesystemIdentity.capture(at: executableURL)
            guard identity.isRegularFile,
                  !identity.isSymbolicLink,
                  !identity.isPackage,
                  !identity.isVolume else {
                throw FilesystemIdentityError.missingStableIdentifier(executableURL.path)
            }
            executableIdentity = identity.digestComponent
        } else {
            executableIdentity = "no-executable"
        }

        let payload = [
            "ryddi.app-uninstall.authorization.v1",
            normalizedURL.path,
            app.bundleIdentifier ?? "no-bundle-identifier",
            app.displayName,
            app.version ?? "no-version",
            app.executableName ?? "no-executable-name",
            app.modificationDate.map { String($0.timeIntervalSince1970) } ?? "no-app-mtime",
            bundleIdentity.digestComponent,
            infoIdentity.digestComponent,
            executableIdentity
        ].joined(separator: "\u{001e}")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AppUninstallExecutionReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let previewID: String
    public let mode: String
    public let appDisplayName: String
    public let bundleIdentifier: String?
    public let bundlePath: String
    public let actionKind: ActionKind
    public let disposition: AppUninstallDisposition
    public let selectedBundleBytes: Int64
    public let relatedReviewBytes: Int64
    public let userConfirmed: Bool
    public let status: String
    public let message: String
    public let resultingTrashPath: String?
    public let authorizationDigest: String?
    public let errors: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        previewID: String,
        mode: String,
        appDisplayName: String,
        bundleIdentifier: String?,
        bundlePath: String,
        actionKind: ActionKind,
        disposition: AppUninstallDisposition,
        selectedBundleBytes: Int64,
        relatedReviewBytes: Int64,
        userConfirmed: Bool,
        status: String,
        message: String,
        resultingTrashPath: String? = nil,
        authorizationDigest: String? = nil,
        errors: [String] = [],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.previewID = previewID
        self.mode = mode
        self.appDisplayName = appDisplayName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.actionKind = actionKind
        self.disposition = disposition
        self.selectedBundleBytes = selectedBundleBytes
        self.relatedReviewBytes = relatedReviewBytes
        self.userConfirmed = userConfirmed
        self.status = status
        self.message = message
        self.resultingTrashPath = resultingTrashPath
        self.authorizationDigest = authorizationDigest
        self.errors = errors
        self.nonClaims = nonClaims
    }
}

public struct AppUninstallPerformAuthorization: Codable, Hashable, Sendable {
    public let dryRunReceipt: AppUninstallExecutionReceipt

    public init(dryRunReceipt: AppUninstallExecutionReceipt) {
        self.dryRunReceipt = dryRunReceipt
    }
}

public struct AppUninstallExecutorConfiguration: Sendable {
    /// App-uninstall dry-run authorization is never valid for more than 15 minutes.
    public static let maximumDryRunAuthorizationAge: TimeInterval = 15 * 60

    public let userPathPolicy: UserPathPolicy
    public let allowedAppRoots: [URL]
    public let dryRunAuthorizationAge: TimeInterval

    public init(
        userPathPolicy: UserPathPolicy = .empty,
        allowedAppRoots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ],
        dryRunAuthorizationAge: TimeInterval = Self.maximumDryRunAuthorizationAge
    ) {
        self.userPathPolicy = userPathPolicy
        self.allowedAppRoots = allowedAppRoots.map(\.standardizedFileURL)
        self.dryRunAuthorizationAge = max(
            1,
            min(dryRunAuthorizationAge, Self.maximumDryRunAuthorizationAge)
        )
    }
}

public protocol AppBundleTrashing: Sendable {
    func trashItem(at url: URL) throws -> URL?
}

public struct FileManagerAppBundleTrasher: AppBundleTrashing {
    public init() {}

    public func trashItem(at url: URL) throws -> URL? {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        return trashedURL as URL?
    }
}

public protocol RunningApplicationChecking: Sendable {
    func isAppRunning(bundleIdentifier: String?, executableName: String?, displayName: String) -> Bool
}

public struct SystemRunningApplicationChecker: RunningApplicationChecking {
    public init() {}

    public func isAppRunning(bundleIdentifier: String?, executableName: String?, displayName: String) -> Bool {
        #if canImport(AppKit)
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return true
        }
        let executable = executableName?.lowercased()
        let display = displayName.lowercased()
        return NSWorkspace.shared.runningApplications.contains { application in
            let localized = application.localizedName?.lowercased()
            if let executable, localized == executable {
                return true
            }
            return localized == display
        }
        #else
        return false
        #endif
    }
}

public final class AppUninstallExecutor: @unchecked Sendable {
    private let fileManager: FileManager
    private let openFileChecker: OpenFileChecking
    private let runningApplicationChecker: RunningApplicationChecking
    private let configuration: AppUninstallExecutorConfiguration
    private let appBundleTrasher: any AppBundleTrashing
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker(),
        runningApplicationChecker: RunningApplicationChecking = SystemRunningApplicationChecker(),
        configuration: AppUninstallExecutorConfiguration = AppUninstallExecutorConfiguration(),
        appBundleTrasher: any AppBundleTrashing = FileManagerAppBundleTrasher(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.openFileChecker = openFileChecker
        self.runningApplicationChecker = runningApplicationChecker
        self.configuration = configuration
        self.appBundleTrasher = appBundleTrasher
        self.now = now
    }

    public func execute(
        preview: AppUninstallPreview,
        mode: ExecutionMode,
        userConfirmed: Bool,
        authorization: AppUninstallPerformAuthorization? = nil
    ) -> AppUninstallExecutionReceipt {
        let candidate = preview.bundleCandidate
        let url = URL(fileURLWithPath: candidate.path).standardizedFileURL

        if candidate.disposition != .trashPreview || candidate.actionKind != .trash {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "skipped",
                message: "Selected app bundle is protected or review-only; no Trash action is available."
            )
        }
        if let rule = configuration.userPathPolicy.matchingRule(for: candidate.path, kind: .exclude) {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Blocked by user exclusion rule at \(rule.path).")
        }
        if let rule = configuration.userPathPolicy.matchingRule(for: candidate.path, kind: .protect) {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Blocked by user protection rule at \(rule.path).")
        }
        guard url.pathExtension.lowercased() == "app" else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Only .app bundles can use app uninstall Trash execution.")
        }
        guard isInAllowedAppRoot(url) else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App bundle is outside the allowed app roots for Trash execution.")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App bundle no longer exists.")
        }
        guard let current = currentInstalledApp(at: url) else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Could not re-read app bundle metadata before action.")
        }
        if let protection = AppUninstallProtection.reason(for: current) {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: protection)
        }
        if runningApplicationChecker.isAppRunning(
            bundleIdentifier: current.bundleIdentifier,
            executableName: current.executableName,
            displayName: current.displayName
        ) {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App appears to be running; quit it before moving the bundle to Trash.")
        }
        guard !isSymbolicLink(url) else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App bundle path changed into a symbolic link.")
        }
        let openStatus = openFileChecker.status(for: url)
        if openStatus.isOpen {
            let processes = openStatus.processSummary.joined(separator: ", ")
            let suffix = processes.isEmpty ? "" : " Open process(es): \(processes)."
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Open-file check blocked app uninstall.\(suffix)")
        }
        if let checkFailed = openStatus.checkFailed {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Open-file check failed: \(checkFailed)")
        }
        let currentAuthorizationDigest: String
        do {
            currentAuthorizationDigest = try AppUninstallAuthorizationDigest.capture(
                app: current,
                bundleURL: url
            )
        } catch {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "skipped",
                message: "Could not capture stable app-bundle identity and metadata for authorization: \(error.localizedDescription)"
            )
        }
        guard let previewAuthorizationDigest = preview.bundleAuthorizationDigest else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App uninstall preview lacks stable bundle authorization evidence; rebuild the preview.")
        }
        guard previewAuthorizationDigest == currentAuthorizationDigest else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "App bundle identity or metadata changed since preview; rebuild the preview and dry run.")
        }
        guard mode == .perform else {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "dry-run",
                message: "Would move selected app bundle to Trash. Related support files would remain untouched.",
                authorizationDigest: currentAuthorizationDigest
            )
        }
        guard userConfirmed else {
            return receipt(preview: preview, mode: mode, userConfirmed: userConfirmed, status: "skipped", message: "Moving an app bundle to Trash requires explicit --yes/user confirmation.")
        }
        if let blockReason = authorizationBlockReason(
            authorization: authorization,
            preview: preview,
            currentApp: current,
            currentAuthorizationDigest: currentAuthorizationDigest,
            now: now()
        ) {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "skipped",
                message: blockReason
            )
        }
        guard let finalApp = currentInstalledApp(at: url),
              let finalAuthorizationDigest = try? AppUninstallAuthorizationDigest.capture(
                  app: finalApp,
                  bundleURL: url
              ),
              finalAuthorizationDigest == currentAuthorizationDigest else {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "skipped",
                message: "App bundle identity or metadata changed during final authorization; rebuild the preview and dry run."
            )
        }

        do {
            let trashedURL = try appBundleTrasher.trashItem(at: url)
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "done",
                message: "Moved selected app bundle to Trash. Related support files were not touched.",
                resultingTrashPath: trashedURL?.path,
                authorizationDigest: currentAuthorizationDigest
            )
        } catch {
            return receipt(
                preview: preview,
                mode: mode,
                userConfirmed: userConfirmed,
                status: "error",
                message: error.localizedDescription,
                errors: [error.localizedDescription]
            )
        }
    }

    private func receipt(
        preview: AppUninstallPreview,
        mode: ExecutionMode,
        userConfirmed: Bool,
        status: String,
        message: String,
        resultingTrashPath: String? = nil,
        authorizationDigest: String? = nil,
        errors: [String] = []
    ) -> AppUninstallExecutionReceipt {
        AppUninstallExecutionReceipt(
            createdAt: now(),
            previewID: preview.id,
            mode: mode.rawValue,
            appDisplayName: preview.selectedApp.displayName,
            bundleIdentifier: preview.selectedApp.bundleIdentifier,
            bundlePath: preview.bundleCandidate.path,
            actionKind: preview.bundleCandidate.actionKind,
            disposition: preview.bundleCandidate.disposition,
            selectedBundleBytes: preview.bundleCandidate.allocatedSize,
            relatedReviewBytes: preview.relatedReviewBytes,
            userConfirmed: userConfirmed,
            status: status,
            message: message,
            resultingTrashPath: resultingTrashPath,
            authorizationDigest: authorizationDigest,
            errors: errors,
            nonClaims: [
                "Only the selected app bundle is in scope for this receipt; related support files were not moved or deleted.",
                "If the app bundle was moved to Trash, restore it from Finder Trash before emptying Trash.",
                "Trash does not guarantee immediate free-space recovery until the user empties Trash and APFS accounting settles.",
                "Ryddi did not quit the app, unload helpers, remove launch agents, revoke login items, or run vendor uninstallers.",
                "Preferences, licenses, app support data, containers, saved state, user documents, and creative assets remain review-only/manual."
            ]
        )
    }

    private func authorizationBlockReason(
        authorization: AppUninstallPerformAuthorization?,
        preview: AppUninstallPreview,
        currentApp: InstalledApp,
        currentAuthorizationDigest: String,
        now: Date
    ) -> String? {
        guard let authorization else {
            return "App uninstall perform requires a fresh matching dry-run authorization receipt. Run app uninstall dry run with audit saving first."
        }
        let dryRun = authorization.dryRunReceipt
        guard dryRun.mode == ExecutionMode.dryRun.rawValue,
              dryRun.status == "dry-run",
              dryRun.errors.isEmpty,
              dryRun.resultingTrashPath == nil,
              dryRun.actionKind == .trash,
              dryRun.disposition == .trashPreview else {
            return "App uninstall authorization is not a clean dry-run receipt."
        }
        let expectedPath = URL(fileURLWithPath: preview.bundleCandidate.path).standardizedFileURL.path
        let authorizedPath = URL(fileURLWithPath: dryRun.bundlePath).standardizedFileURL.path
        guard authorizedPath == expectedPath else {
            return "App uninstall dry-run authorization belongs to a different app bundle path."
        }
        guard dryRun.bundleIdentifier == currentApp.bundleIdentifier else {
            return "App uninstall dry-run authorization belongs to different bundle metadata."
        }
        let age = now.timeIntervalSince(dryRun.createdAt)
        guard age >= 0, age <= configuration.dryRunAuthorizationAge else {
            return "App uninstall dry-run authorization is stale; run the dry run again."
        }
        guard dryRun.authorizationDigest == currentAuthorizationDigest else {
            return "App uninstall dry-run authorization does not match the current bundle identity or metadata."
        }
        return nil
    }

    private func currentInstalledApp(at url: URL) -> InstalledApp? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: infoURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let displayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        return InstalledApp(
            id: bundleIdentifier ?? url.path,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: info?["CFBundleShortVersionString"] as? String,
            executableName: info?["CFBundleExecutable"] as? String,
            path: url.path,
            modificationDate: values?.contentModificationDate
        )
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isInAllowedAppRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return configuration.allowedAppRoots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }
}

public enum AppUninstallPreviewMarkdownBuilder {
    public static func build(
        preview: AppUninstallPreview,
        title: String = "Ryddi App Uninstall Preview",
        itemLimit: Int = 25,
        privacy: ReportPrivacyOptions = .default
    ) -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Preview id: `\(preview.id)`")
        lines.append("- Generated: \(isoString(preview.createdAt))")
        lines.append("- App: \(preview.selectedApp.displayName)")
        if let bundleIdentifier = preview.selectedApp.bundleIdentifier {
            lines.append("- Bundle id: `\(bundleIdentifier)`")
        }
        lines.append("")
        lines.append("## Summary")
        lines.append(markdownTable(
            headers: ["Metric", "Value"],
            rows: [
                ["App bundle action", "\(preview.bundleCandidate.actionKind.label) / \(preview.bundleCandidate.disposition.label)"],
                ["Explicit Trash preview bytes", ByteFormat.string(preview.explicitTrashPreviewBytes)],
                ["Related review bytes", ByteFormat.string(preview.relatedReviewBytes)],
                ["Total bytes under review", ByteFormat.string(preview.totalBytesUnderReview)]
            ]
        ))
        lines.append("")
        lines.append("## App Bundle")
        lines.append(markdownTable(
            headers: ["Allocated", "Safety", "Action", "Disposition", "Path"],
            rows: [[
                ByteFormat.string(preview.bundleCandidate.allocatedSize),
                preview.bundleCandidate.safetyClass.label,
                preview.bundleCandidate.actionKind.label,
                preview.bundleCandidate.disposition.label,
                privacy.displayPath(preview.bundleCandidate.path)
            ]]
        ))
        lines.append("")
        if !preview.bundleCandidate.guidance.isEmpty {
            lines.append("### Bundle Guidance")
            for guidance in preview.bundleCandidate.guidance {
                lines.append("- \(privacy.displayText(guidance, knownPaths: [preview.bundleCandidate.path]))")
            }
            lines.append("")
        }

        lines.append("## Related Files")
        if preview.relatedItems.isEmpty {
            lines.append("No related support files matched the current app-review threshold.")
        } else {
            lines.append(markdownTable(
                headers: ["Allocated", "Safety", "Action", "Category", "Path"],
                rows: preview.relatedItems.prefix(itemLimit).map { item in
                    [
                        ByteFormat.string(item.allocatedSize),
                        item.safetyClass.label,
                        item.actionKind.label,
                        item.category,
                        privacy.displayPath(item.path)
                    ]
                }
            ))
            if preview.relatedItems.count > itemLimit {
                lines.append("")
                lines.append("_\(preview.relatedItems.count - itemLimit) more related item(s) omitted by report limit._")
            }
        }
        lines.append("")

        lines.append("## Notes")
        for note in preview.notes {
            lines.append("- \(note)")
        }
        lines.append("")
        lines.append("## Explicit Non-Claims")
        for note in preview.nonClaims {
            lines.append("- \(note)")
        }
        if privacy.pathStyle != .full || privacy.redactUserText {
            lines.append("- Report privacy was applied (\(privacy.summary)); saved local audit data may still contain full original paths.")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func markdownTable(headers: [String], rows: [[String]]) -> String {
        let header = "| " + headers.joined(separator: " | ") + " |"
        let separator = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + row.map(escapeCell).joined(separator: " | ") + " |"
        }
        return ([header, separator] + body).joined(separator: "\n")
    }

    private static func escapeCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
