import Foundation

public struct ScopeTemplate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let summary: String
    public let recommendedUse: String
    public let scopes: [ScanScope]
    public let nonClaims: [String]

    public init(
        id: String,
        name: String,
        group: String,
        summary: String,
        recommendedUse: String,
        scopes: [ScanScope],
        nonClaims: [String] = ScopeTemplateCatalog.defaultNonClaims
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.summary = summary
        self.recommendedUse = recommendedUse
        self.scopes = DefaultScopes.customPlan(scopes: scopes).scopes
        self.nonClaims = nonClaims
    }

    public var plan: ScanScopePlan {
        DefaultScopes.customPlan(
            label: name,
            summary: summary,
            scopes: scopes,
            nonClaims: nonClaims
        )
    }
}

public enum ScopeTemplateError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let reference):
            return "No built-in scope template found for \(reference)."
        }
    }
}

public enum ScopeTemplateCatalog {
    public static let defaultNonClaims = [
        "Scope templates are suggested scan roots only; they do not change Ryddi's safety rules or cleanup protections.",
        "Scanning a template does not mean Ryddi will select personal files for cleanup.",
        "Some template roots may be missing on a Mac, and missing roots are skipped unless unavailable scopes are explicitly requested."
    ]

    public static func all(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScopeTemplate] {
        [
            weeklyGeneral(home: home, includeUnavailable: includeUnavailable),
            personalLargeFiles(home: home, includeUnavailable: includeUnavailable),
            appLeftovers(home: home, includeUnavailable: includeUnavailable),
            browserCaches(home: home, includeUnavailable: includeUnavailable),
            packageCaches(home: home, includeUnavailable: includeUnavailable),
            aiAgentStorage(home: home, includeUnavailable: includeUnavailable),
            developerMaintenance(home: home, includeUnavailable: includeUnavailable)
        ]
    }

