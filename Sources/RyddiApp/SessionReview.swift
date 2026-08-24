import SwiftUI
import AppKit
import Foundation
import ReclaimerCore
import Darwin

private func normalizedSessionPath(_ path: String) -> String {
    FileIdentity.capture(path: path)?.canonicalPath
        ?? URL(fileURLWithPath: path).standardizedFileURL.path
}

enum SessionSource: String, Sendable, Hashable {
    case codex = "Codex"
    case codexArchive = "Codex Archive"
    case hermes = "Hermes"

    var icon: String {
        switch self {
        case .codex, .codexArchive: "bubble.left.and.text.bubble.right.fill"
        case .hermes: "brain.head.profile.fill"
        }
    }
}

enum SessionUseStatus: Sendable, Hashable {
    case available
    case inUse
    case unknown
}

struct SessionFileFingerprint: Sendable, Hashable {
    let identity: FileIdentity
    let sizeBytes: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int

    static func capture(path: String) -> SessionFileFingerprint? {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              let identity = FileIdentity.capture(path: path), !identity.isSymbolicLink else { return nil }
        return SessionFileFingerprint(
            identity: identity,
            sizeBytes: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec
        )
    }

    func matchesCurrent(path: String) -> Bool {
        guard let current = Self.capture(path: path) else { return false }
        return current == self
    }
}

struct SessionReviewItem: Identifiable, Sendable, Hashable {
    let path: String
    let title: String
    let source: SessionSource
    let modifiedAt: Date
    let fingerprint: SessionFileFingerprint
    let useStatus: SessionUseStatus

    var id: String { path }
    var sizeBytes: Int64 { fingerprint.sizeBytes }
    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct SessionReviewSnapshot: Sendable {
    let items: [SessionReviewItem]
    let wasTruncated: Bool
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

enum SessionReviewLoadError: LocalizedError, Sendable {
    case noSessionFolders
    case inventoryFailed

    var errorDescription: String? {
        switch self {
        case .noSessionFolders: "No supported Codex or Hermes session folders were found."
        case .inventoryFailed: "Ryddi could not build a trustworthy session inventory. Nothing was changed."
        }
    }
}

struct SessionRoot: Sendable {
    let path: String
    let source: SessionSource
}

enum SessionReviewPaths {
    static let recentProtectionInterval: TimeInterval = 15 * 60

    static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SessionRoot] {
        [
            SessionRoot(path: home.appendingPathComponent(".codex/sessions").path, source: .codex),
            SessionRoot(path: home.appendingPathComponent(".codex/archived_sessions").path, source: .codexArchive),
            SessionRoot(path: home.appendingPathComponent(".hermes/sessions").path, source: .hermes),
        ]
    }

    static func existingRoots() -> [SessionRoot] {
        roots().filter {
            guard let identity = FileIdentity.capture(path: $0.path) else { return false }
            return identity.isDirectory && !identity.isSymbolicLink
        }
    }

    static func mutableRoots() -> [SessionRoot] {
        existingRoots().filter { $0.source != .hermes }
    }

    static func archiveDirectory(for source: SessionSource) -> URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/Session Archives")
        return support.appendingPathComponent(source.rawValue)
    }

    static func containsReviewedRoot(_ candidate: String) -> Bool {
        roots().contains { normalizedSessionPath($0.path) == normalizedSessionPath(candidate) }
    }
}

struct SessionReviewLoader: Sendable {
    private let maximumFiles = 5_000

    func load() throws -> SessionReviewSnapshot {
        let roots = SessionReviewPaths.existingRoots()
        guard !roots.isEmpty else { throw SessionReviewLoadError.noSessionFolders }
        let titles = loadCodexTitles()
        let openPaths = loadOpenPaths(inside: roots.map(\.path))
        var records: [(path: String, source: SessionSource, fingerprint: SessionFileFingerprint, modifiedAt: Date)] = []
        var truncated = false

        for root in roots {
            let rootURL = URL(fileURLWithPath: root.path)
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if records.count >= maximumFiles {
                    truncated = true
                    break
                }
                let ext = url.pathExtension.lowercased()
                guard ext == "jsonl" || ext == "json",
                      let fingerprint = SessionFileFingerprint.capture(path: url.path) else { continue }
                let modifiedAt = Date(
                    timeIntervalSince1970: TimeInterval(fingerprint.modifiedSeconds)
                        + TimeInterval(fingerprint.modifiedNanoseconds) / 1_000_000_000
                )
                records.append((fingerprint.identity.canonicalPath, root.source, fingerprint, modifiedAt))
            }
            if truncated { break }
        }

