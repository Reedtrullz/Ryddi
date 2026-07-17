import ReclaimerCore

protocol ScanServicing: Sendable {
    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult
}

extension FileScanner: ScanServicing {}

protocol AuditSnapshotLoading: Sendable {
    func load(limitPerKind: Int) -> AuditStoreSnapshot
}

struct AuditStoreSnapshotLoader: AuditSnapshotLoading {
    func load(limitPerKind: Int) -> AuditStoreSnapshot {
        AuditStore().snapshot(limitPerKind: limitPerKind)
    }
}

protocol PermissionReportLoading: Sendable {
    func load(scopes: [ScanScope]) -> PermissionAdvisorReport
}

struct PermissionReportLoader: PermissionReportLoading {
    func load(scopes: [ScanScope]) -> PermissionAdvisorReport {
        PermissionAdvisor.report(scopes: scopes)
    }
}

protocol GuidedMapPersisting: Sendable {
    func loadLatest() -> GuidedMapSnapshot?
    func save(_ snapshot: GuidedMapSnapshot) throws
}

struct GuidedMapStoreAdapter: GuidedMapPersisting {
    private let store = GuidedMapStore()

    func loadLatest() -> GuidedMapSnapshot? {
        store.latest()
    }

    func save(_ snapshot: GuidedMapSnapshot) throws {
        try store.save(snapshot)
    }
}

struct DashboardDependencies: Sendable {
    private let scanServiceFactory: @Sendable (Bool) throws -> any ScanServicing
    let auditSnapshotLoader: any AuditSnapshotLoading
    let permissionReportLoader: any PermissionReportLoading
    let guidedMapStore: any GuidedMapPersisting

    init(
        auditSnapshotLoader: any AuditSnapshotLoading = AuditStoreSnapshotLoader(),
        permissionReportLoader: any PermissionReportLoading = PermissionReportLoader(),
        guidedMapStore: any GuidedMapPersisting = GuidedMapStoreAdapter(),
        scanServiceFactory: @escaping @Sendable (Bool) throws -> any ScanServicing
    ) {
        self.auditSnapshotLoader = auditSnapshotLoader
        self.permissionReportLoader = permissionReportLoader
        self.guidedMapStore = guidedMapStore
        self.scanServiceFactory = scanServiceFactory
    }

    func makeScanService(includingUserRules: Bool) throws -> any ScanServicing {
        try scanServiceFactory(includingUserRules)
    }

    static let live = DashboardDependencies { includeUserRules in
        try FileScanner(
            ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
            openFileChecker: NoOpenFilesChecker()
        )
    }

    static func testing(
        scanService: any ScanServicing,
        auditSnapshotLoader: any AuditSnapshotLoading = AuditStoreSnapshotLoader(),
        permissionReportLoader: any PermissionReportLoading = PermissionReportLoader(),
        guidedMapStore: any GuidedMapPersisting = GuidedMapStoreAdapter()
    ) -> DashboardDependencies {
        DashboardDependencies(
            auditSnapshotLoader: auditSnapshotLoader,
            permissionReportLoader: permissionReportLoader,
            guidedMapStore: guidedMapStore
        ) { _ in scanService }
    }
}
