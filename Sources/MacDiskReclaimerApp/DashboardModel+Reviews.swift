import Foundation
import ReclaimerCore
import RyddiProtectCore

extension DashboardModel {
    func discoverCloudStorageRoots(userSelectedMegaRoots: [URL] = []) async {
        let activityID = activities.begin(.review, message: "Discovering cloud folders")
        defer { activities.finish(.review, id: activityID) }
        cloudStorageRootDiscovery = await Task.detached {
            CloudStorageRootDiscovery().discover(userSelectedMegaRoots: userSelectedMegaRoots)
        }.value
        error = nil
    }

    func checkActiveHandles() async {
        let activityID = activities.begin(.review, message: "Checking active files")
        defer { activities.finish(.review, id: activityID) }
        do {
            let baseFindings = findings
            let scopePlan = selectedScopePlan
            let includeUserRules = includeUserRulesInScans
            let report = try await Task.detached {
                let sourceFindings: [Finding]
                if baseFindings.isEmpty {
                    let scopes = scopePlan.scopes
                    let policy = UserPathPolicyStore().load()
                    let scanner = try FileScanner(
                        ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                        openFileChecker: NoOpenFilesChecker()
                    )
                    sourceFindings = scanner.scan(
                        scopes: scopes,
                        options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                    )
                } else {
                    sourceFindings = baseFindings
                }
                return ActiveFileReviewScanner(openFileChecker: LsofOpenFileChecker()).review(
                    findings: sourceFindings,
                    options: ActiveFileReviewOptions(limit: 80)
                )
            }.value
            activeFileReview = report
            applyActiveFileStatuses(from: report)
            _ = try AuditStore().save(activeFileReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scanDuplicates(includePreserveByDefault: Bool = false) async {
        let activityID = activities.begin(.review, message: "Reviewing duplicates")
        defer { activities.finish(.review, id: activityID) }
        do {
            let currentScopes = scanScopes.isEmpty
                ? self.currentScopes(includeUnavailable: false)
                : scanScopes
            duplicateReview = try await Task.detached {
                try DuplicateReviewScanner().scan(
                    scopes: currentScopes,
                    options: DuplicateReviewOptions(
                        minimumFileSize: 5_000_000,
                        maximumDepth: 5,
                        maximumFilesToHash: 2_000,
                        includePreserveByDefault: includePreserveByDefault
                    )
                )
            }.value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewTrash() async {
        let activityID = activities.begin(.review, message: "Reviewing Trash")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                TrashReviewScanner().review(
                    options: TrashReviewOptions(limit: 50, measurementDepth: 8)
                )
            }.value
            trashReview = report
            _ = try AuditStore().save(trashReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewDownloads() async {
        let activityID = activities.begin(.review, message: "Reviewing Downloads")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                DownloadsReviewScanner().review(
                    options: DownloadsReviewOptions(limit: 80, oldDays: 90, measurementDepth: 6)
                )
            }.value
            downloadsReview = report
            _ = try AuditStore().save(downloadsReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewBrowserCaches() async {
        let activityID = activities.begin(.review, message: "Reviewing browser caches")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                BrowserCacheReviewScanner().review(
                    options: BrowserCacheReviewOptions(limit: 80, measurementDepth: 7, includeMissingRoots: true)
                )
            }.value
            browserCacheReview = report
            _ = try AuditStore().save(browserCacheReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewPackageCaches() async {
        let activityID = activities.begin(.review, message: "Reviewing package caches")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                PackageCacheReviewScanner().review(
                    options: PackageCacheReviewOptions(limit: 80, measurementDepth: 7, includeMissingRoots: true)
                )
            }.value
            packageCacheReview = report
            _ = try AuditStore().save(packageCacheReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewProjectDependencies() async {
        let activityID = activities.begin(.review, message: "Reviewing project dependencies")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                ProjectDependencyReviewScanner().review(
                    options: ProjectDependencyReviewOptions(
                        limit: 80,
                        oldDays: 90,
                        maximumSearchDepth: 6,
                        measurementDepth: 8,
                        includeMissingRoots: true,
                        includeVCSStatus: true,
                        projectPolicy: ProjectDependencyPolicyStore().load()
                    )
                )
            }.value
            projectDependencyReview = report
            _ = try AuditStore().save(projectDependencyReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewDeviceBackups() async {
        let activityID = activities.begin(.review, message: "Reviewing device backups")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                DeviceBackupReviewScanner().review(
                    options: DeviceBackupReviewOptions(limit: 80, oldDays: 180, measurementDepth: 12)
                )
            }.value
            deviceBackupReview = report
            _ = try AuditStore().save(deviceBackupReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewXcode() async {
        let activityID = activities.begin(.review, message: "Reviewing Xcode storage")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                XcodeReviewScanner().review(
                    options: XcodeReviewOptions(limit: 80, oldDays: 180, measurementDepth: 10, includeMissingRoots: true)
                )
            }.value
            xcodeReview = report
            _ = try AuditStore().save(xcodeReviewReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewApps(includeSystemApps: Bool = false, includeOrphans: Bool = true) async {
        let activityID = activities.begin(.review, message: "Reviewing applications")
        defer { activities.finish(.review, id: activityID) }
        do {
            appReview = try await Task.detached {
                try AppReviewScanner().scan(
                    options: AppReviewOptions(
                        includeSystemApplications: includeSystemApps,
                        includeOrphanCandidates: includeOrphans,
                        minimumRelatedSize: 10_000_000,
                        measurementDepth: 3
                    )
                )
            }.value
            appUninstallPreview = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func previewAppUninstall(group: AppReviewGroup) async {
        guard let report = appReview else {
            error = "Run an app review before building an uninstall preview."
            return
        }
        let activityID = activities.begin(.review, message: "Building uninstall preview")
        defer { activities.finish(.review, id: activityID) }
        do {
            let selector = AppUninstallSelector(
                appPath: group.appPath,
                bundleIdentifier: group.bundleIdentifier,
                displayName: group.ownerName
            )
            let preview = try await Task.detached {
                try AppUninstallPreviewBuilder.build(report: report, selector: selector)
            }.value
            appUninstallPreview = preview
            lastAppUninstallDryRunReceipt = nil
            lastAppUninstallReceipt = nil
            _ = try AuditStore().save(appUninstallPreview: preview)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dryRunAppUninstall() async {
        guard let preview = appUninstallPreview else {
            error = "Build an uninstall preview before running an app uninstall dry run."
            return
        }
        let activityID = activities.begin(.cleanup, message: "Running uninstall dry run")
        defer { activities.finish(.cleanup, id: activityID) }
        do {
            let receipt = await Task.detached {
                let policy = UserPathPolicyStore().load()
                let allowedRoots = AppReviewOptions().appRoots
                return AppUninstallExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: AppUninstallExecutorConfiguration(userPathPolicy: policy, allowedAppRoots: allowedRoots)
                )
                    .execute(preview: preview, mode: .dryRun, userConfirmed: false)
            }.value
            lastAppUninstallDryRunReceipt = receipt
            lastAppUninstallReceipt = nil
            _ = try AuditStore().save(appUninstallReceipt: receipt)
            await loadAudit()
            error = receipt.status == "dry-run" ? nil : receipt.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewAgentStorage() async {
        let activityID = activities.begin(.review, message: "Reviewing agent storage")
        defer { activities.finish(.review, id: activityID) }
        do {
            let includeUserRules = includeUserRulesInScans
            agentStorageReview = try await Task.detached {
                let scopes = DefaultScopes.aiAgentStorage(includeUnavailable: false)
                let policy = UserPathPolicyStore().load()
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let findings = scanner.scan(
                    scopes: scopes,
                    options: ScanOptions(
                        minimumFindingSize: 1,
                        maximumFindingDepth: 3,
                        measurementDepth: 7,
                        includeOpenFileStatus: false,
                        userPathPolicy: policy
                    )
                )
                return AgentStorageReviewBuilder.build(findings: findings, scopes: scopes, limit: 80)
            }.value
            agentRetentionReport = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewAgentRetention(profile: AgentRetentionProfile) async {
        let activityID = activities.begin(.review, message: "Reviewing agent retention")
        defer { activities.finish(.review, id: activityID) }
        do {
            let includeUserRules = includeUserRulesInScans
            let existingReview = agentStorageReview
            let result = try await Task.detached { () -> (AgentStorageReview, AgentRetentionReport) in
                let review: AgentStorageReview
                if let existingReview {
                    review = existingReview
                } else {
                    let scopes = DefaultScopes.aiAgentStorage(includeUnavailable: false)
                    let policy = UserPathPolicyStore().load()
                    let scanner = try FileScanner(
                        ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                        openFileChecker: NoOpenFilesChecker()
                    )
                    let findings = scanner.scan(
                        scopes: scopes,
                        options: ScanOptions(
                            minimumFindingSize: 1,
                            maximumFindingDepth: 3,
                            measurementDepth: 7,
                            includeOpenFileStatus: false,
                            userPathPolicy: policy
                        )
                    )
                    review = AgentStorageReviewBuilder.build(findings: findings, scopes: scopes, limit: 80)
                }
                let retentionReport = AgentRetentionBuilder.build(review: review, profile: profile, limit: 80)
                return (review, retentionReport)
            }.value
            agentStorageReview = result.0
            agentRetentionReport = result.1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func runNativeToolCommand(receipt: NativeToolReceipt, command: NativeToolCommand, perform: Bool) async {
        let activityKind: DashboardActivityKind = perform ? .cleanup : .review
        let activityID = activities.begin(
            activityKind,
            message: perform ? "Running native cleanup" : "Previewing native cleanup"
        )
        defer { activities.finish(activityKind, id: activityID) }
        do {
            let includeUserRules = includeUserRulesInScans
            if perform, let reason = nativePerformBlockReason(receipt: receipt, command: command) {
                error = reason
                return
            }
            let executionReceipts = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
                let selection = NativeToolCommandSelection(receipt: receipt, command: command)
                if perform, command.id == "brew.cleanup" {
                    let executor = NativeActionExecutor()
                    let preview = executor.previewHomebrewCleanup(
                        ruleVersion: ruleVersion,
                        findingPath: receipt.findingPath
                    )
                    let previewReceipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                        from: preview.receipt,
                        ruleVersion: ruleVersion,
                        findingPath: receipt.findingPath,
                        category: receipt.category,
                        userConfirmed: false
                    )
                    let actionReceipt = executor.performHomebrewCleanup(
                        using: preview,
                        userConfirmed: true,
                        ruleVersion: ruleVersion,
                        findingPath: receipt.findingPath
                    )
                    let performedReceipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                        from: actionReceipt,
                        ruleVersion: ruleVersion,
                        findingPath: receipt.findingPath,
                        category: receipt.category,
                        userConfirmed: true
                    )
                    return [previewReceipt, performedReceipt]
                }
                if let maintenanceAction = NativeMaintenanceAction(rawValue: command.id) {
                    let executor = NativeMaintenanceExecutor()
                    let preview = executor.preview(
                        action: maintenanceAction,
                        findingPath: receipt.findingPath,
                        ruleVersion: ruleVersion
                    )
                    let previewReceipt = NativeMaintenanceReceiptBridge.nativeToolExecutionReceipt(
                        from: preview.receipt,
                        action: maintenanceAction,
                        ruleVersion: ruleVersion,
                        findingPath: receipt.findingPath,
                        category: receipt.category,
                        userConfirmed: false
                    )
                    if perform {
                        let actionReceipt = executor.perform(
                            using: preview,
                            userConfirmed: true,
                            findingPath: receipt.findingPath,
                            ruleVersion: ruleVersion
                        )
                        let performedReceipt = NativeMaintenanceReceiptBridge.nativeToolExecutionReceipt(
                            from: actionReceipt,
                            action: maintenanceAction,
                            ruleVersion: ruleVersion,
                            findingPath: receipt.findingPath,
                            category: receipt.category,
                            userConfirmed: true
                        )
                        return [previewReceipt, performedReceipt]
                    }
                    return [previewReceipt]
                }
                return [NativeToolExecutor().execute(
                    selection: selection,
                    mode: perform ? .perform : .dryRun,
                    ruleVersion: ruleVersion,
                    userConfirmed: perform
                )]
            }.value
            let auditStore = AuditStore()
            for executionReceipt in executionReceipts {
                _ = try auditStore.save(nativeToolExecutionReceipt: executionReceipt)
            }
            await loadAudit()
            error = executionReceipts.last?.errors.isEmpty == true ? nil : executionReceipts.last?.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func inspectContainers() async {
        let activityID = activities.begin(.review, message: "Inspecting containers")
        defer { activities.finish(.review, id: activityID) }
        do {
            let report = await Task.detached {
                ContainerInventoryScanner().inspect()
            }.value
            containerInventory = report
            _ = try AuditStore().save(containerInventoryReport: report)
            await loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyActiveFileStatuses(from report: ActiveFileReviewReport) {
        var statusByPath: [String: OpenFileStatus] = [:]
        for item in report.items {
            if let status = item.finding.openFileStatus {
                statusByPath[item.finding.path] = status
            }
        }
        guard !statusByPath.isEmpty else { return }
        findings = findings.map { finding in
            if let status = statusByPath[finding.path] {
                return finding.withOpenFileStatus(status)
            }
            return finding
        }
        refreshReviewQueueReport()
    }

}
