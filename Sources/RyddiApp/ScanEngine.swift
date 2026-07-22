import Foundation
import AppKit
import ReclaimerCore
import Darwin

// MARK: - Cloud offload models

struct CloudProvider: Identifiable, Hashable, Sendable {
    let name: String
    let syncFolderPath: String
    let icon: String
    var id: String { syncFolderPath }
}

struct Grower: Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let sizeBytes: Int64
    let action: String
    let command: String
    let isSafe: Bool
    let identity: FileIdentity
    var id: String { path }
}

// MARK: - Scan engine

public enum CleanViewMode: String, CaseIterable, Sendable {
    case list = "List"
    case chart = "Chart"
}

@MainActor
final class ScanEngine: ObservableObject {
    // Clean pillar
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var cleanViewMode: CleanViewMode = .list

    @Published private var expandedGroups: Set<String> = []

    // Offload pillar
    @Published var cloudProviders: [CloudProvider] = []
    @Published var largeLocalFolders: [ScanItem] = []
    @Published var isCopying = false
    @Published var lastCopiedSource: String?
    @Published var lastCopiedDest: String?
    @Published var lastCopiedBytes: Int64 = 0
    @Published var showCopyComplete = false

    // Control pillar
    @Published var growers: [Grower] = []

    @Published var auditReport: AuditReport? = nil
    @Published var auditSelectedIDs: Set<UUID> = []
    @Published var isAuditing = false

    // Custom paths
    @Published var customPaths: [String] = UserDefaults.standard.stringArray(forKey: "customPaths") ?? []

    // Shared
    @Published var activePillar = 0
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasEverScanned = false
    @Published var errorMessage: String?
    @Published var showConfirmation = false
    @Published var confirmationTitle = ""
    @Published var confirmationMessage = ""
    @Published var confirmationIsDestructive = false
    @Published var pendingAction: (() -> Void)?
    @Published var reclaimReportText: String?

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    var safeItems: [ScanItem] { items.filter { $0.bucket == .safe } }
    var reviewItems: [ScanItem] { items.filter { $0.bucket == .review } }
    var blockedItems: [ScanItem] { items.filter { $0.bucket == .blocked } }

