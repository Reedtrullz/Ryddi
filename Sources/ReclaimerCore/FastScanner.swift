import Foundation

public final class FastScanner: Sendable {
    private let ruleEngine: RuleEngine
    private let measure: @Sendable (ScanRoot) throws -> ScanProcessOutput

    public init(ruleEngine: RuleEngine) {
        self.ruleEngine = ruleEngine
        self.measure = Self.measureRoot
    }

    init(ruleEngine: RuleEngine, measure: @escaping @Sendable (ScanRoot) throws -> ScanProcessOutput) {
        self.ruleEngine = ruleEngine
        self.measure = measure
    }

    public func scan(roots: [ScanRoot]) async throws -> [ScanItem] {
        let result = try await scanWithCoverage(roots: roots)
        guard result.coverage.allSatisfy({ $0.status == .complete }) else {
            throw ScanCoverageError.incomplete(result.coverage)
        }
        return result.items
    }

    public func scanWithCoverage(roots: [ScanRoot]) async throws -> FastScanResult {
        guard roots.count <= 128 else { throw ScanWorkError.entryLimit }
        let uniqueRoots = Dictionary(grouping: roots) {
            canonicalizedPath($0.path)
        }.compactMap { _, values in values.first }
        var items: [ScanItem] = []
        var coverage: [ScanCoverage] = []
        for start in stride(from: 0, to: uniqueRoots.count, by: 4) {
            try Task.checkCancellation()
            let end = min(start + 4, uniqueRoots.count)
            let rootsBatch = Array(uniqueRoots[start..<end])
            let batch = try await withThrowingTaskGroup(of: FastScanResult.self) { group in
                for root in rootsBatch {
                    group.addTask { try await self.scanOne(root: root) }
                }
                var all: [ScanItem] = []
                var covered: [ScanCoverage] = []
                for try await scanned in group {
                    try Task.checkCancellation()
                    all.append(contentsOf: scanned.items)
                    covered.append(contentsOf: scanned.coverage)
                }
                return FastScanResult(items: all, coverage: covered)
            }
            items.append(contentsOf: batch.items)
            coverage.append(contentsOf: batch.coverage)
        }
        var byPath: [String: ScanItem] = [:]
        for item in items {
            try Task.checkCancellation()
            let key = item.identity?.canonicalPath ?? canonicalizedPath(item.path)
            if let existing = byPath[key] {
                byPath[key] = moreCautious(existing, item)
            } else {
                byPath[key] = item
            }
        }
        return FastScanResult(items: byPath.values.sorted { $0.sizeBytes > $1.sizeBytes },
                              coverage: coverage.sorted { $0.path < $1.path })
    }

    private func scanOne(root: ScanRoot) async throws -> FastScanResult {
        do { return try await runCancellableScan { try self.scanOneSynchronously(root: root) } }
        catch is CancellationError { throw CancellationError() }
        catch {
            return FastScanResult(items: [], coverage: [ScanCoverage(path: root.path, status: .failed, reasons: [error.localizedDescription])])
        }
    }

