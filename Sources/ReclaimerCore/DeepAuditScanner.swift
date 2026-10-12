import Foundation
import CryptoKit
import Darwin

func canonicalizedPath(_ path: String) -> String {
    let maxLen = 4096
    var buf = [CChar](repeating: 0, count: maxLen)
    guard realpath(path, &buf) != nil else { return (path as NSString).standardizingPath }
    let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

public enum DeepAuditError: Error, Sendable {
    case tooManyFiles(limit: Int)
}

public final class DeepAuditScanner: @unchecked Sendable {
    private let ruleEngine: RuleEngine?
    private let timeout: TimeInterval
    private let maximumEntries: Int
    private let maximumHashBytes: Int64

    public init(ruleEngine: RuleEngine? = nil, timeout: TimeInterval = 60,
                maximumEntries: Int = 500_000, maximumHashBytes: Int64 = 256 * 1024 * 1024) {
        self.ruleEngine = ruleEngine
        self.timeout = timeout
        self.maximumEntries = maximumEntries
        self.maximumHashBytes = maximumHashBytes
    }

    public func scan(path: String) throws -> [ReclaimRecommendation] {
        var budget = ScanBudget(timeout: timeout, maximumEntries: maximumEntries, maximumHashBytes: maximumHashBytes)
        try budget.check()
        let root = canonicalizedPath(path)
        let rootURL = URL(fileURLWithPath: root)
        let rootComps = rootURL.pathComponents
        var recs: [ReclaimRecommendation] = []
        var dirSize: [String: Int64] = [:]
        var duplicateMap: [String: [(url: URL, size: Int64)]] = [:]
        var seenPaths: Set<String> = []
        var dirMeta: [(path: String, mtime: Date)] = []
        let now = Date()
        let calendar = Calendar.current

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        func isUnderRoot(_ url: URL) -> Bool {
            let comps = url.pathComponents
            return comps.count >= rootComps.count && Array(comps.prefix(rootComps.count)) == rootComps
        }

        func pathContains(_ fullPath: String, _ name: String) -> Bool {
            let lower = fullPath.lowercased()
            return lower.contains("/\(name)/") || lower.hasSuffix("/\(name)")
        }

        while true {
            try budget.check()
            guard let url = enumerator.nextObject() as? URL else { break }
            try budget.visitEntry()

            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
            if vals?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            let size = Int64(vals?.fileSize ?? 0)
            let mtime = vals?.contentModificationDate ?? Date.distantPast
            let isDir = vals?.isDirectory ?? false
            let p = url.path

            if size > 0 {
                var cursor = url.deletingLastPathComponent()
                while cursor.path != root && isUnderRoot(cursor) {
                    dirSize[cursor.path, default: 0] += size
                    cursor.deleteLastPathComponent()
                }
                dirSize[root, default: 0] += size
            }

            if size > 0 {
                let key = "\(url.lastPathComponent)|\(size)"
                duplicateMap[key, default: []].append((url, size))
            }

            if !seenPaths.contains(p) {
                let lower = p.lowercased()
                let ext = url.pathExtension.lowercased()
                var category: BloatCategory?
                var desc = ""
                var action: ReclaimAction = .moveToTrash
                var reclaimSize = size

                if isDir {
                    dirMeta.append((p, mtime))
                } else {
                    if ext == "log" || ext == "crash" {
                        let threshold = ext == "crash" ? 90 : 30
                        if size > 1 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > threshold {
                            category = .oldLog
                            desc = "Old log/crash file older than \(threshold) days."
                        }
                    } else if lower.contains(".codex/sessions/") || lower.contains(".claude/projects/") || lower.contains(".aider") || lower.contains(".cursor/sessions/") {
                        if size > 1 * 1024 * 1024 {
                            category = .aiSessionCache
                            desc = "AI agent session cache."
                        }
                    } else if (ext == "dmg" || ext == "pkg" || ext == "zip"),
                              lower.contains("downloads/"),
                              size > 10 * 1024 * 1024,
                              calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 90 {
                        category = .oldInstaller
                        desc = "Old installer/package in Downloads."
                    } else if (ext == "iso" || ext == "vmdk" || ext == "dmg" || ext == "pkg" || lower.hasSuffix(".tar.gz")),
                              size > 1 * 1024 * 1024 * 1024 {
                        category = .largeBinary
                        desc = "Large binary file."
                        action = .reviewRequired
                    }
                }

                if category == nil, let engine = ruleEngine {
                    let c = engine.classify(path: p, isDirectory: isDir, isSymbolicLink: false)
                    if c.safetyClass == .autoSafe || c.safetyClass == .safeAfterCondition {
                        category = .oldLog
                        desc = c.matches.first?.title ?? "Rule-classified bloat"
                        reclaimSize = size
                    }
                }

                if let cat = category {
                    recs.append(ReclaimRecommendation(
                        path: p, category: cat, reclaimableBytes: reclaimSize,
                        safetyScore: 0.5, effortScore: 1.0,
                        description: desc, action: action,
                        identity: FileIdentity.capture(path: p)
                    ))
                    seenPaths.insert(p)
                }
            }
        }

        for (p, mtime) in dirMeta {
            try budget.check()
            if seenPaths.contains(p) { continue }
            let ds = dirSize[p, default: 0]
            let lower = p.lowercased()
            var category: BloatCategory?
            var desc = ""
            var action: ReclaimAction = .moveToTrash
            let reclaimSize = ds

            if isBuildArtifactPath(p) {
                if ds > 10 * 1024 * 1024 {
                    category = .buildArtifact
                    desc = "Build-looking directory; producer and descendant evidence is unverified."
                    action = .reviewRequired
                }
            } else if pathContains(p, "node_modules") || pathContains(p, "vendor") || pathContains(p, ".gradle") || pathContains(p, "pods") || pathContains(p, ".swiftpm/cache") || pathContains(p, ".pub-cache") || pathContains(p, "carthage/build") || pathContains(p, "go/pkg/mod") {
                if ds > 10 * 1024 * 1024 {
                    category = .dependencyCache
                    desc = "Dependency cache can be rebuilt from manifest."
                }
            } else if pathContains(p, "xcode/archives") || pathContains(p, "devicesupport") || pathContains(p, "ios device logs") || pathContains(p, "coresimulator/devices") {
                if ds > 50 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 90 {
                    category = .xcodeCruft
                    desc = "Old Xcode archives or device support data."
                }
            } else if pathContains(p, ".docker") || pathContains(p, ".colima") || lower.contains("library/containers/com.docker.docker") {
                if ds > 100 * 1024 * 1024 {
                    category = .dockerLayer
                    desc = "Docker/Colima runtime data. Use docker prune."
                    action = .reviewRequired
                }
            } else if pathContains(p, ".trash") {
                if ds > 1 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 30 {
                    category = .trashOld
                    desc = "Files in Trash older than 30 days."
                }
            } else if lower.contains(".git/") && lower.contains("/objects/pack") {
                if ds > 100 * 1024 * 1024 {
                    category = .gitBloat
                    desc = "Git pack files are large. Run `git gc` instead of deleting."
                    action = .reviewRequired
                }
            }

            if let cat = category {
                recs.append(ReclaimRecommendation(
                    path: p, category: cat, reclaimableBytes: reclaimSize,
                    safetyScore: 0.5, effortScore: 1.0,
                    description: desc, action: action,
                    identity: FileIdentity.capture(path: p)
                ))
                seenPaths.insert(p)
            }
        }

        for (_, candidates) in duplicateMap where candidates.count > 1 {
            try budget.check()
            let candidateBytes = candidates.reduce(Int64(0)) { total, candidate in
                let (sum, overflow) = total.addingReportingOverflow(candidate.size)
                return overflow ? Int64.max : sum
            }
            try budget.requireHashCapacity(candidateBytes)
            var byDigest: [String: [(url: URL, size: Int64)]] = [:]
            for candidate in candidates {
                try Task.checkCancellation()
                guard let digest = try contentDigest(of: candidate.url, budget: &budget) else { continue }
                byDigest[digest, default: []].append(candidate)
            }
            for matches in byDigest.values where matches.count > 1 {
                let ordered = matches.sorted { $0.url.path < $1.url.path }
                let preserved = ordered[0].url.path
                for duplicate in ordered.dropFirst() where duplicate.size > 5 * 1024 * 1024 {
                    recs.append(ReclaimRecommendation(
                        path: duplicate.url.path,
                        category: .duplicateFile,
                        reclaimableBytes: duplicate.size,
                        safetyScore: 0.6,
                        effortScore: 0.6,
                        description: "Content-verified duplicate. Preserving \(preserved) by default.",
                        action: .reviewRequired,
                        identity: FileIdentity.capture(path: duplicate.url.path)
                    ))
                }
            }
        }

        try budget.check()
        let checker = SafetyChecker()
        var checked: [ReclaimRecommendation] = []
        for recommendation in recs {
            try budget.check()
            checked.append(contentsOf: checker.check([recommendation], scanRoot: root))
        }
        let withoutParents = try removingParentsThatContainReviewFindings(checked, budget: budget)
        let result = try collapseOverlappingActions(withoutParents, budget: budget)
        try budget.check()
        return result
    }

    private func contentDigest(of url: URL, budget: inout ScanBudget) throws -> String? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        var hasher = SHA256()
        do {
            while true {
                try budget.check()
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                try budget.hash(data.count)
                hasher.update(data: data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScanWorkError {
            throw error
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func collapseOverlappingActions(_ recommendations: [ReclaimRecommendation], budget: ScanBudget) throws -> [ReclaimRecommendation] {
        let ordered = recommendations.sorted {
            let lhsDepth = URL(fileURLWithPath: $0.path).pathComponents.count
            let rhsDepth = URL(fileURLWithPath: $1.path).pathComponents.count
            return lhsDepth == rhsDepth ? $0.path < $1.path : lhsDepth < rhsDepth
        }
        var retained: [ReclaimRecommendation] = []
        for recommendation in ordered {
            try budget.check()
            let covered = try retained.contains { parent in
                try budget.check()
                guard parent.action == .moveToTrash, parent.safetyScore >= 0.8 else { return false }
                let parentComponents = URL(fileURLWithPath: parent.path).pathComponents
                let childComponents = URL(fileURLWithPath: recommendation.path).pathComponents
                return childComponents.count > parentComponents.count
                    && Array(childComponents.prefix(parentComponents.count)) == parentComponents
            }
            if !covered { retained.append(recommendation) }
        }
        return retained
    }

    private func removingParentsThatContainReviewFindings(
        _ recommendations: [ReclaimRecommendation], budget: ScanBudget
    ) throws -> [ReclaimRecommendation] {
        try recommendations.filter { parent in
            try budget.check()
            guard parent.action == .moveToTrash, parent.safetyScore >= 0.8 else { return true }
            let parentComponents = URL(fileURLWithPath: parent.path).pathComponents
            return try !recommendations.contains { child in
                try budget.check()
                guard child.id != parent.id,
                      child.action == .reviewRequired || child.safetyScore < 0.8 else { return false }
                let childComponents = URL(fileURLWithPath: child.path).pathComponents
                return childComponents.count > parentComponents.count
                    && Array(childComponents.prefix(parentComponents.count)) == parentComponents
            }
        }
    }
}
