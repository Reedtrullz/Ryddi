import Foundation
import AppKit
import ReclaimerCore

// MARK: - Cloud offload models

struct CloudProvider: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let syncFolderPath: String
    let icon: String
}

struct Grower: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64
    let action: String
    let command: String
    let isSafe: Bool
}

// MARK: - Scan engine

@MainActor
final class ScanEngine: ObservableObject {
    // Clean pillar
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<UUID> = []

    // Offload pillar
    @Published var cloudProviders: [CloudProvider] = []
    @Published var largeLocalFolders: [ScanItem] = []
    @Published var isCopying = false
    @Published var lastCopiedSource: String?
    @Published var lastCopiedDest: String?
    @Published var lastCopiedBytes: Int64 = 0
    @Published var showDeleteOriginalsPrompt = false

    // Control pillar
    @Published var growers: [Grower] = []

    // Custom paths
    @Published var customPaths: [String] = UserDefaults.standard.stringArray(forKey: "customPaths") ?? []

    // Shared
    @Published var activePillar = 0
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var showConfirmation = false
    @Published var confirmationTitle = ""
    @Published var confirmationMessage = ""
    @Published var confirmationIsDestructive = false
    @Published var pendingAction: (() -> Void)?
    @Published var reclaimReportText: String?

    var safeItems: [ScanItem] { items.filter { $0.bucket == .safe } }
    var reviewItems: [ScanItem] { items.filter { $0.bucket == .review } }
    var blockedItems: [ScanItem] { items.filter { $0.bucket == .blocked } }

