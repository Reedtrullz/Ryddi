import Foundation

public enum DiagnosticOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case scan
    case presentation
    case plan
    case dryRun
    case trashExecution
    case navigation
}

public enum DiagnosticEvent: String, Codable, CaseIterable, Hashable, Sendable {
    case staleScanRejected
    case permissionCoverageChanged
    case e2eCheckpoint
}

public enum DiagnosticErrorKind: String, Codable, CaseIterable, Hashable, Sendable {
    case scanFailed
    case planAuditFailed
    case dryRunFailed
    case trashExecutionFailed
    case exportFailed
}

public struct DiagnosticDuration: Codable, Hashable, Sendable {
    public let operation: DiagnosticOperation
    public let milliseconds: Int

    public init(operation: DiagnosticOperation, milliseconds: Int) {
        self.operation = operation
        self.milliseconds = max(0, milliseconds)
    }
}

public struct DiagnosticEventCount: Codable, Hashable, Sendable {
    public let event: DiagnosticEvent
    public let count: Int

    public init(event: DiagnosticEvent, count: Int) {
        self.event = event
        self.count = max(0, count)
    }
}

public struct DiagnosticMetadata: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let generatedAt: Date
    public let appVersion: String
    public let preset: ScanScopePreset
    public let stage: ScanSessionStage?
    public let findingCount: Int
    public let readableScopeCount: Int
    public let totalScopeCount: Int
    public let durations: [DiagnosticDuration]
    public let eventCounts: [DiagnosticEventCount]
    public let lastErrorKind: DiagnosticErrorKind?
    public let nonClaims: [String]
}

public enum DiagnosticMetadataBuilder {
    public static func build(
        appVersion: String,
        preset: ScanScopePreset,
        stage: ScanSessionStage?,
        findingCount: Int,
        readableScopeCount: Int,
        totalScopeCount: Int,
        durations: [DiagnosticOperation: Int],
        eventCounts: [DiagnosticEvent: Int],
        lastErrorKind: DiagnosticErrorKind?,
        now: Date = Date(),
        id: String = UUID().uuidString
    ) -> DiagnosticMetadata {
        DiagnosticMetadata(
            schemaVersion: 1,
            id: sanitizedToken(id, fallback: "diagnostic"),
            generatedAt: now,
            appVersion: sanitizedToken(appVersion, fallback: "unknown"),
            preset: preset,
            stage: stage,
            findingCount: max(0, findingCount),
            readableScopeCount: max(0, readableScopeCount),
            totalScopeCount: max(0, totalScopeCount),
            durations: DiagnosticOperation.allCases.compactMap { operation in
                durations[operation].map { DiagnosticDuration(operation: operation, milliseconds: $0) }
            },
            eventCounts: DiagnosticEvent.allCases.compactMap { event in
                eventCounts[event].map { DiagnosticEventCount(event: event, count: $0) }
            },
            lastErrorKind: lastErrorKind,
            nonClaims: [
                "This summary contains typed timing and count metadata only.",
                "It does not include paths, filenames, SSH targets, usernames, rule text, command output, or file contents.",
                "Ryddi does not upload this summary automatically."
            ]
        )
    }

    private static func sanitizedToken(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let token = String(value.unicodeScalars.prefix(64).map { allowed.contains($0) ? Character(String($0)) : "_" })
        return token.isEmpty ? fallback : token
    }
}
