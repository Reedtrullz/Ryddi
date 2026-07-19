import Foundation

public final class FastScanner: @unchecked Sendable {
    private let ruleEngine: RuleEngine

    public init(ruleEngine: RuleEngine) { self.ruleEngine = ruleEngine }

    public func scan(roots: [ScanRoot]) async throws -> [ScanItem] {
        let items = try await withThrowingTaskGroup(of: [ScanItem].self) { group in
            for root in roots {
                group.addTask { try await self.scanOne(root: root) }
            }
            var all: [ScanItem] = []
            for try await batch in group { all.append(contentsOf: batch) }
            return all
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func scanOne(root: ScanRoot) async throws -> [ScanItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-k", "-d", "1", root.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2, let kb = Int64(parts[0]) else { return nil }
            let childPath = String(parts[1])
            let c = ruleEngine.classify(path: childPath, isDirectory: true, isSymbolicLink: false)
            let bucket: Bucket = switch c.safetyClass {
            case .autoSafe, .safeAfterCondition: .safe
            case .preserveByDefault, .reviewRequired: .review
            case .neverTouch: .blocked
            }
            return ScanItem(
                name: URL(fileURLWithPath: childPath).lastPathComponent,
                path: childPath, sizeBytes: kb * 1024,
                bucket: bucket,
                ruleTitle: c.matches.first?.title ?? "Unclassified"
            )
        }
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