    var selectedReclaimBytes: Int64 {
        items.filter { $0.bucket == .safe && selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var safeTotalBytes: Int64 { safeItems.reduce(0) { $0 + $1.sizeBytes } }

    var selectedAuditBytes: Int64 {
        guard let report = auditReport else { return 0 }
        return report.recommendations
            .filter { auditSelectedIDs.contains($0.id) && $0.safetyScore >= 0.8 && $0.action == .moveToTrash }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }

    func groupedItems(_ bucketItems: [ScanItem]) -> [ScanItemGroup] {
        let dict = Dictionary(grouping: bucketItems) { $0.groupKey }
        return dict.map { ScanItemGroup(baseName: $0.key, items: $0.value) }
            .sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    func isGroupExpanded(_ baseName: String) -> Bool {
        expandedGroups.contains(baseName)
    }

    func setGroupExpanded(_ baseName: String, expanded: Bool) {
        if expanded {
            expandedGroups.insert(baseName)
        } else {
            expandedGroups.remove(baseName)
        }
    }

    func selectGroup(_ group: ScanItemGroup, selected: Bool) {
        let ids = Set(group.items.map(\.id))
        if selected {
            selectedIDs.formUnion(ids)
        } else {
            selectedIDs.subtract(ids)
        }
    }

    var needsFullDiskAccess: Bool {
        let test = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
        return !FileManager.default.isReadableFile(atPath: test.path)
    }

    var isEmergency: Bool {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (vals?.volumeAvailableCapacityForImportantUsage ?? Int64.max) < 10_737_418_240 // 10 GB
    }

    // MARK: - Full scan

    func scanAll(preservingError: Bool = false) {
        cancelScan()
        let generation = UUID()
        scanGeneration = generation
        isScanning = true
        selectedIDs = []
        auditSelectedIDs = []
        if !preservingError { errorMessage = nil }
        scanTask = Task {
            defer {
                if scanGeneration == generation { isScanning = false }
            }
            do {
                let engine = try RuleEngine.bundled()
                let scanner = FastScanner(ruleEngine: engine)

                var roots = FastScanner.defaultRoots()
                for path in customPaths {
                    roots.append(ScanRoot(name: URL(fileURLWithPath: path).lastPathComponent, path: path))
                }
                let scannedItems = try await scanner.scan(roots: roots)
                guard scanGeneration == generation else { return }
                items = scannedItems
                hasEverScanned = true

                let support = await Task.detached(priority: .utility) {
                    let providers = Self.detectCloudProviders()
                    let folders = Self.detectLargeLocalFolders()
                    let growers = (try? Self.detectGrowers()) ?? []
                    return (providers, folders, growers)
                }.value
                try Task.checkCancellation()
                guard scanGeneration == generation else { return }
                cloudProviders = support.0
                largeLocalFolders = support.1
                growers = support.2
            } catch is CancellationError {
                if scanGeneration == generation { errorMessage = "Scan cancelled." }
            } catch {
                if scanGeneration == generation { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration = UUID()
        isScanning = false
    }

    // MARK: - Clean

    func reclaim() {
        guard !isCleaning, !isScanning else { return }
        let toTrash = items.filter { selectedIDs.contains($0.id) && $0.bucket == .safe }
        guard !toTrash.isEmpty else { return }
        isCleaning = true
        Task {
            let failed = await Task.detached(priority: .userInitiated) {
                var failures: [String] = []
                do {
                    let ruleEngine = try RuleEngine.bundled()
                    let validator = CleanupValidator()
                    for item in toTrash {
                        try Task.checkCancellation()
                        do {
                            let url = try validator.validate(item, ruleEngine: ruleEngine)
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        } catch {
                            failures.append("\(item.name): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    failures.append(error.localizedDescription)
                }
                return failures
            }.value
            isCleaning = false
            if !failed.isEmpty {
                errorMessage = "Some items were not cleaned:\n" + failed.joined(separator: "\n")
            }
            scanAll(preservingError: !failed.isEmpty)
        }
    }

    func selectAllSafe() {
        selectedIDs = Set(safeItems.map(\.id))
    }

    func generateReclaimReport() -> String {
        let fmt = ByteCountFormatter()
        var report = "🧹 Ryddi reclaim report\n"
        report += "Safe opportunities found: \(fmt.string(fromByteCount: safeTotalBytes))\n"

        if !safeItems.isEmpty {
            report += "\nClean:\n"
            for item in safeItems.prefix(8) {
                report += "  \(fmt.string(fromByteCount: item.sizeBytes).padding(toLength: 8, withPad: " ", startingAt: 0)) \(item.name)\n"
            }
            if safeItems.count > 8 {
                report += "  ... and \(safeItems.count - 8) more\n"
            }
        }

        if let copied = lastCopiedDest, lastCopiedBytes > 0 {
            report += "\nCopied to a provider-managed folder (original kept):\n"
            report += "  \(fmt.string(fromByteCount: lastCopiedBytes)) \(URL(fileURLWithPath: copied).lastPathComponent)\n"
        }

        if !blockedItems.isEmpty {
            report += "\n🛡️ Protected (not touched):\n"
            let categories = Set(blockedItems.map(\.ruleTitle))
            for cat in categories.prefix(5) {
                report += "  \(cat)\n"
            }
        }

        report += "\nryddi.reidar.tech"
        return report
    }

    func copyReclaimReport() {
        reclaimReportText = generateReclaimReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reclaimReportText ?? "", forType: .string)
    }

    // MARK: - Custom paths

    func addCustomPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customPaths.contains(trimmed) else { return }
        customPaths.append(trimmed)
        UserDefaults.standard.set(customPaths, forKey: "customPaths")
        scanAll()
    }

    func removeCustomPath(_ path: String) {
        customPaths.removeAll { $0 == path }
        UserDefaults.standard.set(customPaths, forKey: "customPaths")
        scanAll()
    }

    // MARK: - Offload

    nonisolated static func detectCloudProviders() -> [CloudProvider] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(String, URL, String)] = [
            ("Dropbox", home.appendingPathComponent("Dropbox"), "shippingbox.fill"),
            ("Google Drive", home.appendingPathComponent("Google Drive"), "externaldrive.fill.badge.icloud"),
            ("iCloud Drive", home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), "icloud.fill"),
            ("MEGA", home.appendingPathComponent("MEGAsync"), "m.square.fill"),
            ("OneDrive", home.appendingPathComponent("OneDrive"), "externaldrive.fill"),
        ]
        let cloudStorageDir = home.appendingPathComponent("Library/CloudStorage")
        var extra: [(String, URL, String)] = []
        if let entries = try? FileManager.default.contentsOfDirectory(at: cloudStorageDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for entry in entries where entry.hasDirectoryPath {
                extra.append((entry.lastPathComponent, entry, "externaldrive.fill"))
            }
        }
        var seen: Set<String> = []
        return (candidates + extra).compactMap { name, url, icon in
            guard let identity = FileIdentity.capture(path: url.path),
                  identity.isDirectory,
                  !identity.isSymbolicLink,
                  seen.insert(identity.canonicalPath).inserted else { return nil }
            return CloudProvider(name: name, syncFolderPath: identity.canonicalPath, icon: icon)
        }
    }

    nonisolated static func detectLargeLocalFolders() -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(String, URL)] = [
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Movies", home.appendingPathComponent("Movies")),
            ("Pictures", home.appendingPathComponent("Pictures")),
            ("Music", home.appendingPathComponent("Music")),
        ]
        return candidates.compactMap { name, url in
            guard let identity = FileIdentity.capture(path: url.path),
                  identity.isDirectory,
                  !identity.isSymbolicLink,
                  let kb = measuredKilobytes(at: identity.canonicalPath),
                  kb > 100_000 else { return nil }
            return ScanItem(
                name: name,
                path: identity.canonicalPath,
                sizeBytes: kb * 1024,
                bucket: .review,
                ruleTitle: "Large local folder",
                scanRoot: identity.canonicalPath,
                identity: identity
            )
        }
    }

    func copyToCloud(sourcePath: String, provider: CloudProvider) {
        guard !isCopying else { return }
        isCopying = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.performCopy(sourcePath: sourcePath, provider: provider)
            }.value
            isCopying = false
            switch result {
            case .success(let destination, let bytes, let warning):
                lastCopiedSource = sourcePath
                lastCopiedDest = destination
                lastCopiedBytes = bytes
                showCopyComplete = true
                errorMessage = warning
            case .failure(let message):
                errorMessage = message
            }
        }
    }

