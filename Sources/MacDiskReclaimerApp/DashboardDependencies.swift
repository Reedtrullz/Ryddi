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

struct DashboardDependencies: Sendable {
    private let scanServiceFactory: @Sendable (Bool) throws -> any ScanServicing
    let auditSnapshotLoader: any AuditSnapshotLoading

    init(
        auditSnapshotLoader: any AuditSnapshotLoading = AuditStoreSnapshotLoader(),
        scanServiceFactory: @escaping @Sendable (Bool) throws -> any ScanServicing
    ) {
        self.auditSnapshotLoader = auditSnapshotLoader
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
        auditSnapshotLoader: any AuditSnapshotLoading = AuditStoreSnapshotLoader()
    ) -> DashboardDependencies {
        DashboardDependencies(auditSnapshotLoader: auditSnapshotLoader) { _ in scanService }
    }
}
