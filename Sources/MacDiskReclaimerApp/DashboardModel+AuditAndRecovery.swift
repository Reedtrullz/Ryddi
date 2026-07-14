import Foundation
import ReclaimerCore

extension DashboardModel {
    func loadSavedScopeSets() {
        let previousSelection = selectedSavedScopeSetID
        savedScopeSets = SavedScopeSetStore().list()
        if let previousSelection, !savedScopeSets.contains(where: { $0.id == previousSelection }) {
            selectedSavedScopeSetID = nil
            resetScanState()
        }
        if overview == nil {
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        }
    }

    func saveCurrentScopeSet(name: String, summary: String?) {
        do {
            let planToSave = selectedScopePlan
            let set = try SavedScopeSetStore().upsert(
                name: name,
                paths: planToSave.scopes.map(\.root.path),
                summary: summary
            )
            savedScopeSets = SavedScopeSetStore().list()
            selectedScopeTemplateID = nil
            selectedSavedScopeSetID = set.id
            resetScanState()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveScopeTemplate(_ template: ScopeTemplate) {
        do {
            let set = try SavedScopeSetStore().upsert(
                name: template.name,
                paths: template.scopes.map(\.root.path),
                summary: template.summary
            )
            savedScopeSets = SavedScopeSetStore().list()
            selectedScopeTemplateID = nil
            selectedSavedScopeSetID = set.id
            resetScanState()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeSavedScopeSet(_ set: SavedScopeSet) {
        do {
            _ = try SavedScopeSetStore().remove(reference: set.id)
            if selectedSavedScopeSetID == set.id {
                selectedSavedScopeSetID = nil
                resetScanState()
            }
            savedScopeSets = SavedScopeSetStore().list()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func importSavedScopeSets(from url: URL, replace: Bool) {
        do {
            let result = try SavedScopeSetStore().importDocument(from: url, merge: !replace)
            lastScopeSetImportResult = result
            loadSavedScopeSets()
            error = nil
        } catch {
            lastScopeSetImportResult = nil
            self.error = error.localizedDescription
        }
    }

    func loadAudit() {
        let store = AuditStore()
        auditStoreSummary = store.summary()
        recentPlans = store.recentPlans()
        recentReceipts = store.recentReceipts()
        recentNativeToolReports = store.recentNativeToolReports()
        recentNativeToolExecutionReceipts = store.recentNativeToolExecutionReceipts()
        recentContainerInventoryReports = store.recentContainerInventoryReports()
        recentRemoteProbeReports = store.recentRemoteProbeReports()
        recentRemoteScanReports = store.recentRemoteScanReports()
        recentRemoteDogfoodReports = store.recentRemoteDogfoodReports()
        if remoteProbeReport == nil {
            remoteProbeReport = recentRemoteProbeReports.first
        }
        if remoteScanReport == nil {
            remoteScanReport = recentRemoteScanReports.first
        }
        syncRemoteDogfoodReport()
        if
            let currentRemoteScan = recentRemoteScanReports.first,
            let previousRemoteScan = store.latestPreviousRemoteScanReport(
                forConcreteTarget: currentRemoteScan.target,
                excludingReportID: currentRemoteScan.id
            )
        {
            remoteGrowthReport = RemoteGrowthReportBuilder.build(
                previous: previousRemoteScan,
                current: currentRemoteScan,
                limit: 10
            )
        } else {
            remoteGrowthReport = nil
        }
        recentActiveFileReviewReports = store.recentActiveFileReviewReports()
        recentTrashReviewReports = store.recentTrashReviewReports()
        recentDownloadsReviewReports = store.recentDownloadsReviewReports()
        recentBrowserCacheReviewReports = store.recentBrowserCacheReviewReports()
        recentPackageCacheReviewReports = store.recentPackageCacheReviewReports()
        recentProjectDependencyReviewReports = store.recentProjectDependencyReviewReports()
        recentDeviceBackupReviewReports = store.recentDeviceBackupReviewReports()
        recentXcodeReviewReports = store.recentXcodeReviewReports()
        recentAppUninstallReceipts = store.recentAppUninstallReceipts()
        loadRecovery()
    }

    func previewAuditPrune() {
        let store = AuditStore()
        let policy = AuditRetentionPolicy(olderThanDays: 90, keepRecent: 20)
        let plan = store.prunePlan(policy: policy)
        auditPrunePlan = plan
        auditPruneReceipt = try? store.prune(plan: plan, dryRun: true)
        auditStoreSummary = store.summary()
    }

    func loadHolding() {
        heldItems = HoldingStore().list()
        loadRecovery()
    }

    func loadRecovery() {
        recoveryReport = RecoveryCenter.build(heldItems: heldItems, receipts: recentReceipts)
    }

    func loadHistory() {
        let store = ScanHistoryStore()
        scanSnapshots = store.recent(limit: 8)
        growthDeltas = store.latestGrowthDeltas(group: .category, limit: 8)
    }

    func loadUserPolicy() {
        userPathPolicy = UserPathPolicyStore().load()
    }

    func refreshPermissions() {
        let transition = PermissionCoverageTransition.refresh(
            previous: permissionReport,
            scopes: currentScopes(includeUnavailable: true)
        )
        if transition.coverageChanged {
            diagnostics.record(.permissionCoverageChanged)
        }
        permissionReport = transition.current
        Task { await refreshPresentationSnapshot() }
    }

    func addUserPathRule(path: String, kind: UserPathPolicyKind, reason: String) async {
        let activityID = activities.begin(.review, message: "Updating path policy")
        defer { activities.finish(.review, id: activityID) }
        do {
            _ = try UserPathPolicyStore().add(path: path, kind: kind, reason: reason)
            userPathPolicy = UserPathPolicyStore().load()
            error = nil
            if !findings.isEmpty {
                activities.finish(.review, id: activityID)
                await scan()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeUserPathRule(_ rule: UserPathRule) async {
        let activityID = activities.begin(.review, message: "Updating path policy")
        defer { activities.finish(.review, id: activityID) }
        do {
            _ = try UserPathPolicyStore().remove(path: rule.path, kind: rule.kind)
            userPathPolicy = UserPathPolicyStore().load()
            error = nil
            if !findings.isEmpty {
                activities.finish(.review, id: activityID)
                await scan()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func installSchedule() {
        do {
            let bundledCLI = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reclaimer")
            let cliPath = FileManager.default.isExecutableFile(atPath: bundledCLI.path)
                ? bundledCLI.path
                : (Bundle.main.executableURL?.path ?? "/usr/local/bin/reclaimer")
            let selection: ScheduledScopeSelection
            if let selectedSavedScopeSetID {
                selection = ScheduledScopeSelection(savedScopeSet: selectedSavedScopeSetID)
            } else if let selectedScopeTemplateID {
                selection = ScheduledScopeSelection(template: selectedScopeTemplateID)
            } else {
                selection = ScheduledScopeSelection(preset: scanPreset)
            }
            let schedule = ScheduleConfiguration(scopeSelection: selection)
            _ = try LaunchAgentManager().install(cliPath: cliPath, schedule: schedule)
            refreshAutomation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func revealScheduleInFinder() {
        PathActions.revealInFinder(LaunchAgentManager().installedPath().path)
    }

    func refreshAutomation() {
        launchAgentStatus = LaunchAgentManager().status()
        launchAgentInstalled = launchAgentStatus.installed
        diskStatus = DiskStatusReader().snapshot()
    }
}
