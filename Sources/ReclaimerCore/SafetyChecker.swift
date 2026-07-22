import Foundation

public struct SafetyChecker {
    public init() {}

    public func check(_ recommendations: [ReclaimRecommendation], scanRoot: String) -> [ReclaimRecommendation] {
        let root = canonicalizedPath(scanRoot)
        let rootComps = URL(fileURLWithPath: root).pathComponents
        let appBundle = (Bundle.main.bundlePath as NSString).standardizingPath
        let fm = FileManager.default
        let now = Date()
        let calendar = Calendar.current

        func isUnderRoot(_ path: String) -> Bool {
            let comps = URL(fileURLWithPath: canonicalizedPath(path)).pathComponents
            return comps.count >= rootComps.count && Array(comps.prefix(rootComps.count)) == rootComps
        }

        return recommendations.map { rec in
            var r = rec
            var modified = false
            let p = canonicalizedPath(rec.path)
            let isOutsideRoot = !isUnderRoot(p)
            if isOutsideRoot {
                r = copy(r, safetyScore: 0.1, action: .reviewRequired)
                modified = true
            }

            if p.contains(".git/") {
                r = copy(r, description: "Git repository detected. Run `git gc` to reduce pack size instead of deleting.", action: .reviewRequired)
                modified = true
            }

            if p.hasPrefix(appBundle) {
                r = copy(r, safetyScore: 0.0, action: .reviewRequired)
                modified = true
            }

            if rec.category == .aiSessionCache {
                r = copy(
                    r,
                    safetyScore: 0.2,
                    description: "AI session history is preserve-by-default; review retention manually.",
                    action: .reviewRequired
                )
                modified = true
            }

            if rec.category == .duplicateFile || rec.category == .trashOld {
                r = copy(
                    r,
                    safetyScore: defaultSafety(for: rec.category),
                    effortScore: defaultEffort(for: rec.category),
                    action: .reviewRequired
                )
                modified = true
            }

            if p.contains("node_modules/") || p.hasSuffix("/node_modules") {
                var cursor = URL(fileURLWithPath: p)
                while cursor.path != root && isUnderRoot(cursor.path) {
                    let pkg = cursor.appendingPathComponent("package.json").path
                    if fm.fileExists(atPath: pkg) {
                        if let attrs = try? fm.attributesOfItem(atPath: pkg),
                           let mtime = attrs[.modificationDate] as? Date,
                           calendar.dateComponents([.day], from: mtime, to: now).day ?? 8 < 8 {
                            r = copy(r, safetyScore: 0.3, description: "Active project (package.json modified within 7 days).", action: .reviewRequired)
                            modified = true
                        }
                        break
                    }
                    cursor.deleteLastPathComponent()
                }
            }

            if rec.category == .buildArtifact || p.contains("target/") || p.contains(".build/") || p.hasSuffix("/target") || p.hasSuffix("/.build") {
                let comps = URL(fileURLWithPath: p).pathComponents
                var buildPath: String?
                for (i, comp) in comps.enumerated() {
                    let lower = comp.lowercased()
                    if lower == "target" || lower == ".build" {
                        buildPath = NSString.path(withComponents: Array(comps.prefix(i + 1)))
                    }
                }
                if let bp = buildPath, let attrs = try? fm.attributesOfItem(atPath: bp),
                   let mtime = attrs[.modificationDate] as? Date,
                   calendar.dateComponents([.hour], from: mtime, to: now).hour ?? 25 < 25 {
                    r = copy(r, safetyScore: 0.3, description: "Build directory modified within last 24 hours.", action: .reviewRequired)
                    modified = true
                }
            }

            if !modified {
                let defaultScore = defaultSafety(for: rec.category)
                let score = rec.action == .reviewRequired ? min(defaultScore, 0.6) : defaultScore
                r = copy(r, safetyScore: score, effortScore: defaultEffort(for: rec.category))
            }

            if isOutsideRoot {
                r = copy(
                    r,
                    safetyScore: min(r.safetyScore, 0.1),
                    description: "Outside the reviewed scan root; no cleanup action is allowed.",
                    action: .reviewRequired
                )
            }

            return r
        }
    }

    private func copy(_ rec: ReclaimRecommendation, path: String? = nil, category: BloatCategory? = nil,
                      reclaimableBytes: Int64? = nil, safetyScore: Double? = nil, effortScore: Double? = nil,
                      description: String? = nil, action: ReclaimAction? = nil) -> ReclaimRecommendation {
        ReclaimRecommendation(
            path: path ?? rec.path,
            category: category ?? rec.category,
            reclaimableBytes: reclaimableBytes ?? rec.reclaimableBytes,
            safetyScore: safetyScore ?? rec.safetyScore,
            effortScore: effortScore ?? rec.effortScore,
            description: description ?? rec.description,
            action: action ?? rec.action,
            identity: rec.identity
        )
    }

    private func defaultSafety(for category: BloatCategory) -> Double {
        switch category {
        case .buildArtifact, .oldLog:
            return 0.9
        case .duplicateFile:
            return 0.6
        case .dependencyCache, .oldInstaller, .xcodeCruft, .dockerLayer, .trashOld:
            return 0.6
        case .largeBinary, .gitBloat, .aiSessionCache:
            return 0.2
        }
    }

    private func defaultEffort(for category: BloatCategory) -> Double {
        switch category {
        case .duplicateFile:
            return 0.6
        case .gitBloat:
            return 0.2
        default:
            return 1.0
        }
    }
}
