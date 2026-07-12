import Foundation

public enum ReleaseTrustState: String, Codable, CaseIterable, Hashable, Sendable {
    case localDebug
    case signedOnly
    case notarizationSubmitted
    case notarizationAccepted
    case stapledAndAccepted
    case invalid
    case missingManifest

    public var label: String {
        switch self {
        case .localDebug: "Local debug"
        case .signedOnly: "Signed only"
        case .notarizationSubmitted: "Notarization pending"
        case .notarizationAccepted: "Accepted, not stapled"
        case .stapledAndAccepted: "Release ready"
        case .invalid: "Invalid proof"
        case .missingManifest: "Missing manifest"
        }
    }
}

public struct ReleaseTrustEvidence: Codable, Hashable, Sendable {
    public let state: ReleaseTrustState
    public let version: String?
    public let buildNumber: String?
    public let artifactName: String?
    public let artifactSHA256: String?
    public let sourceCommit: String?
    public let codesignVerified: Bool
    public let hardenedRuntime: Bool
    public let notarizationStatus: String?
    public let stapleValidated: Bool
    public let gatekeeperAccepted: Bool
    public let manifestPath: String?
    public let warnings: [String]

    public init(
        state: ReleaseTrustState,
        version: String? = nil,
        buildNumber: String? = nil,
        artifactName: String? = nil,
        artifactSHA256: String? = nil,
        sourceCommit: String? = nil,
        codesignVerified: Bool = false,
        hardenedRuntime: Bool = false,
        notarizationStatus: String? = nil,
        stapleValidated: Bool = false,
        gatekeeperAccepted: Bool = false,
        manifestPath: String? = nil,
        warnings: [String] = []
    ) {
        self.state = state
        self.version = version
        self.buildNumber = buildNumber
        self.artifactName = artifactName
        self.artifactSHA256 = artifactSHA256
        self.sourceCommit = sourceCommit
        self.codesignVerified = codesignVerified
        self.hardenedRuntime = hardenedRuntime
        self.notarizationStatus = notarizationStatus
        self.stapleValidated = stapleValidated
        self.gatekeeperAccepted = gatekeeperAccepted
        self.manifestPath = manifestPath
        self.warnings = warnings
    }

    public var summary: String {
        switch state {
        case .stapledAndAccepted:
            "Signed, notarized, stapled, and Gatekeeper accepted."
        case .notarizationAccepted:
            "Apple notarization was accepted, but stapling or Gatekeeper proof is incomplete."
        case .notarizationSubmitted:
            "Notarization has been submitted but has not reached accepted release proof."
        case .signedOnly:
            "Developer ID signing is present, but notarization, stapling, or Gatekeeper proof is missing."
        case .localDebug:
            "Unsigned or local debug artifact; verify distributed releases with a manifest."
        case .missingManifest:
            "No release manifest was found."
        case .invalid:
            "Release trust evidence is inconsistent or invalid."
        }
    }

    public static func missingManifest(path: String?) -> ReleaseTrustEvidence {
        ReleaseTrustEvidence(
            state: .missingManifest,
            manifestPath: path,
            warnings: ["No release manifest was found. Build trust cannot be inferred from prose or app runtime strings."]
        )
    }
}

public enum ReleaseTrustEvidenceParser {
    public static func parseRuntimeManifest(text: String, path: String?) -> ReleaseTrustEvidence? {
        let fields = parseFields(text)
        guard fields["manifest_schema"] == "ryddi.release-trust.v1" else {
            return nil
        }
        return parseManifest(text: text, path: path)
    }

