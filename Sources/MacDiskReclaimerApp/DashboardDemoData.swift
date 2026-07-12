import Foundation
import ReclaimerCore

@MainActor
enum DashboardDemoData {
    static var isEnabled: Bool {
        DashboardLaunchOptions.isScreenshotDemo
    }

    static func apply(to model: DashboardModel) {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let home = URL(fileURLWithPath: "/Users/ryddi-demo")
        let scopes = [
            ScanScope(name: "Developer caches", root: home.appendingPathComponent("Library/Caches"), permissionState: .readable),
            ScanScope(name: "AI agent storage", root: home.appendingPathComponent(".codex"), permissionState: .readable),
            ScanScope(name: "Project workspace", root: home.appendingPathComponent("Projects"), permissionState: .readable),
            ScanScope(name: "Package stores", root: home.appendingPathComponent(".npm"), permissionState: .readable),
            ScanScope(name: "Containers", root: home.appendingPathComponent(".colima"), permissionState: .readable),
            ScanScope(name: "Downloads review", root: home.appendingPathComponent("Downloads"), permissionState: .readable)
        ]
        let findings = demoFindings(home: home, now: now)
        let overview = FindingAnalytics.overview(findings: findings, scopes: scopes, topLimit: 12)
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: findings, mode: .autoSafeOnly)
        let agentReview = AgentStorageReviewBuilder.build(findings: findings, scopes: scopes, limit: 20, generatedAt: now)
        let retentionReport = AgentRetentionBuilder.build(
            review: agentReview,
            profile: .balanced,
            limit: 20,
            referenceDate: now,
            generatedAt: now
        )
        let packageReport = packageCacheReview(home: home, now: now)
        let appReviewReport = appReview(home: home, now: now)
        let remote = remoteReports(now: now)

