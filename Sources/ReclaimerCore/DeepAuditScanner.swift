import Foundation

func canonicalPath(_ path: String) -> String {
    let maxLen = 4096
    var buf = [CChar](repeating: 0, count: maxLen)
    guard realpath(path, &buf) != nil else { return (path as NSString).standardizingPath }
    return String(cString: buf)
}

public enum DeepAuditError: Error, Sendable {
    case tooManyFiles(limit: Int)
}

public final class DeepAuditScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let ruleEngine: RuleEngine?

    public init(fileManager: FileManager = .default, ruleEngine: RuleEngine? = nil) {
        self.fileManager = fileManager
        self.ruleEngine = ruleEngine
    }

    public func scan(path: String) throws -> [ReclaimRecommendation] {
        let root = canonicalPath(path)
        let rootURL = URL(fileURLWithPath: root)
        let rootComps = rootURL.pathComponents
        var recs: [ReclaimRecommendation] = []
        var fileList: [(url: URL, size: Int64, mtime: Date, isDir: Bool)] = []
        var totalBytes: Int64 = 0
        var fileCount = 0
        let maxFiles = 500_000

        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else {
            return []
        }

        while let url = enumerator.nextObject() as? URL {
            fileCount += 1
            if fileCount > maxFiles {
                throw DeepAuditError.tooManyFiles(limit: maxFiles)
            }
            do {
                let vals = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                let size = Int64(vals.fileSize ?? 0)
                let mtime = vals.contentModificationDate ?? Date.distantPast
                let isDir = vals.isDirectory ?? false
                totalBytes += size
                fileList.append((url, size, mtime, isDir))
            } catch { continue }
        }

        func isUnderRoot(_ url: URL) -> Bool {
            let comps = url.pathComponents
            return comps.count >= rootComps.count && Array(comps.prefix(rootComps.count)) == rootComps
        }

        var dirSize: [String: Int64] = [:]
        for (url, size, _, _) in fileList {
            var cursor = url
            while cursor.path != root && isUnderRoot(cursor) {
                dirSize[cursor.path, default: 0] += size
                cursor.deleteLastPathComponent()
            }
            dirSize[root, default: 0] += size
        }

        var seenPaths: Set<String> = []
        var duplicateMap: [String: [(path: String, size: Int64)]] = [:]

        for (url, size, _, _) in fileList where size > 0 {
            let key = "\(url.lastPathComponent)|\(size)"
            duplicateMap[key, default: []].append((url.path, size))
        }

        let now = Date()
        let calendar = Calendar.current

        for (url, size, mtime, isDir) in fileList {
            let p = url.path
            if seenPaths.contains(p) { continue }

            let lower = p.lowercased()
            let ext = url.pathExtension.lowercased()

            var category: BloatCategory?
            var desc = ""
            var action: ReclaimAction = .moveToTrash
            var reclaimSize = size

            func pathContains(_ name: String) -> Bool {
                lower.contains("/\(name)/") || lower.hasSuffix("/\(name)")
            }
            if isDir {
                let ds = dirSize[p, default: 0]
                if pathContains(".build") || pathContains("target") || pathContains("deriveddata") || pathContains("node_modules/.cache") || pathContains("__pycache__") || pathContains(".gradle/build") || pathContains(".swiftpm/debug") || pathContains(".spm-build") || pathContains("build") {
                    if ds > 10 * 1024 * 1024 {
                        category = .buildArtifact
                        desc = "Build artifacts are regenerable from source."
                        reclaimSize = ds
                    }
                } else if pathContains("node_modules") || pathContains("vendor") || pathContains(".gradle") || pathContains("pods") || pathContains(".swiftpm/cache") || pathContains(".pub-cache") || pathContains("carthage/build") || pathContains("go/pkg/mod") {
                    if ds > 10 * 1024 * 1024 {
                        category = .dependencyCache
                        desc = "Dependency cache can be rebuilt from manifest."
                        reclaimSize = ds
                    }
                } else if pathContains("xcode/archives") || pathContains("devicesupport") || pathContains("ios device logs") || pathContains("coresimulator/devices") {
                    if ds > 50 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 90 {
                        category = .xcodeCruft
                        desc = "Old Xcode archives or device support data."
                        reclaimSize = ds
                    }
                } else if pathContains(".docker") || pathContains(".colima") || lower.contains("library/containers/com.docker.docker") {
                    if ds > 100 * 1024 * 1024 {
                        category = .dockerLayer
                        desc = "Docker/Colima runtime data. Use docker prune."
                        action = .reviewRequired
                        reclaimSize = ds
                    }
                } else if pathContains(".trash") {
                    if ds > 1 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 30 {
                        category = .trashOld
                        desc = "Files in Trash older than 30 days."
                        reclaimSize = ds
                    }
                } else if lower.contains(".git/") && lower.contains("/objects/pack") {
                    if ds > 100 * 1024 * 1024 {
                        category = .gitBloat
                        desc = "Git pack files are large. Run `git gc` instead of deleting."
                        action = .reviewRequired
                        reclaimSize = ds
                    }
                }
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
                } else if ext == "dmg" || ext == "pkg" || ext == "zip" {
                    if lower.contains("downloads/"), size > 10 * 1024 * 1024, calendar.dateComponents([.day], from: mtime, to: now).day ?? 0 > 90 {
                        category = .oldInstaller
                        desc = "Old installer/package in Downloads."
                    }
                } else if ext == "iso" || ext == "vmdk" || ext == "tar.gz" || ext == "dmg" || ext == "pkg" {
                    if size > 1 * 1024 * 1024 * 1024 {
                        category = .largeBinary
                        desc = "Large binary file."
                        action = .reviewRequired
                    }
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
                    description: desc, action: action
                ))
                seenPaths.insert(p)
            }
        }

        for (_, dups) in duplicateMap where dups.count > 1 {
            let totalDupSize = dups.reduce(0) { $0 + $1.size } * Int64(dups.count - 1)
            if totalDupSize > 10 * 1024 * 1024 {
                let first = dups.first!
                recs.append(ReclaimRecommendation(
                    path: first.path, category: .duplicateFile,
                    reclaimableBytes: totalDupSize,
                    safetyScore: 0.8, effortScore: 0.6,
                    description: "Duplicate file found in \(dups.count) locations (same name and size).",
                    action: .moveToTrash
                ))
            }
        }

        let checker = SafetyChecker()
        return checker.check(recs, scanRoot: root)
    }
}
