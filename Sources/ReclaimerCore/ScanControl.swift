import Foundation

public final class ScanCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let externalCancellationCheck: (@Sendable () -> Bool)?
    private let allowsCancellation: Bool

    public init() {
        externalCancellationCheck = nil
        allowsCancellation = true
    }

    fileprivate init(allowsCancellation: Bool) {
        externalCancellationCheck = nil
        self.allowsCancellation = allowsCancellation
    }

    init(isCancelled: @escaping @Sendable () -> Bool) {
        externalCancellationCheck = isCancelled
        allowsCancellation = true
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled } || externalCancellationCheck?() == true
    }

    public func cancel() {
        guard allowsCancellation else { return }
        lock.withLock { cancelled = true }
    }
}

public struct ScanProgress: Hashable, Sendable {
    public enum Phase: String, Hashable, Sendable {
        case preparing
        case measuring
        case classifying
        case finished
    }

    public let phase: Phase
    public let scopeName: String?
    public let measuredItemCount: Int
    public let requestedItemBudget: Int

    public init(
        phase: Phase,
        scopeName: String?,
        measuredItemCount: Int,
        requestedItemBudget: Int
    ) {
        self.phase = phase
        self.scopeName = scopeName
        self.measuredItemCount = measuredItemCount
        self.requestedItemBudget = requestedItemBudget
    }
}

public struct ScanControl: Sendable {
    public let cancellation: ScanCancellationToken
    public let progress: (@Sendable (ScanProgress) -> Void)?

    public init(
        cancellation: ScanCancellationToken,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) {
        self.cancellation = cancellation
        self.progress = progress
    }

    init(isCancelled: @escaping @Sendable () -> Bool) {
        self.init(cancellation: ScanCancellationToken(isCancelled: isCancelled))
    }

    public static let none = ScanControl(cancellation: ScanCancellationToken(allowsCancellation: false))
}