        model.scanPreset = .developer
        model.selectedScopeTemplateID = nil
        model.selectedSavedScopeSetID = nil
        model.findings = findings
        model.refreshReviewQueueReport()
        model.scanScopes = scopes
        model.overview = overview
        model.diskDrillDown = DiskDrillDownBuilder.build(findings: findings, scopes: scopes, maxDepth: 3, childLimit: 8)
        model.plan = plan
        model.lastDryRunReceipt = nil
        model.lastExecutionReceipt = nil
        model.lastScannedScopeLabel = "Screenshot demo"
        model.lastScanDate = now
        model.diskStatus = DiskStatusSnapshot(
            createdAt: now,
            path: "/System/Volumes/Data",
            volumeName: "Data",
            totalBytes: gb(500),
            freeBytes: gb(104),
            importantFreeBytes: gb(104),
            availableBytes: gb(104),
            pressure: .healthy,
            notes: ["Synthetic screenshot fixture; no real disk scan was performed."]
        )
        model.permissionReport = PermissionAdvisor.report(scopeSummaries: permissionSummaries(for: scopes), now: now)
        model.agentStorageReview = agentReview
        model.agentRetentionReport = retentionReport
        model.packageCacheReview = packageReport
        model.appReview = appReviewReport
        model.appUninstallPreview = nil
        model.recentPackageCacheReviewReports = [packageReport]
        model.remoteTargets = [remote.target]
        model.remoteTargetInput = remote.target.input
        model.remoteProbeReport = remote.probe
        model.remoteScanReport = remote.scan
        model.remoteDogfoodReport = remote.dogfood
        model.recentRemoteProbeReports = [remote.probe]
        model.recentRemoteScanReports = [remote.scan]
        model.recentRemoteDogfoodReports = [remote.dogfood]
        model.remoteGrowthReport = nil
        model.error = nil
    }

    private static func demoFindings(home: URL, now: Date) -> [Finding] {
        [
            finding(
                id: "demo-homebrew-cache",
                scope: "Developer caches",
                path: home.appendingPathComponent("Library/Caches/Homebrew/downloads").path,
                name: "Homebrew downloads",
                bytes: gb(1) + mb(680),
                safety: .autoSafe,
                action: .deleteCache,
                category: "Developer cache",
                owner: "Homebrew",
                next: "Rebuildable package downloads; native dry-run remains preferred for Homebrew cleanup.",
                modified: now.addingTimeInterval(-45 * 86_400),
                gates: [.openFileClear, .notSymbolicLink, .finalClassificationRequired]
            ),
            finding(
                id: "demo-codex-cache",
                scope: "AI agent storage",
                path: home.appendingPathComponent(".codex/cache/object-store").path,
                name: "Codex object cache",
                bytes: gb(2) + mb(120),
                safety: .autoSafe,
                action: .deleteCache,
                category: "Codex",
                owner: "Codex",
                next: "Rebuildable cache; selected only after open-file and final classification checks.",
                modified: now.addingTimeInterval(-35 * 86_400),
                gates: [.openFileClear, .notSymbolicLink, .finalClassificationRequired]
            ),
            finding(
                id: "demo-npm-cacache",
                scope: "Package stores",
                path: home.appendingPathComponent(".npm/_cacache").path,
                name: "_cacache",
                bytes: gb(3) + mb(210),
                safety: .safeAfterCondition,
                action: .nativeToolCommand,
                category: "Developer cache",
                owner: "npm",
                next: "Use npm cache verification before cleanup.",
                modified: now.addingTimeInterval(-31 * 86_400),
                conditions: ["Prefer native package-manager preview before cleanup."],
                gates: [.nativeToolRequired],
                nativeTool: "npm"
            ),
            finding(
                id: "demo-browser-cache-active",
                scope: "Developer caches",
                path: home.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache").path,
                name: "Chrome cache",
                bytes: mb(980),
                safety: .safeAfterCondition,
                action: .deleteCache,
                category: "Browser cache",
                owner: "Chrome",
                next: "Quit Chrome and rescan active handles before cleanup.",
                modified: now.addingTimeInterval(-8 * 86_400),
                conditions: ["Quit the owning app before cleanup."],
                open: true
            ),
            finding(
                id: "demo-codex-sessions",
                scope: "AI agent storage",
                path: home.appendingPathComponent(".codex/sessions/2026/07").path,
                name: "Codex sessions",
                bytes: gb(6) + mb(850),
                safety: .preserveByDefault,
                action: .compress,
                category: "Codex",
                owner: "Codex",
                next: "Sessions can contain useful project history; review or archive deliberately.",
                modified: now.addingTimeInterval(-70 * 86_400)
            ),
            finding(
                id: "demo-codex-auth",
                scope: "AI agent storage",
                path: home.appendingPathComponent(".codex/auth.json").path,
                name: "Codex auth.json",
                bytes: 6_144,
                safety: .neverTouch,
                action: .reportOnly,
                category: "Codex",
                owner: "Codex",
                next: "Credential and auth material is blocked from cleanup.",
                modified: now.addingTimeInterval(-2 * 86_400)
            ),
            finding(
                id: "demo-download-archive",
                scope: "Downloads review",
                path: home.appendingPathComponent("Downloads/video-export-archive.zip").path,
                name: "video-export-archive.zip",
                bytes: gb(4) + mb(640),
                safety: .reviewRequired,
                action: .compress,
                category: "Large files",
                owner: "Downloads",
                next: "Large personal archive; open in Finder before moving or deleting.",
                modified: now.addingTimeInterval(-120 * 86_400)
            ),
            finding(
                id: "demo-colima-disk",
                scope: "Containers",
                path: home.appendingPathComponent(".colima/default/disk.img").path,
                name: "Colima VM disk",
                bytes: gb(8) + mb(150),
                safety: .reviewRequired,
                action: .nativeToolCommand,
                category: "Containers",
                owner: "Colima",
                next: "Use Colima/Docker inventory and native cleanup guidance; never raw-delete VM disks.",
                modified: now.addingTimeInterval(-14 * 86_400),
                conditions: ["Use native VM/container tool before cleanup."],
                gates: [.nativeToolRequired],
                nativeTool: "colima"
            ),
            finding(
                id: "demo-project-build",
                scope: "Project workspace",
                path: home.appendingPathComponent("Projects/ExampleApp/.build").path,
                name: ".build",
                bytes: gb(1) + mb(420),
                safety: .autoSafe,
                action: .deleteCache,
                category: "Project dependencies",
                owner: "SwiftPM",
                next: "Rebuildable project output; eligible after open-file and final classification checks.",
                modified: now.addingTimeInterval(-22 * 86_400),
                gates: [.openFileClear, .notSymbolicLink, .finalClassificationRequired]
            ),
            finding(
                id: "demo-unknown-support",
                scope: "Developer caches",
                path: home.appendingPathComponent("Library/Application Support/ExampleTool/state").path,
                name: "ExampleTool state",
                bytes: gb(2) + mb(260),
                safety: .reviewRequired,
                action: .openGuidance,
                category: "Unknown",
                owner: "ExampleTool",
                next: "Unknown app state stays review-only until a rule explains it.",
                modified: now.addingTimeInterval(-19 * 86_400)
            )
        ]
    }

    private static func packageCacheReview(home: URL, now: Date) -> PackageCacheReviewReport {
        let homebrewRoot = home.appendingPathComponent("Library/Caches/Homebrew")
        let npmRoot = home.appendingPathComponent(".npm/_cacache")
        let gradleRoot = home.appendingPathComponent(".gradle/caches")
        let items = [
            packageItem(path: homebrewRoot.appendingPathComponent("downloads").path, name: "Homebrew downloads", manager: .homebrew, kind: .downloadCache, bytes: gb(1) + mb(680), count: 840, now: now),
            packageItem(path: npmRoot.path, name: "_cacache", manager: .npm, kind: .packageStore, bytes: gb(3) + mb(210), count: 4_300, now: now),
            packageItem(path: gradleRoot.appendingPathComponent("modules-2").path, name: "modules-2", manager: .gradle, kind: .buildCache, bytes: gb(1) + mb(140), count: 1_120, now: now)
        ]
        let total = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return PackageCacheReviewReport(
            createdAt: now,
            totalLogicalSize: total,
            totalAllocatedSize: total,
            itemCount: items.reduce(0) { $0 + $1.itemCount },
            displayedItemCount: items.count,
            candidateBytes: total,
            rootSummaries: [
                packageRoot(manager: .homebrew, path: homebrewRoot.path, bytes: gb(1) + mb(680), count: 840),
                packageRoot(manager: .npm, path: npmRoot.path, bytes: gb(3) + mb(210), count: 4_300),
                packageRoot(manager: .gradle, path: gradleRoot.path, bytes: gb(1) + mb(140), count: 1_120)
            ],
            managerSummaries: [
                PackageCacheSummary(name: "npm", itemCount: 4_300, allocatedSize: gb(3) + mb(210)),
                PackageCacheSummary(name: "Homebrew", itemCount: 840, allocatedSize: gb(1) + mb(680)),
                PackageCacheSummary(name: "Gradle", itemCount: 1_120, allocatedSize: gb(1) + mb(140))
            ],
            kindSummaries: [
                PackageCacheSummary(name: "Package store", itemCount: 4_300, allocatedSize: gb(3) + mb(210)),
                PackageCacheSummary(name: "Download cache", itemCount: 840, allocatedSize: gb(1) + mb(680)),
                PackageCacheSummary(name: "Build cache", itemCount: 1_120, allocatedSize: gb(1) + mb(140))
            ],
            largestItems: items,
            protectedConfigRoots: [
                PackageCacheProtectedConfigRoot(manager: .npm, path: home.appendingPathComponent(".npmrc").path, permissionState: .readable, note: "Config and token-bearing files are never package cache candidates."),
                PackageCacheProtectedConfigRoot(manager: .homebrew, path: home.appendingPathComponent(".homebrew").path, permissionState: .missing, note: "Tool config is reported separately from rebuildable cache data.")
            ],
            guidance: [
                "Use preview commands first. Ryddi does not run package cleanup from this report.",
                "Package managers can redownload cache data, but config, auth, registry, and project behavior files stay protected."
            ],
            nonClaims: [
                "No package cache cleanup was executed.",
                "Native tools may report different reclaim after their own accounting.",
                "Protected package-manager config and auth paths remain out of scope."
            ]
        )
    }

    private static func appReview(home: URL, now: Date) -> AppReviewReport {
        let vivaldi = InstalledApp(
            id: "demo-vivaldi",
            displayName: "Vivaldi",
            bundleIdentifier: "com.vivaldi.Vivaldi",
            version: "7.3",
            executableName: "Vivaldi",
            path: "/Applications/Vivaldi.app",
            modificationDate: now.addingTimeInterval(-18 * 86_400)
        )
        let arc = InstalledApp(
            id: "demo-arc",
            displayName: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            version: "1.95",
            executableName: "Arc",
            path: "/Applications/Arc.app",
            modificationDate: now.addingTimeInterval(-29 * 86_400)
        )
        let codex = InstalledApp(
            id: "demo-codex",
            displayName: "Codex",
            bundleIdentifier: "com.openai.codex",
            version: "0.9",
            executableName: "Codex",
            path: "/Applications/Codex.app",
            modificationDate: now.addingTimeInterval(-4 * 86_400)
        )

        let installedGroups = [
            AppReviewGroup(
                id: "demo-vivaldi-group",
                ownerName: "Vivaldi",
                bundleIdentifier: vivaldi.bundleIdentifier,
                appPath: vivaldi.path,
                isInstalled: true,
                items: [
                    appReviewItem(owner: "vivaldi", path: home.appendingPathComponent("Library/Application Support/Vivaldi").path, name: "Vivaldi state", bytes: gb(4) + mb(300), category: "App state", safety: .preserveByDefault, action: .reportOnly, now: now),
                    appReviewItem(owner: "vivaldi", path: home.appendingPathComponent("Library/Caches/Vivaldi").path, name: "Vivaldi cache", bytes: gb(2) + mb(130), category: "App cache", safety: .safeAfterCondition, action: .deleteCache, now: now)
                ],
                notes: ["Installed-app support data may include preferences, profiles, extensions, and state."]
            ),
            AppReviewGroup(
                id: "demo-arc-group",
                ownerName: "Arc",
                bundleIdentifier: arc.bundleIdentifier,
                appPath: arc.path,
                isInstalled: true,
                items: [
                    appReviewItem(owner: "arc", path: home.appendingPathComponent("Library/Caches/Arc").path, name: "Arc cache", bytes: gb(2) + mb(710), category: "App cache", safety: .safeAfterCondition, action: .deleteCache, now: now),
                    appReviewItem(owner: "arc", path: home.appendingPathComponent("Library/Application Support/Arc").path, name: "Arc state", bytes: gb(2) + mb(430), category: "App state", safety: .preserveByDefault, action: .reportOnly, now: now)
                ],
                notes: ["Browser state is preserve-first unless profiles and sync behavior are reviewed."]
            ),
            AppReviewGroup(
                id: "demo-codex-group",
                ownerName: "Codex",
                bundleIdentifier: codex.bundleIdentifier,
                appPath: codex.path,
                isInstalled: true,
                items: [
                    appReviewItem(owner: "codex", path: home.appendingPathComponent("Library/Logs/com.openai.codex").path, name: "Codex logs", bytes: gb(3) + mb(40), category: "App logs", safety: .reviewRequired, action: .reportOnly, now: now),
                    appReviewItem(owner: "codex", path: home.appendingPathComponent("Library/Caches/Codex").path, name: "Codex cache", bytes: mb(887), category: "App cache", safety: .safeAfterCondition, action: .deleteCache, now: now),
                    appReviewItem(owner: "codex", path: home.appendingPathComponent("Library/Application Support/Codex").path, name: "Codex state", bytes: mb(508), category: "App state", safety: .preserveByDefault, action: .reportOnly, now: now)
                ],
                notes: ["AI-agent app state can contain session context and remains preserve-first."]
            )
        ]

        let orphanGroups = [
            AppReviewGroup(
                id: "demo-old-helper-group",
                ownerName: "Old Helper",
                bundleIdentifier: nil,
                appPath: nil,
                isInstalled: false,
                items: [
                    appReviewItem(owner: "old-helper", path: home.appendingPathComponent("Library/Application Support/Old Helper").path, name: "Old Helper support", bytes: gb(1) + mb(240), category: "App state", safety: .reviewRequired, action: .reportOnly, now: now),
                    appReviewItem(owner: "old-helper", path: home.appendingPathComponent("Library/Caches/Old Helper").path, name: "Old Helper cache", bytes: mb(620), category: "App cache", safety: .safeAfterCondition, action: .deleteCache, now: now)
                ],
                notes: ["Orphan candidates are heuristic app-owned-looking files with no discovered app match."]
            )
        ]

        return AppReviewReport(
            createdAt: now,
            appRoots: ["/Applications", home.appendingPathComponent("Applications").path],
            installedApps: [vivaldi, arc, codex],
            installedAppGroups: installedGroups,
            orphanGroups: orphanGroups,
            skipped: [home.appendingPathComponent("Library/Containers/com.example.protected").path],
            notes: [
                "Apps & Leftovers is review-only. Ryddi does not uninstall apps or delete related files from this report.",
                "Installed-app support data can include preferences, licenses, projects, plugins, and state; review before removal.",
                "Orphan candidates are heuristic app-owned-looking files with no currently discovered app match, not proof that the app is gone."
            ]
        )
    }

    private static func appReviewItem(
        owner: String,
        path: String,
        name: String,
        bytes: Int64,
        category: String,
        safety: SafetyClass,
        action: ActionKind,
        now: Date
    ) -> AppReviewItem {
        AppReviewItem(
            ownerKey: owner,
            path: path,
            displayName: name,
            logicalSize: bytes,
            allocatedSize: bytes,
            isDirectory: true,
            modificationDate: now.addingTimeInterval(-14 * 86_400),
            category: category,
            safetyClass: safety,
            actionKind: action,
            evidence: [Evidence(kind: "demo", message: "Synthetic screenshot app review path.")]
        )
    }

    private static func remoteReports(now: Date) -> (target: RemoteTargetReference, probe: RemoteProbeReport, scan: RemoteScanReport, dogfood: RemoteDogfoodReport) {
        let target = RemoteTargetReference(
            id: "demo-vps",
            input: "demo-vps",
            alias: "demo-vps",
            resolvedUser: "deploy",
            resolvedHost: "203.0.113.42",
            resolvedPort: 22,
            knownHostsState: "known",
            fingerprint: "SHA256:demo-redacted"
        )
        let probe = RemoteProbeReport(
            id: "demo-remote-probe",
            createdAt: now,
            target: target,
            osSummary: "Ubuntu 24.04 LTS",
            homeDirectory: "/home/deploy",
            sudoNonInteractive: false,
            availableTools: ["docker", "journalctl", "apt-get"],
            commands: [
                command(id: "probe.uname", display: "ssh demo-vps uname -srm", stdout: ["Linux 6.8.0 x86_64"]),
                command(id: "probe.sudo", display: "ssh demo-vps sudo -n true", exit: 1, stderr: ["sudo requires authentication; no prompt was attempted"])
            ],
            nonClaims: RemoteProbeReport.defaultNonClaims
        )
        let scan = RemoteScanReport(
            id: "demo-remote-scan",
            createdAt: now,
            preset: .vpsGeneral,
            target: target,
            diskFilesystems: [
                RemoteFilesystemSummary(mount: "/", filesystem: "/dev/vda1", usedBytes: gb(72), availableBytes: gb(18), capacityPercent: 80),
                RemoteFilesystemSummary(mount: "/var/lib/docker", filesystem: "/dev/vdb1", usedBytes: gb(88), availableBytes: gb(5), capacityPercent: 95)
            ],
            inodeFilesystems: [
                RemoteFilesystemSummary(mount: "/", filesystem: "/dev/vda1", usedBytes: nil, availableBytes: nil, capacityPercent: 64)
            ],
            findings: [
                remoteFinding(path: "/var/lib/docker/overlay2", display: "<path redacted>", bucket: "Docker data", bytes: gb(28), safety: .safeAfterCondition, action: .nativeToolCommand, next: .useNativeTool, evidence: "Docker-owned storage should be reviewed with Docker commands, not raw deletion."),
                remoteFinding(path: "/var/log/journal", display: "<path redacted>", bucket: "journald logs", bytes: gb(5) + mb(400), safety: .safeAfterCondition, action: .openGuidance, next: .useNativeTool, evidence: "Use journalctl vacuum guidance after reviewing retention needs."),
                remoteFinding(path: "/var/lib/docker/volumes/postgres_data", display: "<path redacted>", bucket: "Docker volumes", bytes: gb(14), safety: .preserveByDefault, action: .nativeToolCommand, next: .protectByDefault, evidence: "Docker volumes may contain databases or app state."),
                remoteFinding(path: "/srv/app/releases/2026-04-12", display: "<path redacted>", bucket: "Old deploy releases", bytes: gb(3) + mb(700), safety: .reviewRequired, action: .openGuidance, next: .archiveCandidate, evidence: "Release directories may be useful for rollback.")
            ],
            nativeGuidance: [
                RemoteNativeGuidance(id: "docker-review", title: "Docker review", command: "docker system df -v", risk: "review", summary: "Inspect images, build cache, containers, and volumes before pruning."),
                RemoteNativeGuidance(id: "journal-vacuum", title: "journald vacuum review", command: "journalctl --disk-usage", risk: "review", summary: "Check current journal usage before choosing any vacuum command."),
                RemoteNativeGuidance(id: "apt-preview", title: "APT dry run", command: "apt-get --dry-run autoremove", risk: "review", summary: "Review packages that would be removed; Ryddi does not run this remotely.")
            ],
            commands: [
                command(id: "scan.df", display: "ssh demo-vps df -Pk", stdout: ["Filesystem 1024-blocks Used Available Capacity Mounted on"]),
                command(id: "scan.du", display: "ssh demo-vps du -k -d 1 /var /home /opt /srv", stdout: ["29360128 /var/lib/docker"]),
                command(id: "scan.docker-df", display: "ssh demo-vps docker system df -v", exit: 1, stderr: ["permission denied while connecting to Docker socket"])
            ],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
        let dogfood = RemoteDogfoodReportBuilder.build(
            probe: probe,
            scan: scan,
            growth: nil,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, redactUserText: true),
            now: now
        )
        return (target, probe, scan, dogfood)
    }

    private static func finding(
        id: String,
        scope: String,
        path: String,
        name: String,
        bytes: Int64,
        safety: SafetyClass,
        action: ActionKind,
        category: String,
        owner: String,
        next: String,
        modified: Date,
        conditions: [String] = [],
        gates: [PlanConditionKind] = [],
        nativeTool: String? = nil,
        open: Bool = false
    ) -> Finding {
        let gateEvidence = RuleGateEvidence(nativeToolName: nativeTool, nativePreviewAvailable: nativeTool != nil)
        let match = RuleMatch(
            ruleID: "demo.\(id)",
            title: name,
            category: category,
            safetyClass: safety,
            actionKind: action,
            evidence: [next],
            conditions: conditions,
            conditionGates: gates,
            gateEvidence: gateEvidence,
            recovery: "Synthetic demo data only; no real path is touched."
        )
        let openStatus = OpenFileStatus(
            isOpen: open,
            processSummary: open ? ["DemoApp pid 123"] : [],
            checkedAt: modified,
            checkedRecursively: true,
            checkedPath: path
        )
        return Finding(
            id: id,
            scopeName: scope,
            path: path,
            displayName: name,
            logicalSize: bytes,
            allocatedSize: bytes,
            isDirectory: !name.contains("."),
            modificationDate: modified,
            ownerHint: owner,
            safetyClass: safety,
            actionKind: action,
            ruleMatches: [match],
            evidence: [
                Evidence(kind: "demo", message: next),
                Evidence(kind: "privacy", message: "Synthetic screenshot path under /Users/ryddi-demo.")
            ],
            openFileStatus: openStatus
        )
    }

    private static func packageRoot(manager: PackageCacheManager, path: String, bytes: Int64, count: Int) -> PackageCacheRootSummary {
        PackageCacheRootSummary(
            manager: manager,
            rootPath: path,
            permissionState: .readable,
            logicalSize: bytes,
            allocatedSize: bytes,
            itemCount: count,
            nativeCleanupHint: manager.nativeCleanupHint,
            note: "Synthetic readable cache root for screenshot proof."
        )
    }

    private static func permissionSummaries(for scopes: [ScanScope]) -> [ScopeAccessSummary] {
        scopes.map {
            ScopeAccessSummary(
                name: $0.name,
                path: $0.root.path,
                permissionState: .readable,
                message: "Synthetic screenshot scope is readable."
            )
        }
    }

    private static func packageItem(
        path: String,
        name: String,
        manager: PackageCacheManager,
        kind: PackageCacheKind,
        bytes: Int64,
        count: Int,
        now: Date
    ) -> PackageCacheItem {
        PackageCacheItem(
            path: path,
            displayName: name,
            manager: manager,
            kind: kind,
            logicalSize: bytes,
            allocatedSize: bytes,
            itemCount: count,
            isDirectory: true,
            modificationDate: now.addingTimeInterval(-30 * 86_400),
            signals: ["Synthetic screenshot cache root", manager.nativeCleanupHint],
            recommendation: "\(manager.label) cache should be reviewed with native preview commands before cleanup.",
            guidance: [manager.nativeCleanupHint]
        )
    }

    private static func remoteFinding(
        path: String,
        display: String,
        bucket: String,
        bytes: Int64,
        safety: SafetyClass,
        action: ActionKind,
        next: ReviewNextAction,
        evidence: String
    ) -> RemoteStorageFinding {
        RemoteStorageFinding(
            remotePath: path,
            displayPath: display,
            bucket: bucket,
            allocatedBytes: bytes,
            safetyClass: safety,
            actionKind: action,
            evidence: [Evidence(kind: "demo", message: evidence)],
            recommendedNextAction: next
        )
    }

    private static func command(
        id: String,
        display: String,
        exit: Int32 = 0,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> RemoteCommandResult {
        RemoteCommandResult(
            commandID: id,
            displayCommand: display,
            exitCode: exit,
            timedOut: false,
            stdoutPreview: stdout,
            stderrPreview: stderr,
            redactionApplied: true
        )
    }

    private static func gb(_ value: Int64) -> Int64 {
        value * 1_024 * 1_024 * 1_024
    }

    private static func mb(_ value: Int64) -> Int64 {
        value * 1_024 * 1_024
    }
}

@MainActor
extension DashboardModel {
    func applyScreenshotDemoIfNeeded() {
        guard DashboardDemoData.isEnabled else { return }
        DashboardDemoData.apply(to: self)
    }
}
