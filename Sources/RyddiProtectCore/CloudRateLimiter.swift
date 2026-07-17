import Foundation

public enum CloudProviderError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case serverFailure(statusCode: Int)
    case transportFailure
    case malformedResponse
}

public struct CloudRateLimiter: Sendable {
    public static let maximumRetryDelay: TimeInterval = 30

    public let maximumRetryCount: Int
    private let jitter: @Sendable () -> Double

    public init(
        maximumRetryCount: Int = CloudInventoryLimits.maximumRetryCount,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.maximumRetryCount = Swift.min(
            Swift.max(0, maximumRetryCount),
            CloudInventoryLimits.maximumRetryCount
        )
        self.jitter = jitter
    }

    public func delay(for error: CloudProviderError, retryNumber: Int) -> TimeInterval? {
        guard (1...maximumRetryCount).contains(retryNumber) else {
            return nil
        }

        let baseDelay: TimeInterval
        let useJitter: Bool
        switch error {
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter.isFinite, retryAfter >= 0 {
                baseDelay = Swift.min(retryAfter, Self.maximumRetryDelay)
                useJitter = false
            } else {
                baseDelay = exponentialDelay(retryNumber: retryNumber)
                useJitter = true
            }
        case .serverFailure(let statusCode) where (500...599).contains(statusCode):
            baseDelay = exponentialDelay(retryNumber: retryNumber)
            useJitter = true
        case .transportFailure:
            baseDelay = exponentialDelay(retryNumber: retryNumber)
            useJitter = true
        case .unauthorized, .forbidden, .serverFailure, .malformedResponse:
            return nil
        }

        guard useJitter else {
            return baseDelay
        }
        let rawJitter = jitter()
        let boundedJitter = rawJitter.isFinite
            ? Swift.min(Swift.max(rawJitter, 0), 1)
            : 0.5
        let multiplier = 0.75 + (boundedJitter * 0.5)
        return Swift.min(baseDelay * multiplier, Self.maximumRetryDelay)
    }

    private func exponentialDelay(retryNumber: Int) -> TimeInterval {
        Swift.min(0.25 * pow(2, Double(retryNumber - 1)), Self.maximumRetryDelay)
    }
}