    var selectedReclaimBytes: Int64 {
        items.filter { $0.bucket == .safe && selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var safeTotalBytes: Int64 { safeItems.reduce(0) { $0 + $1.sizeBytes } }

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

    func scanAll() async {
        isScanning = true; errorMessage = nil
        defer { isScanning = false }

        do {
            let engine = try RuleEngine.bundled()
            let scanner = FastScanner(ruleEngine: engine)

            var roots = FastScanner.defaultRoots()
            for path in customPaths {
                roots.append(ScanRoot(name: URL(fileURLWithPath: path).lastPathComponent, path: path))
            }
            items = try await scanner.scan(roots: roots)
            selectedIDs = Set(safeItems.map(\.id))

            cloudProviders = detectCloudProviders()
            largeLocalFolders = detectLargeLocalFolders()
            growers = try await detectGrowers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Clean

    func reclaim() {
        let toTrash = items.filter { selectedIDs.contains($0.id) && $0.bucket == .safe }
        for item in toTrash {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
        Task { await scanAll() }
    }

    func emergencyReclaim() {
        selectedIDs = Set(safeItems.map(\.id))
        reclaim()
    }

    func generateReclaimReport() -> String {
        let fmt = ByteCountFormatter()
        var report = "🧹 Ryddi reclaim report\n"
        report += "Reclaimed: \(fmt.string(fromByteCount: safeTotalBytes))\n"

        if !safeItems.isEmpty {
            report += "\nClean:\n"
            for item in safeItems.prefix(8) {
                report += "  \(fmt.string(fromByteCount: item.sizeBytes).padding(toLength: 8, withPad: " ", startingAt: 0)) \(item.name)\n"
            }
            if safeItems.count > 8 {
                report += "  ... and \(safeItems.count - 8) more\n"
            }
        }

        let copiedItems = largeLocalFolders.filter { $0.sizeBytes > 0 }
        if !copiedItems.isEmpty {
            report += "\nOffloaded to cloud:\n"
            for item in copiedItems {
                report += "  \(fmt.string(fromByteCount: item.sizeBytes).padding(toLength: 8, withPad: " ", startingAt: 0)) \(item.name)\n"
            }
        }

        let shrunkGrowers = growers.filter { $0.isSafe && $0.sizeBytes > 0 }
        if !shrunkGrowers.isEmpty {
            report += "\nShrunk:\n"
            for g in shrunkGrowers {
                report += "  \(fmt.string(fromByteCount: g.sizeBytes).padding(toLength: 8, withPad: " ", startingAt: 0)) \(g.name)\n"
            }
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
        Task { await scanAll() }
    }

    func removeCustomPath(_ path: String) {
        customPaths.removeAll { $0 == path }
        UserDefaults.standard.set(customPaths, forKey: "customPaths")
        Task { await scanAll() }
    }

    // MARK: - Offload

    func detectCloudProviders() -> [CloudProvider] {
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
        return (candidates + extra).compactMap { name, url, icon in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return CloudProvider(name: name, syncFolderPath: url.path, icon: icon)
        }
    }

    func detectLargeLocalFolders() -> [ScanItem] {
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
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            task.arguments = ["-sk", url.path]
            let pipe = Pipe(); task.standardOutput = pipe
            try? task.run(); task.waitUntilExit()
            guard let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                  let kb = Int64(out.split(separator: "\t").first ?? "0"), kb > 100_000
            else { return nil }
            return ScanItem(name: name, path: url.path, sizeBytes: kb * 1024, bucket: .review, ruleTitle: "Large local folder")
        }
    }

    func copyToCloud(sourcePath: String, provider: CloudProvider) {
        isCopying = true
        defer { isCopying = false }

        let source = URL(fileURLWithPath: sourcePath)
        let dest = URL(fileURLWithPath: provider.syncFolderPath).appendingPathComponent(source.lastPathComponent)
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/cp")
        task.arguments = ["-R", source.path, dest.path]
        try? task.run(); task.waitUntilExit()

        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: dest.path) else {
            errorMessage = "Copy failed. Check permissions and disk space."
            return
        }

        let du = Process(); du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        du.arguments = ["-sk", dest.path]
        let pipe = Pipe(); du.standardOutput = pipe
        try? du.run(); du.waitUntilExit()
        if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
           let kb = Int64(out.split(separator: "\t").first ?? "0") {
            lastCopiedBytes = kb * 1024
        }

        lastCopiedSource = sourcePath
        lastCopiedDest = dest.path
        showDeleteOriginalsPrompt = true
    }

    func deleteOriginalAfterCopy() {
        guard let source = lastCopiedSource else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: source), resultingItemURL: nil)
        lastCopiedSource = nil
        lastCopiedDest = nil
        lastCopiedBytes = 0
        showDeleteOriginalsPrompt = false
        Task { await scanAll() }
    }

    func dismissCopyPrompt() {
        lastCopiedSource = nil
        lastCopiedDest = nil
        lastCopiedBytes = 0
        showDeleteOriginalsPrompt = false
    }

    // MARK: - Control

    func detectGrowers() async throws -> [Grower] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [Grower] = []

        let defs: [(String, URL, String, String, Bool)] = [
            ("Colima VM disk", home.appendingPathComponent(".colima/default"), "Shrink disk",
             "colima stop default && rm ~/.colima/default/diffdisk && colima start default --disk 20", false),
            ("Xcode simulators", home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"),
             "Remove unavailable", "xcrun simctl delete unavailable", true),
            ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
             "Delete DerivedData", "rm -rf ~/Library/Developer/Xcode/DerivedData", true),
            ("Trash", home.appendingPathComponent(".Trash"),
             "Empty Trash", "Finder → Empty Trash", true),
            ("Docker disk image", home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data"),
             "Prune unused data", "docker system prune -a --volumes", false),
        ]

        for (name, path, action, command, isSafe) in defs {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            task.arguments = ["-sk", path.path]
            let pipe = Pipe(); task.standardOutput = pipe
            try task.run(); task.waitUntilExit()
            guard let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                  let kb = Int64(out.split(separator: "\t").first ?? "0"), kb > 5000
            else { continue }
            results.append(Grower(name: name, path: path.path, sizeBytes: kb * 1024,
                                  action: action, command: command, isSafe: isSafe))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func shrinkGrower(_ grower: Grower) {
        if grower.isSafe {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", grower.command]
            try? task.run(); task.waitUntilExit()
            Task { await scanAll() }
        }
    }
}
