import Foundation

public final class FastScanner: Sendable {
    private let ruleEngine: RuleEngine

    public init(ruleEngine: RuleEngine) { self.ruleEngine = ruleEngine }

    public func scan(roots: [ScanRoot]) async throws -> [ScanItem] {
        let uniqueRoots = Dictionary(grouping: roots) {
            canonicalizedPath($0.path)
        }.compactMap { _, values in values.first }
        var items: [ScanItem] = []
        for start in stride(from: 0, to: uniqueRoots.count, by: 4) {
            try Task.checkCancellation()
            let end = min(start + 4, uniqueRoots.count)
            let rootsBatch = Array(uniqueRoots[start..<end])
            let batchItems = try await withThrowingTaskGroup(of: [ScanItem].self) { group in
                for root in rootsBatch {
                    group.addTask { try await self.scanOne(root: root) }
                }
                var all: [ScanItem] = []
                for try await scanned in group {
                    try Task.checkCancellation()
                    all.append(contentsOf: scanned)
                }
                return all
            }
            items.append(contentsOf: batchItems)
        }
        var byPath: [String: ScanItem] = [:]
        for item in items {
            let key = item.identity?.canonicalPath ?? canonicalizedPath(item.path)
            if let existing = byPath[key] {
                byPath[key] = moreCautious(existing, item)
            } else {
                byPath[key] = item
            }
        }
        return byPath.values.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func scanOne(root: ScanRoot) async throws -> [ScanItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-k", "-d", "1", root.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try Task.checkCancellation()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else { return [] }

        let rootPath = canonicalizedPath(root.path)
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2, let kb = Int64(parts[0]) else { return nil }
            let childPath = String(parts[1])
            guard let identity = FileIdentity.capture(path: childPath),
                  identity.canonicalPath != rootPath,
                  !identity.isSymbolicLink else { return nil }
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
            return ScanItem(
                name: URL(fileURLWithPath: childPath).lastPathComponent,
                path: childPath, sizeBytes: kb * 1024,
                bucket: bucket,
                ruleTitle: c.matches.first?.title ?? "Unclassified",
                safetyClass: c.safetyClass,
                actionKind: c.actionKind,
                scanRoot: rootPath,
                identity: identity
            )
        }
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
