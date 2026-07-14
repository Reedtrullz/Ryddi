import ReclaimerCore

protocol ScanServicing: Sendable {
    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult
}

extension FileScanner: ScanServicing {}

struct DashboardDependencies: Sendable {
    private let scanServiceFactory: @Sendable (Bool) throws -> any ScanServicing

    init(scanServiceFactory: @escaping @Sendable (Bool) throws -> any ScanServicing) {
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

    static func testing(scanService: any ScanServicing) -> DashboardDependencies {
        DashboardDependencies { _ in scanService }
    }
}
