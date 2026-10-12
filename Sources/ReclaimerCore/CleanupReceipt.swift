import Foundation

public enum CleanupOutcome: String, Sendable {
    case moved = "Moved", retained = "Retained", failed = "Failed"
}

public struct CleanupReceiptEntry: Identifiable, Sendable {
    public let id = UUID()
    public let sourcePath: String
    public let outcome: CleanupOutcome
    public let recoveryPath: String?
    public let detail: String

    public init(sourcePath: String, outcome: CleanupOutcome, recoveryPath: String?, detail: String) {
        self.sourcePath = sourcePath
        self.outcome = outcome
        self.recoveryPath = recoveryPath
        self.detail = detail
    }
}

public struct CleanupReceipt: Identifiable, Sendable {
    public let id = UUID()
    public let completedAt: Date
    public let entries: [CleanupReceiptEntry]
    public static let lifetime: TimeInterval = 30 * 60
    public static let spaceStatement = "Physically reclaimed space is unverified. Moving to Trash retains data; it does not prove freed disk space."

    public init(entries: [CleanupReceiptEntry], completedAt: Date = Date()) {
        self.entries = entries
        self.completedAt = completedAt
    }

    public var summary: String {
        "\(entries.filter { $0.outcome == .moved }.count) moved, \(entries.filter { $0.outcome == .retained }.count) retained, \(entries.filter { $0.outcome == .failed }.count) failed"
    }

    public var hasUnmovedItems: Bool { entries.contains { $0.outcome != .moved } }
    public func isExpired(at date: Date = Date()) -> Bool { date >= completedAt.addingTimeInterval(Self.lifetime) }

    public func text(includePaths: Bool = false) -> String {
        var lines = ["Ryddi action receipt", summary, Self.spaceStatement]
        for (index, entry) in entries.enumerated() {
            lines.append("Item \(index + 1): \(entry.outcome.rawValue)")
            if includePaths {
                lines.append("Source: \(entry.sourcePath)")
                lines.append("Recorded recovery location: \(entry.recoveryPath ?? "Unknown")")
                lines.append(entry.detail)
            } else {
                lines.append(entry.recoveryPath == nil ? "Recovery location unverified." : "Recovery location available in the local receipt.")
            }
        }
        lines.append(includePaths ? "Includes private paths and error details." : "Paths, names and error details redacted.")
        return lines.joined(separator: "\n")
    }

    public static func perform(paths: [String], operation: (String) throws -> URL) -> CleanupReceipt {
        var entries: [CleanupReceiptEntry] = []
        var cancelled = false
        for path in paths {
            if cancelled || Task.isCancelled {
                entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .retained, recoveryPath: path,
                    detail: "Not attempted by Ryddi because the action was cancelled. Original path recorded; external changes are unverified."))
                continue
            }
            do {
                let recovery = try operation(path)
                guard recovery.isFileURL else { throw SessionTrashError.locationUnknown }
                entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .moved, recoveryPath: recovery.path,
                    detail: "Moved to Finder Trash. Reveal the recorded location to review or recover it manually."))
            } catch let error as SessionTrashError {
                if case .retained(let recovery) = error {
                    entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .retained, recoveryPath: recovery, detail: error.localizedDescription))
                } else {
                    entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .failed, recoveryPath: nil, detail: error.localizedDescription))
                }
            } catch is CancellationError {
                cancelled = true
                entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .failed, recoveryPath: nil,
                    detail: "The attempted action was cancelled; its recovery location is unverified. Review source and Trash manually."))
            } catch {
                entries.append(CleanupReceiptEntry(sourcePath: path, outcome: .failed, recoveryPath: nil, detail: error.localizedDescription))
            }
        }
        return CleanupReceipt(entries: entries)
    }
}
