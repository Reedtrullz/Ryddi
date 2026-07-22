import Foundation
import CryptoKit

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

    public init(ruleEngine: RuleEngine? = nil) {
        self.ruleEngine = ruleEngine
    }

    public func scan(path: String) throws -> [ReclaimRecommendation] {
        let root = canonicalizedPath(path)
        let rootURL = URL(fileURLWithPath: root)
        let rootComps = rootURL.pathComponents
        var recs: [ReclaimRecommendation] = []
        var dirSize: [String: Int64] = [:]
        var duplicateMap: [String: [(url: URL, size: Int64)]] = [:]
        var seenPaths: Set<String> = []
        var dirMeta: [(path: String, mtime: Date)] = []
        var fileCount = 0
        let maxFiles = 500_000
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

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            fileCount += 1
            if fileCount > maxFiles {
                throw DeepAuditError.tooManyFiles(limit: maxFiles)
            }

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
            if seenPaths.contains(p) { continue }
            let ds = dirSize[p, default: 0]
            let lower = p.lowercased()
            var category: BloatCategory?
            var desc = ""
            var action: ReclaimAction = .moveToTrash
            let reclaimSize = ds

            if pathContains(p, ".build") || pathContains(p, "target") || pathContains(p, "deriveddata") || pathContains(p, "node_modules/.cache") || pathContains(p, "__pycache__") || pathContains(p, ".gradle/build") || pathContains(p, ".swiftpm/debug") || pathContains(p, ".spm-build") {
                if ds > 10 * 1024 * 1024 {
                    category = .buildArtifact
                    desc = "Build artifacts are regenerable from source."
                }
            } else if pathContains(p, "build") {
                if ds > 10 * 1024 * 1024 {
                    category = .buildArtifact
                    desc = "Generic build-named folder; confirm that it is generated output."
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

        let duplicateHashBudget: Int64 = 4 * 1024 * 1024 * 1024
        for (_, candidates) in duplicateMap where candidates.count > 1 {
            let candidateBytes = candidates.reduce(Int64(0)) { partial, candidate in
                let (sum, overflow) = partial.addingReportingOverflow(candidate.size)
                return overflow ? Int64.max : sum
            }
            guard candidateBytes <= duplicateHashBudget else { continue }
            var byDigest: [String: [(url: URL, size: Int64)]] = [:]
            for candidate in candidates {
                try Task.checkCancellation()
                guard let digest = try contentDigest(of: candidate.url) else { continue }
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

        let checker = SafetyChecker()
        let checked = checker.check(recs, scanRoot: root)
        return collapseOverlappingActions(removingParentsThatContainReviewFindings(checked))
    }

    private func contentDigest(of url: URL) throws -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                hasher.update(data: data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func collapseOverlappingActions(_ recommendations: [ReclaimRecommendation]) -> [ReclaimRecommendation] {
        let ordered = recommendations.sorted {
            let lhsDepth = URL(fileURLWithPath: $0.path).pathComponents.count
            let rhsDepth = URL(fileURLWithPath: $1.path).pathComponents.count
            return lhsDepth == rhsDepth ? $0.path < $1.path : lhsDepth < rhsDepth
        }
        var retained: [ReclaimRecommendation] = []
        for recommendation in ordered {
            let covered = retained.contains { parent in
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
        _ recommendations: [ReclaimRecommendation]
    ) -> [ReclaimRecommendation] {
        recommendations.filter { parent in
            guard parent.action == .moveToTrash, parent.safetyScore >= 0.8 else { return true }
            let parentComponents = URL(fileURLWithPath: parent.path).pathComponents
            return !recommendations.contains { child in
                guard child.id != parent.id,
                      child.action == .reviewRequired || child.safetyScore < 0.8 else { return false }
                let childComponents = URL(fileURLWithPath: child.path).pathComponents
                return childComponents.count > parentComponents.count
                    && Array(childComponents.prefix(parentComponents.count)) == parentComponents
            }
        }
    }
}