    func dismissCopyPrompt() {
        lastCopiedSource = nil
        lastCopiedDest = nil
        lastCopiedBytes = 0
        showCopyComplete = false
    }

    // MARK: - Control

    nonisolated static func detectGrowers() throws -> [Grower] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [Grower] = []

        let defs: [(String, URL, String, String, Bool)] = [
            ("Colima VM disk", home.appendingPathComponent(".colima/default"), "Review Colima storage",
             "Inspect with colima list and back up workloads before changing the VM", false),
            ("Xcode simulators", home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"),
             "Review unavailable simulators", "Use Xcode → Settings → Platforms", false),
            ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
             "Move DerivedData to Trash", "Finder Trash (recoverable)", true),
            ("Trash", home.appendingPathComponent(".Trash"),
             "Review Trash", "Finder → Trash", false),
            ("Docker disk image", home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data"),
             "Review Docker storage", "Inspect with docker system df; no cleanup runs from Ryddi", false),
        ]

        for (name, path, action, command, isSafe) in defs {
            guard let identity = FileIdentity.capture(path: path.path),
                  !identity.isSymbolicLink,
                  let kb = measuredKilobytes(at: identity.canonicalPath),
                  kb > 5000 else { continue }
            results.append(Grower(name: name, path: identity.canonicalPath, sizeBytes: kb * 1024,
                                  action: action, command: command, isSafe: isSafe, identity: identity))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func shrinkGrower(_ grower: Grower) {
        guard grower.isSafe, !isCleaning, !isScanning else { return }
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            .standardizedFileURL.path
        guard let expectedIdentity = FileIdentity.capture(path: expected),
              grower.identity.canonicalPath == expectedIdentity.canonicalPath,
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty,
              grower.identity.isDirectory,
              !grower.identity.isSymbolicLink else {
            errorMessage = "Close Xcode and scan again before moving DerivedData to Trash."
            return
        }
        isCleaning = true
        Task {
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    let url = try CleanupValidator().validateRecoverableDirectory(
                        path: grower.path,
                        expectedPath: expected,
                        scannedIdentity: grower.identity
                    )
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            isCleaning = false
            if let failure {
                errorMessage = "\(grower.action) failed: \(failure)"
            } else {
                scanAll()
            }
        }
    }

    func runAudit(path: String, preservingError: Bool = false) {
        guard !isAuditing else { return }
        isAuditing = true
        if !preservingError { errorMessage = nil }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<AuditReport, Error> in
                do {
                    let recs = try DeepAuditScanner().scan(path: path)
                    let total = recs.reduce(0) { $0 + $1.reclaimableBytes }
                    return .success(AuditReport(
                        scannedPaths: [path], totalBytes: total, bloatBytes: total,
                        reclaimableBytes: total, recommendations: recs
                    ))
                } catch {
                    return .failure(error)
                }
            }.value
            isAuditing = false
            switch result {
            case .success(let report):
                auditReport = report
                auditSelectedIDs = []
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func copyAuditReport() {
        guard let report = auditReport else { return }
        let text = AuditReportFormatter.plainText(report: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func reclaimAuditSelection() {
        guard let report = auditReport else { return }
        let toTrash = report.recommendations.filter {
            auditSelectedIDs.contains($0.id) && $0.safetyScore >= 0.8 && $0.action == .moveToTrash
        }
        guard let root = report.scannedPaths.first, !toTrash.isEmpty else { return }
        isCleaning = true
        Task {
            let failed = await Task.detached(priority: .userInitiated) {
                let validator = CleanupValidator()
                var failures: [String] = []
                for recommendation in toTrash {
                    do {
                        try Task.checkCancellation()
                    } catch {
                        failures.append("Cleanup cancelled.")
                        break
                    }
                    do {
                        let url = try validator.validate(recommendation, scanRoot: root)
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } catch {
                        failures.append("\(urlName(recommendation.path)): \(error.localizedDescription)")
                    }
                }
                return failures
            }.value
            isCleaning = false
            if !failed.isEmpty { errorMessage = "Some items were not cleaned:\n" + failed.joined(separator: "\n") }
            runAudit(path: root, preservingError: !failed.isEmpty)
        }
    }
}

private enum CopyResult: Sendable {
    case success(destination: String, bytes: Int64, warning: String?)
    case failure(String)
}

private extension ScanEngine {
    nonisolated static func performCopy(sourcePath: String, provider: CloudProvider) -> CopyResult {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
        guard let identity = FileIdentity.capture(path: source.path), !identity.isSymbolicLink else {
            return .failure("Copy refused: the source is missing or is a symbolic link.")
        }
        let home = fm.homeDirectoryForCurrentUser
        let allowedSourceNames = ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music"]
        let allowedSources = Set(allowedSourceNames.compactMap {
            FileIdentity.capture(path: home.appendingPathComponent($0).path)?.canonicalPath
        })
        guard allowedSources.contains(identity.canonicalPath) else {
            return .failure("Copy refused because the source is outside Ryddi's reviewed Offload folders.")
        }
        guard let providerIdentity = FileIdentity.capture(path: provider.syncFolderPath),
              providerIdentity.isDirectory,
              !providerIdentity.isSymbolicLink else {
            return .failure("Copy refused because the provider folder is missing or is a symbolic link.")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let copyName = "\(source.lastPathComponent) — Ryddi Copy \(formatter.string(from: Date()))"
        let destination = URL(fileURLWithPath: provider.syncFolderPath).appendingPathComponent(copyName)
        guard !fm.fileExists(atPath: destination.path) else {
            return .failure("Copy refused because the destination already exists.")
        }
        do {
            guard identity.matchesCurrent(path: source.path),
                  providerIdentity.matchesCurrent(path: provider.syncFolderPath) else {
                return .failure("Copy refused because the source changed after review.")
            }
            try fm.copyItem(at: source, to: destination)
            guard identity.matchesCurrent(path: source.path),
                  providerIdentity.matchesCurrent(path: provider.syncFolderPath),
                  fm.fileExists(atPath: destination.path) else {
                try? fm.removeItem(at: destination)
                return .failure("Copy could not be verified. The partial copy was removed.")
            }
            let sourceBytes = allocatedBytes(at: source)
            let destinationBytes = allocatedBytes(at: destination)
            let warning: String? = sourceBytes == destinationBytes
                ? nil
                : "Copy completed, but local allocated sizes differ. Keep the original and review the copy in Finder."
            return .success(destination: destination.path, bytes: destinationBytes, warning: warning)
        } catch {
            try? fm.removeItem(at: destination)
            return .failure("Copy failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func allocatedBytes(at url: URL) -> Int64 {
        (measuredKilobytes(at: url.path) ?? 0) * 1024
    }

    nonisolated static func measuredKilobytes(at path: String, timeout: TimeInterval = 10) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                return nil
            }
            usleep(20_000)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8),
              let kilobytes = Int64(output.split(separator: "\t").first ?? "0") else { return nil }
        return kilobytes
    }
}

private func urlName(_ path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
}