        guard !records.isEmpty else { throw SessionReviewLoadError.inventoryFailed }
        let now = Date()
        let items = records.map { record in
            let title = titles[record.path]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let recentlyModified = now.timeIntervalSince(record.modifiedAt) < SessionReviewPaths.recentProtectionInterval
            return SessionReviewItem(
                path: record.path,
                title: title?.isEmpty == false ? title! : "\(record.source.rawValue) session",
                source: record.source,
                modifiedAt: record.modifiedAt,
                fingerprint: record.fingerprint,
                useStatus: openPaths.map { $0.contains(record.path) || recentlyModified ? .inUse : .available } ?? .unknown
            )
        }.sorted { lhs, rhs in
            if lhs.sizeBytes == rhs.sizeBytes { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.sizeBytes > rhs.sizeBytes
        }
        return SessionReviewSnapshot(items: items, wasTruncated: truncated)
    }

    private func loadCodexTitles() -> [String: String] {
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path),
              let data = runForData(
                executable: "/usr/bin/sqlite3",
                arguments: ["-readonly", "-json", database.path, "SELECT rollout_path, title FROM threads"],
                timeout: 5,
                acceptedStatuses: [0]
              ),
              let rows = try? JSONDecoder().decode([ThreadIndexRow].self, from: data) else { return [:] }
        return rows.reduce(into: [:]) { titles, row in
            titles[normalizedSessionPath(row.rolloutPath)] = row.title
        }
    }

    private func loadOpenPaths(inside roots: [String]) -> Set<String>? {
        var openPaths: Set<String> = []
        for root in roots {
            guard let data = runForData(
                executable: "/usr/sbin/lsof",
                arguments: ["-Fn", "+D", root],
                timeout: 5,
                acceptedStatuses: [0, 1]
            ), let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.split(separator: "\n") where line.first == "n" {
                let path = normalizedSessionPath(String(line.dropFirst()))
                if path.hasPrefix(normalizedSessionPath(root) + "/") {
                    openPaths.insert(path)
                }
            }
        }
        return openPaths
    }

    private func runForData(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        acceptedStatuses: Set<Int32>
    ) -> Data? {
        var template = Array((NSTemporaryDirectory() + "ryddi-session-review.XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { return nil }
        let outputPath = String(
            decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? output.close()
            unlink(outputPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                return nil
            }
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return nil
        }
        guard acceptedStatuses.contains(process.terminationStatus),
              (try? output.synchronize()) != nil else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size <= 10_485_760,
              lseek(descriptor, 0, SEEK_SET) == 0 else { return nil }
        return try? output.readToEnd() ?? Data()
    }
}

private struct ThreadIndexRow: Decodable {
    let rolloutPath: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case rolloutPath = "rollout_path"
        case title
    }
}

enum SessionReviewFilter: String, CaseIterable {
    case largest = "Largest"
    case older = "Older than 30 days"
    case all = "All"
}

private enum SessionActionKind {
    case archive
    case trash
}

private struct PendingSessionAction: Identifiable {
    let kind: SessionActionKind
    let item: SessionReviewItem
    var id: String { "\(item.id)-\(kind == .archive ? "archive" : "trash")" }

    var title: String {
        switch kind {
        case .archive: "Archive this session?"
        case .trash: "Move this session to Trash?"
        }
    }

    var message: String {
        switch kind {
        case .archive:
            "Ryddi will create and verify a private gzip archive, then move the original transcript to Finder Trash. The task will no longer be available normally in Codex."
        case .trash:
            "The transcript will move to Finder Trash without an archive. Its task history may disappear from Codex, but it remains recoverable until Trash is emptied."
        }
    }
}

struct SessionReviewView: View {
    @ObservedObject var engine: ScanEngine
    @Environment(\.dismiss) private var dismiss
    @State private var filter: SessionReviewFilter = .largest
    @State private var searchText = ""
    @State private var pendingAction: PendingSessionAction?

