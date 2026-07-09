import Foundation

public struct RemotePrivacyRedactor: Sendable {
    public let privacy: ReportPrivacyOptions
    public let target: RemoteTargetReference?
    private let sensitiveValues: [String]

    public init(
        privacy: ReportPrivacyOptions,
        target: RemoteTargetReference? = nil,
        additionalSensitiveValues: [String] = []
    ) {
        self.privacy = privacy
        self.target = target
        var values = additionalSensitiveValues
        if let target {
            values.append(contentsOf: [
                target.input,
                target.alias,
                target.resolvedHost,
                target.resolvedUser
            ].compactMap { $0 })
        }
        self.sensitiveValues = Self.expandedSensitiveValues(values)
    }

    public var redactsUserText: Bool {
        privacy.redactUserText || privacy.pathStyle == .redacted
    }

    public func targetLabel() -> String {
        guard redactsUserText else { return target?.alias ?? target?.input ?? "unknown" }
        return "<target redacted>"
    }

    public func host() -> String {
        guard redactsUserText else { return target?.resolvedHost ?? "unknown" }
        return "<host redacted>"
    }

    public func user() -> String {
        guard redactsUserText else { return target?.resolvedUser ?? "unknown" }
        return "<user redacted>"
    }

    public func path(_ path: String) -> String {
        privacy.displayPath(path)
    }

    public func text(_ text: String, knownPaths: [String] = []) -> String {
        var output = privacy.displayText(text, knownPaths: knownPaths + sensitiveValues)
        guard redactsUserText else { return output }
        for value in sensitiveValues.sorted(by: { $0.count > $1.count }) {
            guard value.count >= 3 else { continue }
            output = output.replacingOccurrences(of: value, with: "<redacted>")
        }
        for token in ["IdentityFile", "BEGIN OPENSSH", "OPENSSH PRIVATE KEY"] {
            output = output.replacingOccurrences(of: token, with: "<redacted>")
        }
        return output
    }

    public func commandCard(_ card: RemoteManualCommandCard) -> RemoteManualCommandCard {
        RemoteManualCommandCard(
            id: card.id,
            title: text(card.title),
            kind: card.kind,
            displayCommand: text(card.displayCommand),
            risk: card.risk,
            explanation: text(card.explanation),
            prerequisites: card.prerequisites.map { text($0) },
            nonClaims: card.nonClaims
        )
    }

    private static func expandedSensitiveValues(_ values: [String]) -> [String] {
        var expanded = Set<String>()
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 3 else { continue }
            expanded.insert(value)
            if let schemeRange = value.range(of: "://") {
                let suffix = String(value[schemeRange.upperBound...])
                if suffix.count >= 3 {
                    expanded.insert(suffix)
                }
            }
            let slashParts = value.split(separator: "/").map(String.init)
            if let last = slashParts.last, last.count >= 3 {
                expanded.insert(last)
            }
            for part in value.split(whereSeparator: { ".-_".contains($0) }).map(String.init) where part.count >= 4 {
                expanded.insert(part)
            }
        }
        return Array(expanded)
    }
}
