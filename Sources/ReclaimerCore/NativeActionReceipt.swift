import Foundation

public struct NativeActionReceipt: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let kind: SafeActionKind
    public let mode: SafeActionExecutionMode
    public let commandDisplay: [String]
    public let exitCode: Int32?
    public let stdoutPreview: [String]
    public let stderrPreview: [String]
    public let beforeDisk: DiskStatusSnapshot?
    public let afterDisk: DiskStatusSnapshot?
    public let skippedReason: String?
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        kind: SafeActionKind,
        mode: SafeActionExecutionMode,
        commandDisplay: [String],
        exitCode: Int32?,
        stdoutPreview: [String],
        stderrPreview: [String],
        beforeDisk: DiskStatusSnapshot?,
        afterDisk: DiskStatusSnapshot?,
        skippedReason: String?,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.mode = mode
        self.commandDisplay = commandDisplay
        self.exitCode = exitCode
        self.stdoutPreview = stdoutPreview
        self.stderrPreview = stderrPreview
        self.beforeDisk = beforeDisk
        self.afterDisk = afterDisk
        self.skippedReason = skippedReason
        self.nonClaims = nonClaims
    }
}