    public static func find(
        _ reference: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) throws -> ScopeTemplate {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ScopeTemplateError.notFound(reference) }
        let lower = normalized.lowercased()
        let templates = all(home: home, includeUnavailable: includeUnavailable)
        if let exact = templates.first(where: { $0.id == lower || $0.name.lowercased() == lower }) {
            return exact
        }
        if let prefix = templates.first(where: { $0.id.hasPrefix(lower) }) {
            return prefix
        }
        throw ScopeTemplateError.notFound(reference)
    }

    public static func plan(
        reference: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) throws -> ScanScopePlan {
        try find(reference, home: home, includeUnavailable: includeUnavailable).plan
    }

    private static func weeklyGeneral(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "weekly-general",
            name: "Weekly General Review",
            group: "General Mac",
            summary: "A focused recurring review of common user-visible cleanup roots: Downloads, Desktop, user caches, logs, and Trash.",
            recommendedUse: "Weekly or biweekly report-first maintenance.",
            scopes: scopes(
                [
                    ("Downloads review", home.appendingPathComponent("Downloads")),
                    ("Desktop review", home.appendingPathComponent("Desktop")),
                    ("User caches", home.appendingPathComponent("Library/Caches")),
                    ("User logs", home.appendingPathComponent("Library/Logs")),
                    ("Trash review", home.appendingPathComponent(".Trash"))
                ],
                includeUnavailable: includeUnavailable
            )
        )
    }

    private static func personalLargeFiles(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "personal-large-files",
            name: "Personal Large Files",
            group: "General Mac",
            summary: "Review-heavy personal roots where large downloads, media, archives, and old documents commonly accumulate.",
            recommendedUse: "Monthly review before archiving, external-drive moves, or manual Trash decisions.",
            scopes: scopes(
                [
                    ("Downloads review", home.appendingPathComponent("Downloads")),
                    ("Desktop review", home.appendingPathComponent("Desktop")),
                    ("Documents review", home.appendingPathComponent("Documents")),
                    ("Movies review", home.appendingPathComponent("Movies")),
                    ("Pictures review", home.appendingPathComponent("Pictures")),
                    ("Music review", home.appendingPathComponent("Music"))
                ],
                includeUnavailable: includeUnavailable
            )
        )
    }

    private static func appLeftovers(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "app-leftovers",
            name: "Apps And Leftovers",
            group: "Apps",
            summary: "Installed app bundles plus common per-user Library roots where support files, containers, preferences, saved state, and launch agents live.",
            recommendedUse: "Review before uninstalling apps or investigating app-support bloat.",
            scopes: scopes(
                [
                    ("Applications", URL(fileURLWithPath: "/Applications")),
                    ("User Applications", home.appendingPathComponent("Applications")),
                    ("Application Support review", home.appendingPathComponent("Library/Application Support")),
                    ("User caches", home.appendingPathComponent("Library/Caches")),
                    ("Preferences review", home.appendingPathComponent("Library/Preferences")),
                    ("Containers review", home.appendingPathComponent("Library/Containers")),
                    ("Saved Application State", home.appendingPathComponent("Library/Saved Application State")),
                    ("User LaunchAgents", home.appendingPathComponent("Library/LaunchAgents"))
                ],
                includeUnavailable: includeUnavailable,
                removingNestedChildren: true
            )
        )
    }

    private static func browserCaches(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "browser-caches",
            name: "Browser Cache Review",
            group: "General Mac",
            summary: "Browser cache roots separated from browser profiles, cookies, bookmarks, and history.",
            recommendedUse: "Use when browser cache growth is visible, then quit browsers before cleanup.",
            scopes: scopes(
                [
                    ("Chrome cache", home.appendingPathComponent("Library/Caches/Google/Chrome")),
                    ("Chrome app cache", home.appendingPathComponent("Library/Caches/com.google.Chrome")),
                    ("Firefox cache", home.appendingPathComponent("Library/Caches/Firefox")),
                    ("Safari cache", home.appendingPathComponent("Library/Caches/com.apple.Safari")),
                    ("WebKit cache", home.appendingPathComponent("Library/Caches/com.apple.WebKit"))
                ],
                includeUnavailable: includeUnavailable
            )
        )
    }

    private static func packageCaches(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "package-caches",
            name: "Package Manager Caches",
            group: "Developer",
            summary: "Common package-manager and build cache roots for Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, and SwiftPM.",
            recommendedUse: "Developer maintenance review before using native cleanup commands.",
            scopes: scopes(
                [
                    ("Homebrew cache", home.appendingPathComponent("Library/Caches/Homebrew")),
                    ("npm cache", home.appendingPathComponent(".npm")),
                    ("pnpm store", home.appendingPathComponent("Library/pnpm/store")),
                    ("Yarn cache", home.appendingPathComponent("Library/Caches/Yarn")),
                    ("pip cache", home.appendingPathComponent("Library/Caches/pip")),
                    ("Cargo cache", home.appendingPathComponent(".cargo")),
                    ("Go modules", home.appendingPathComponent("go/pkg/mod")),
                    ("Gradle cache", home.appendingPathComponent(".gradle/caches")),
                    ("Maven cache", home.appendingPathComponent(".m2/repository")),
                    ("CocoaPods cache", home.appendingPathComponent("Library/Caches/CocoaPods")),
                    ("SwiftPM cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm"))
                ],
                includeUnavailable: includeUnavailable
            )
        )
    }

    private static func aiAgentStorage(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "ai-agent-storage",
            name: "AI Agent Storage",
            group: "Developer",
            summary: "Codex, Claude, Cursor, Windsurf, and Ollama storage roots, with cache/history/protected-state rules applied by the normal rule pack.",
            recommendedUse: "Frequent review on machines where agent sessions, logs, caches, or local models grow quickly.",
            scopes: DefaultScopes.aiAgentStorage(home: home, includeUnavailable: includeUnavailable)
        )
    }

    private static func developerMaintenance(home: URL, includeUnavailable: Bool) -> ScopeTemplate {
        ScopeTemplate(
            id: "developer-maintenance",
            name: "Developer Maintenance",
            group: "Developer",
            summary: "The broader developer and AI-agent maintenance set: Codex, containers, Xcode, package caches, IDE caches, mobile tooling, and build temp data.",
            recommendedUse: "Weekly or after large build/test/autonomous-agent sessions.",
            scopes: DefaultScopes.developerAgentBloat(home: home, includeUnavailable: includeUnavailable)
        )
    }

    private static func scopes(
        _ paths: [(String, URL)],
        includeUnavailable: Bool,
        removingNestedChildren: Bool = false
    ) -> [ScanScope] {
        DefaultScopes.customPlan(
            scopes: paths.compactMap { name, url in
                let root = url.standardizedFileURL
                guard includeUnavailable || FileManager.default.fileExists(atPath: root.path) else { return nil }
                return ScanScope(name: name, root: root)
            }
        ).scopes.removingNestedChildrenIfNeeded(removingNestedChildren)
    }
}

private extension Array where Element == ScanScope {
    func removingNestedChildrenIfNeeded(_ enabled: Bool) -> [ScanScope] {
        guard enabled else { return self }
        var output: [ScanScope] = []
        for scope in self.sorted(by: { $0.root.path.count < $1.root.path.count }) {
            let path = scope.root.standardizedFileURL.path
            guard !output.contains(where: { path.hasPrefix($0.root.standardizedFileURL.path + "/") }) else { continue }
            output.append(scope)
        }
        return output
    }
}
