import Foundation

public enum RemoteTargetInputPolicyError: LocalizedError, Equatable {
    case empty
    case tooLong(maximum: Int)
    case startsWithDash
    case containsWhitespaceOrControl

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Invalid remote target: enter an SSH alias, host, or user@host."
        case .tooLong(let maximum):
            "Invalid remote target: target must be \(maximum) characters or fewer."
        case .startsWithDash:
            "Invalid remote target: targets cannot start with '-' because that can be interpreted as an ssh option."
        case .containsWhitespaceOrControl:
            "Invalid remote target: targets cannot contain whitespace or control characters."
        }
    }
}

public enum RemoteTargetInputPolicy {
    public static let maximumLength = 255

    @discardableResult
    public static func validate(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RemoteTargetInputPolicyError.empty
        }
        guard trimmed.count <= maximumLength else {
            throw RemoteTargetInputPolicyError.tooLong(maximum: maximumLength)
        }
        guard !trimmed.hasPrefix("-") else {
            throw RemoteTargetInputPolicyError.startsWithDash
        }
        let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard trimmed.unicodeScalars.allSatisfy({ !invalidCharacters.contains($0) }) else {
            throw RemoteTargetInputPolicyError.containsWhitespaceOrControl
        }
        return trimmed
    }
}