    private static func measureRoot(_ root: ScanRoot) throws -> ScanProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-k", "-d", "1", root.path]
        return try BoundedScanProcess.run(process, timeout: 30, maximumOutputBytes: 8 * 1024 * 1024)
    }

    private func scanOneSynchronously(root: ScanRoot) throws -> FastScanResult {
        var budget = ScanBudget(timeout: 30, maximumEntries: 100_000)
        guard let rootIdentity = FileIdentity.capture(path: root.path) else {
            return FastScanResult(items: [], coverage: [ScanCoverage(path: root.path, status: .failed, reasons: ["Root identity/access unavailable."])])
        }
        guard rootIdentity.isDirectory, !rootIdentity.isSymbolicLink else {
            return FastScanResult(items: [], coverage: [ScanCoverage(path: root.path, status: .skipped, reasons: ["Only non-symlink directory roots are scanned."])])
        }
        guard FileManager.default.isReadableFile(atPath: root.path) else {
            return FastScanResult(items: [], coverage: [ScanCoverage(path: root.path, status: .failed, reasons: ["Root is not readable."])])
        }
        let result = try measure(root)
        guard let output = String(data: result.data, encoding: .utf8) else {
            return FastScanResult(items: [], coverage: [ScanCoverage(path: root.path, status: .failed, reasons: ["Measurement output is not UTF-8."])])
        }
        var reasons: [String] = result.status == 0 ? [] : ["du exited with status \(result.status); totals may be incomplete."]

        let rootPath = rootIdentity.canonicalPath
        let rootComponents = URL(fileURLWithPath: rootPath).pathComponents
        var items: [ScanItem] = []
        for line in output.split(separator: "\n") {
            try budget.visitEntry()
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2, let kb = Int64(parts[0]), kb >= 0, kb <= Int64.max / 1024 else {
                if reasons.count < 32 { reasons.append("Invalid measurement row skipped.") }
                continue
            }
            let childPath = String(parts[1])
            if canonicalizedPath(childPath) == rootPath { continue }
            guard let identity = FileIdentity.capture(path: childPath), !identity.isSymbolicLink else {
                if reasons.count < 32 { reasons.append("Measured child identity unavailable or changed: \(childPath)") }
                continue
            }
            let components = URL(fileURLWithPath: identity.canonicalPath).pathComponents
            guard components.count > rootComponents.count,
                  Array(components.prefix(rootComponents.count)) == rootComponents else {
                if reasons.count < 32 { reasons.append("Measurement outside requested root skipped.") }
                continue
            }
            let c = ruleEngine.classify(
                path: childPath,
                isDirectory: identity.isDirectory,
                isSymbolicLink: identity.isSymbolicLink
            )
            let bucket: Bucket = switch c.safetyClass {
            case .autoSafe: .safe
            case .safeAfterCondition: .review
            case .preserveByDefault, .reviewRequired: .review
            case .neverTouch: .blocked
            }
            items.append(ScanItem(
                name: URL(fileURLWithPath: childPath).lastPathComponent,
                path: childPath, sizeBytes: kb * 1024,
                bucket: bucket,
                ruleTitle: c.matches.first?.title ?? "Unclassified",
                safetyClass: c.safetyClass,
                actionKind: c.actionKind,
                scanRoot: rootPath,
                identity: identity
            ))
        }
        try budget.check()
        let incomplete = !reasons.isEmpty
        if incomplete {
            items = items.map {
                ScanItem(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes,
                         bucket: $0.bucket == .blocked ? .blocked : .review,
                         ruleTitle: $0.ruleTitle + " (incomplete coverage)",
                         safetyClass: $0.safetyClass == .neverTouch ? .neverTouch : .reviewRequired,
                         actionKind: $0.actionKind, scanRoot: $0.scanRoot, identity: $0.identity)
            }
        }
        return FastScanResult(items: items, coverage: [ScanCoverage(path: rootPath,
                              status: incomplete ? (items.isEmpty ? .failed : .partial) : .complete,
                              reasons: reasons)])
    }

    private func moreCautious(_ lhs: ScanItem, _ rhs: ScanItem) -> ScanItem {
        func rank(_ bucket: Bucket) -> Int {
            switch bucket {
            case .safe: 0
            case .review: 1
            case .blocked: 2
            }
        }
        if rank(rhs.bucket) != rank(lhs.bucket) {
            return rank(rhs.bucket) > rank(lhs.bucket) ? rhs : lhs
        }
        return rhs.safetyClass.riskRank > lhs.safetyClass.riskRank ? rhs : lhs
    }

    public static func defaultRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ScanRoot] {
        let roots: [(String, URL)] = [
            ("Homebrew cache", home.appendingPathComponent("Library/Caches/Homebrew")),
            ("npm cache", home.appendingPathComponent(".npm")),
            ("pip cache", home.appendingPathComponent("Library/Caches/pip")),
            ("Cargo cache", home.appendingPathComponent(".cargo")),
            ("SwiftPM cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm")),
            ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
            ("Playwright browsers", home.appendingPathComponent("Library/Caches/ms-playwright")),
            ("Codex state", home.appendingPathComponent(".codex")),
            ("Claude state", home.appendingPathComponent(".claude")),
            ("Hermes state", home.appendingPathComponent(".hermes")),
            ("VS Code caches", home.appendingPathComponent("Library/Application Support/Code")),
            ("Cursor caches", home.appendingPathComponent("Library/Application Support/Cursor")),
            ("Chrome cache", home.appendingPathComponent("Library/Caches/Google/Chrome")),
            ("Arc cache", home.appendingPathComponent("Library/Caches/Arc")),
            ("Vivaldi cache", home.appendingPathComponent("Library/Caches/Vivaldi")),
            ("fnm Node versions", home.appendingPathComponent(".local/share/fnm")),
            ("Bun cache", home.appendingPathComponent(".bun/install/cache")),
            ("pnpm store", home.appendingPathComponent("Library/pnpm/store")),
            ("LM Studio models", home.appendingPathComponent(".cache/lm-studio")),
            ("User caches", home.appendingPathComponent("Library/Caches")),
            ("User logs", home.appendingPathComponent("Library/Logs")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Trash", home.appendingPathComponent(".Trash")),
        ]
        return roots.compactMap { name, url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ScanRoot(name: name, path: url.path)
        }
    }
}