    public static func parseManifest(text: String, path: String?) -> ReleaseTrustEvidence {
        let fields = parseFields(text)
        guard !fields.isEmpty else {
            return .missingManifest(path: path)
        }

        let codesignVerified = parseBool(fields["codesign_verified"])
        let hardenedRuntime = parseBool(fields["hardened_runtime"])
        let notarizationStatus = fields["notarization_status"] ?? normalizedLegacyNotarization(fields["Notarization state"])
        let stapleValidated = parseBool(fields["stapled"])
        let gatekeeperAccepted = parseGatekeeper(fields["gatekeeper"])
        let state = stateFor(
            codesignVerified: codesignVerified,
            hardenedRuntime: hardenedRuntime,
            notarizationStatus: notarizationStatus,
            stapleValidated: stapleValidated,
            gatekeeperAccepted: gatekeeperAccepted
        )

        return ReleaseTrustEvidence(
            state: state,
            version: fields["version"] ?? fields["Bundle version"],
            buildNumber: fields["build"] ?? fields["Bundle build"],
            artifactName: fields["artifact"] ?? fields["Artifact"].map { URL(fileURLWithPath: $0).lastPathComponent },
            artifactSHA256: fields["sha256"] ?? fields["Checksum"].flatMap(firstSHA256),
            sourceCommit: fields["source_commit"] ?? fields["Commit"],
            codesignVerified: codesignVerified,
            hardenedRuntime: hardenedRuntime,
            notarizationStatus: notarizationStatus,
            stapleValidated: stapleValidated,
            gatekeeperAccepted: gatekeeperAccepted,
            manifestPath: path,
            warnings: warningsFor(
                state: state,
                codesignVerified: codesignVerified,
                hardenedRuntime: hardenedRuntime,
                notarizationStatus: notarizationStatus,
                stapleValidated: stapleValidated,
                gatekeeperAccepted: gatekeeperAccepted
            )
        )
    }

    private static func parseFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("- ") else { continue }
            if let equals = line.firstIndex(of: "=") {
                let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    fields[key] = value
                }
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, fields[key] == nil {
                    fields[key] = value
                }
            }
        }
        return fields
    }

    private static func parseBool(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "accepted", "valid": true
        default: false
        }
    }

    private static func parseGatekeeper(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "accepted"
    }

    private static func normalizedLegacyNotarization(_ value: String?) -> String? {
        guard let value else { return nil }
        let lowercased = value.lowercased()
        if lowercased.contains("accepted") {
            return "Accepted"
        }
        if lowercased.contains("progress") {
            return "In Progress"
        }
        if lowercased.contains("invalid") {
            return "Invalid"
        }
        return value
    }

    private static func stateFor(
        codesignVerified: Bool,
        hardenedRuntime: Bool,
        notarizationStatus: String?,
        stapleValidated: Bool,
        gatekeeperAccepted: Bool
    ) -> ReleaseTrustState {
        let status = notarizationStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "invalid" || status == "rejected" {
            return .invalid
        }
        if status == "accepted", (!codesignVerified || !hardenedRuntime) {
            return .invalid
        }
        if codesignVerified, hardenedRuntime, status == "accepted", stapleValidated, gatekeeperAccepted {
            return .stapledAndAccepted
        }
        if codesignVerified, hardenedRuntime, status == "accepted" {
            return .notarizationAccepted
        }
        if codesignVerified, hardenedRuntime, isSubmittedStatus(status) {
            return .notarizationSubmitted
        }
        if codesignVerified || hardenedRuntime {
            return .signedOnly
        }
        return .localDebug
    }

    private static func isSubmittedStatus(_ status: String?) -> Bool {
        switch status {
        case "in progress", "submitted", "waiting", "uploaded": true
        default: false
        }
    }

    private static func warningsFor(
        state: ReleaseTrustState,
        codesignVerified: Bool,
        hardenedRuntime: Bool,
        notarizationStatus: String?,
        stapleValidated: Bool,
        gatekeeperAccepted: Bool
    ) -> [String] {
        switch state {
        case .stapledAndAccepted:
            return []
        case .missingManifest:
            return ["No release manifest was found."]
        case .invalid:
            return ["Release trust evidence is inconsistent or invalid; do not publish this artifact as trusted."]
        case .localDebug:
            return ["This is not a signed/notarized release proof."]
        case .signedOnly, .notarizationSubmitted, .notarizationAccepted:
            var warnings: [String] = []
            if !codesignVerified {
                warnings.append("codesign verification is missing.")
            }
            if !hardenedRuntime {
                warnings.append("Hardened Runtime proof is missing.")
            }
            if notarizationStatus != "Accepted" {
                warnings.append("Apple notarization is not accepted.")
            }
            if !stapleValidated {
                warnings.append("Stapling validation is missing.")
            }
            if !gatekeeperAccepted {
                warnings.append("Gatekeeper assessment is not accepted.")
            }
            return warnings
        }
    }

    private static func firstSHA256(_ value: String) -> String? {
        value.split(separator: " ").first.map(String.init)
    }
}

public enum ReleaseTrustEvidenceLoader {
    public static func load(path: String = "dist/Ryddi-release-manifest.txt") -> ReleaseTrustEvidence {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .missingManifest(path: url.path)
        }
        return ReleaseTrustEvidenceParser.parseManifest(text: text, path: url.path)
    }
}