    private var visibleItems: [SessionReviewItem] {
        if !searchText.isEmpty {
            return engine.sessionReviewItems.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.fileName.localizedCaseInsensitiveContains(searchText)
                    || $0.source.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        let base: [SessionReviewItem]
        switch filter {
        case .largest: base = Array(engine.sessionReviewItems.prefix(25))
        case .older:
            let cutoff = Date().addingTimeInterval(-30 * 86_400)
            base = engine.sessionReviewItems.filter { $0.modifiedAt < cutoff }
        case .all: base = engine.sessionReviewItems
        }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Session Review")
                        .font(.title2.bold())
                    Text("Conversation history—not cache. Nothing is selected, and every action is rechecked.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            if !engine.sessionReviewItems.isEmpty {
                HStack(spacing: 12) {
                    SessionSummaryCard(
                        title: "Session history",
                        value: ByteCountFormatter().string(fromByteCount: engine.sessionReviewTotalBytes),
                        icon: "externaldrive.fill"
                    )
                    SessionSummaryCard(
                        title: "Files",
                        value: "\(engine.sessionReviewItems.count)",
                        icon: "doc.text.fill"
                    )
                    SessionSummaryCard(
                        title: "Currently in use",
                        value: "\(engine.sessionReviewItems.filter { $0.useStatus == .inUse }.count)",
                        icon: "lock.fill"
                    )
                    if engine.sessionReviewItems.contains(where: { $0.useStatus == .unknown }) {
                        SessionSummaryCard(
                            title: "Use check unavailable",
                            value: "\(engine.sessionReviewItems.filter { $0.useStatus == .unknown }.count)",
                            icon: "questionmark.circle.fill"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            HStack(spacing: 12) {
                Picker("Show", selection: $filter) {
                    ForEach(SessionReviewFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)
                TextField("Search titles", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button {
                    engine.loadSessionReview()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(engine.isLoadingSessions || engine.isMaintainingSessions)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if let message = engine.sessionReviewMessage {
                Label(message, systemImage: engine.sessionReviewMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(engine.sessionReviewMessageIsError ? .orange : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        (engine.sessionReviewMessageIsError ? Color.orange : Color.green).opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            if engine.isLoadingSessions {
                Spacer()
                ProgressView("Building local session inventory…")
                    .controlSize(.large)
                Spacer()
            } else if engine.sessionReviewItems.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Sessions Available", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text("Refresh after running a scan, or check Ryddi's warning above.")
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            SessionReviewRow(
                                item: item,
                                isBusy: engine.isMaintainingSessions,
                                allowsMutation: item.source != .hermes,
                                reveal: { engine.revealSession(item) },
                                archive: { pendingAction = PendingSessionAction(kind: .archive, item: item) },
                                trash: { pendingAction = PendingSessionAction(kind: .trash, item: item) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .overlay(alignment: .bottom) {
                    if engine.isMaintainingSessions {
                        ProgressView("Verifying session action…")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                }

                HStack {
                    if engine.sessionReviewWasTruncated {
                        Label("Inventory stopped at the 5,000-file safety bound.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Showing \(visibleItems.count) of \(engine.sessionReviewItems.count) files")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Archives stay local in Ryddi Application Support")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 620, idealHeight: 700)
        .alert(pendingAction?.title ?? "", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingAction = nil }
            if let action = pendingAction {
                switch action.kind {
                case .archive:
                    Button("Archive & Move Original to Trash", role: .destructive) {
                        engine.archiveSession(action.item)
                        pendingAction = nil
                    }
                case .trash:
                    Button("Move to Trash", role: .destructive) {
                        engine.trashSession(action.item)
                        pendingAction = nil
                    }
                }
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
    }
}

private struct SessionSummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SessionReviewRow: View {
    let item: SessionReviewItem
    let isBusy: Bool
    let allowsMutation: Bool
    let reveal: () -> Void
    let archive: () -> Void
    let trash: () -> Void

    private var canAct: Bool { allowsMutation && item.useStatus == .available && !isBusy }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.source.icon)
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
                .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    SessionStatusBadge(status: item.useStatus)
                }
                Text("\(item.source.rawValue) • \(item.modifiedAt.formatted(date: .abbreviated, time: .shortened)) • \(item.fileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !allowsMutation {
                    Text("Reveal only — use Hermes session maintenance to prune this file.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(ByteCountFormatter().string(fromByteCount: item.sizeBytes))
                .font(.body.monospacedDigit())
                .frame(minWidth: 78, alignment: .trailing)
            Button(action: reveal) {
                Image(systemName: "finder")
            }
            .buttonStyle(.borderless)
            .help("Show transcript in Finder")
            Button("Archive…", action: archive)
                .controlSize(.small)
                .disabled(!canAct)
            Button("Trash…", role: .destructive, action: trash)
                .controlSize(.small)
                .disabled(!canAct)
        }
        .padding(12)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SessionStatusBadge: View {
    let status: SessionUseStatus

    var body: some View {
        switch status {
        case .available:
            EmptyView()
        case .inUse:
            Label("In use", systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .unknown:
            Label("Use check unavailable", systemImage: "questionmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}

private enum SessionActionResult: Sendable {
    case success(String)
    case failure(String)
}

extension ScanEngine {
    var sessionReviewTotalBytes: Int64 {
        sessionReviewItems.reduce(0) { $0 + $1.sizeBytes }
    }

    func canReviewSessions(_ items: [ScanItem]) -> Bool {
        items.contains { SessionReviewPaths.containsReviewedRoot($0.path) }
    }

    func openSessionReview() {
        showSessionReview = true
        loadSessionReview()
    }

    func loadSessionReview(preservingMessage: Bool = false) {
        guard !isLoadingSessions, !isMaintainingSessions else { return }
        isLoadingSessions = true
        if !preservingMessage {
            sessionReviewMessage = nil
            sessionReviewMessageIsError = false
        }
        let generation = UUID()
        sessionReviewGeneration = generation
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SessionReviewSnapshot, Error> in
                do { return .success(try SessionReviewLoader().load()) }
                catch { return .failure(error) }
            }.value
            guard sessionReviewGeneration == generation else { return }
            isLoadingSessions = false
            switch result {
            case .success(let snapshot):
                sessionReviewItems = snapshot.items
                sessionReviewWasTruncated = snapshot.wasTruncated
            case .failure(let error):
                sessionReviewItems = []
                sessionReviewWasTruncated = false
                sessionReviewMessage = error.localizedDescription
                sessionReviewMessageIsError = true
            }
        }
    }

    func revealSession(_ item: SessionReviewItem) {
        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
    }

    func trashSession(_ item: SessionReviewItem) {
        performSessionAction { Self.performSessionTrash(item) }
    }

    func archiveSession(_ item: SessionReviewItem) {
        performSessionAction { Self.performSessionArchive(item) }
    }

    private func performSessionAction(
        _ action: @escaping @Sendable () -> SessionActionResult
    ) {
        guard !isMaintainingSessions, !isLoadingSessions else { return }
        isMaintainingSessions = true
        sessionReviewMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated, operation: action).value
            isMaintainingSessions = false
            switch result {
            case .success(let message):
                sessionReviewMessage = message
                sessionReviewMessageIsError = false
            case .failure(let message):
                sessionReviewMessage = message
                sessionReviewMessageIsError = true
            }
            loadSessionReview(preservingMessage: true)
            scanAll(preservingError: true)
        }
    }

    nonisolated private static func performSessionTrash(_ item: SessionReviewItem) -> SessionActionResult {
        do {
            guard item.source != .hermes else {
                return .failure("Hermes sessions are reveal-only. Use Hermes session maintenance to prune them safely.")
            }
            guard Date().timeIntervalSince(item.modifiedAt) >= SessionReviewPaths.recentProtectionInterval else {
                return .failure("This session was modified recently and is protected as active. Try again later.")
            }
            guard item.fingerprint.matchesCurrent(path: item.path) else {
                return .failure("The session changed after review. Refresh before acting.")
            }
            let roots = SessionReviewPaths.mutableRoots().map(\.path)
            let url = try CleanupValidator().validateSessionFile(
                path: item.path,
                allowedRoots: roots,
                scannedIdentity: item.fingerprint.identity
            )
            guard item.fingerprint.matchesCurrent(path: item.path) else {
                return .failure("The session changed during validation. Nothing was moved.")
            }
            try SessionTrashMover().moveValidatedFileToTrash(
                source: url,
                scannedIdentity: item.fingerprint.identity
            )
            return .success("Moved \(item.title) to Finder Trash. It remains recoverable until Trash is emptied.")
        } catch {
            return .failure("Session was kept: \(error.localizedDescription)")
        }
    }

    nonisolated private static func performSessionArchive(_ item: SessionReviewItem) -> SessionActionResult {
        do {
            guard item.source != .hermes else {
                return .failure("Hermes sessions are reveal-only. Use Hermes session maintenance to prune them safely.")
            }
            guard Date().timeIntervalSince(item.modifiedAt) >= SessionReviewPaths.recentProtectionInterval else {
                return .failure("This session was modified recently and is protected as active. Try again later.")
            }
            guard item.fingerprint.matchesCurrent(path: item.path) else {
                return .failure("The session changed after review. Refresh before acting.")
            }
            let roots = SessionReviewPaths.mutableRoots().map(\.path)
            let source = try CleanupValidator().validateSessionFile(
                path: item.path,
                allowedRoots: roots,
                scannedIdentity: item.fingerprint.identity
            )
            let archive = try SessionArchiveWriter().writeVerifiedArchive(
                source: source,
                destinationDirectory: SessionReviewPaths.archiveDirectory(for: item.source)
            )
            do {
                guard item.fingerprint.matchesCurrent(path: item.path) else {
                    return .success("Archive verified at \(archive.path). The original changed and was kept.")
                }
                let revalidated = try CleanupValidator().validateSessionFile(
                    path: item.path,
                    allowedRoots: roots,
                    scannedIdentity: item.fingerprint.identity
                )
                try SessionTrashMover().moveValidatedFileToTrash(
                    source: revalidated,
                    scannedIdentity: item.fingerprint.identity
                )
                return .success("Archive verified at \(archive.path). The original moved to Finder Trash.")
            } catch {
                return .success("Archive verified at \(archive.path). The original was kept: \(error.localizedDescription)")
            }
        } catch {
            return .failure("Session was kept: \(error.localizedDescription)")
        }
    }
}
