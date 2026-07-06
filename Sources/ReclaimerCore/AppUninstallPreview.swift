import Foundation

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
        relatedItems: [AppReviewItem],
        notes: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.selectedApp = selectedApp
        self.selector = selector
        self.bundleCandidate = bundleCandidate
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
        let protection = protectionReason(for: app)
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

    private static func protectionReason(for app: InstalledApp) -> String? {
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
