import Foundation

public enum SafeActionKind: String, Codable, Hashable, Sendable {
    case homebrewCleanup
    case auditPrune
    case trashAppBundle
    case packageCacheGuidance
    case openFinderReview
}

public enum SafeActionExecutionMode: String, Codable, Hashable, Sendable {
    case dryRun
    case perform
}

public struct SafeActionCandidate: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: SafeActionKind
    public let title: String
    public let detail: String
    public let estimatedBytes: Int64?
    public let requiredConditions: [PlanConditionKind]
    public let commandPreview: [String]
    public let destructive: Bool
    public let reviewRequired: Bool

    public init(
        id: String,
        kind: SafeActionKind,
        title: String,
        detail: String,
        estimatedBytes: Int64?,
        requiredConditions: [PlanConditionKind],
        commandPreview: [String],
        destructive: Bool,
        reviewRequired: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.estimatedBytes = estimatedBytes
        self.requiredConditions = requiredConditions
        self.commandPreview = commandPreview
        self.destructive = destructive
        self.reviewRequired = reviewRequired
    }
}

public struct NativeActionCommand: Codable, Hashable, Sendable {
    public let kind: SafeActionKind
    public let executable: String
    public let arguments: [String]

    public init(kind: SafeActionKind, executable: String, arguments: [String]) {
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
    }
}

public enum NativeActionAllowlistResult: Codable, Hashable, Sendable {
    case allowed
    case blocked(String)

    public var blockedReason: String? {
        switch self {
        case .allowed:
            return nil
        case .blocked(let reason):
            return reason
        }
    }
}

public enum NativeActionAllowlist {
    public static func validate(_ command: NativeActionCommand) -> NativeActionAllowlistResult {
        if containsShellMetacharacter(command.executable) || command.arguments.contains(where: containsShellMetacharacter) {
            return .blocked("shell metacharacters are not allowed")
        }

        if isShellExecutable(command.executable) {
            return .blocked("shell execution is not allowed")
        }

        switch command.kind {
        case .homebrewCleanup:
            guard isBrewExecutable(command.executable) else {
                return .blocked("unexpected executable for homebrewCleanup")
            }
            guard command.arguments == ["cleanup"]
                || command.arguments == ["cleanup", "--dry-run"]
                || command.arguments == ["cleanup", "-n"] else {
                return .blocked("unexpected arguments for homebrewCleanup")
            }
            return .allowed

        case .auditPrune, .trashAppBundle, .packageCacheGuidance, .openFinderReview:
            return .blocked("native command execution is not implemented for \(command.kind.rawValue)")
        }
    }

    private static func isBrewExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return executable == "brew" || last == "brew"
    }

    private static func isShellExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return ["sh", "bash", "zsh", "fish"].contains(last)
    }

    private static func containsShellMetacharacter(_ value: String) -> Bool {
        value.contains("&&")
            || value.contains(";")
            || value.contains("\n")
            || value.contains("`")
            || value.contains("$(")
    }
}
