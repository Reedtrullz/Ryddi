import Foundation
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

    // Shared
    @Published var activePillar = 0
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var showConfirmation = false
    @Published var confirmationTitle = ""
    @Published var confirmationMessage = ""
    @Published var confirmationIsDestructive = false
    @Published var pendingAction: (() -> Void)?

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

    // MARK: - Full scan

    func scanAll() async {
        isScanning = true; errorMessage = nil
        defer { isScanning = false }

        do {
            let engine = try RuleEngine.bundled()
            let scanner = FastScanner(ruleEngine: engine)

            let roots = FastScanner.defaultRoots()
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
