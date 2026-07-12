import Foundation

public struct ScanRequestIdentity: Hashable, Sendable {
    public let id: UUID
    public let preset: ScanScopePreset
    public let scopeDigest: String
    public let ruleVersion: String
    public let policyDigest: String

    public init(
        id: UUID = UUID(),
        preset: ScanScopePreset,
        scopeDigest: String,
        ruleVersion: String,
        policyDigest: String
    ) {
        self.id = id
        self.preset = preset
        self.scopeDigest = scopeDigest
        self.ruleVersion = ruleVersion
        self.policyDigest = policyDigest
    }
}

public struct ScanRequestCoordinator: Sendable {
    public private(set) var activeRequest: ScanRequestIdentity?

    public init(activeRequest: ScanRequestIdentity? = nil) {
        self.activeRequest = activeRequest
    }

    public mutating func begin(_ request: ScanRequestIdentity) {
        activeRequest = request
    }

    public func accepts(_ request: ScanRequestIdentity) -> Bool {
        activeRequest == request
    }

    public mutating func invalidate() {
        activeRequest = nil
    }

    @discardableResult
    public mutating func finish(_ request: ScanRequestIdentity) -> Bool {
        guard accepts(request) else { return false }
        activeRequest = nil
        return true
    }
}
