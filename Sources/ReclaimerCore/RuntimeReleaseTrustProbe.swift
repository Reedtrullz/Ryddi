import Foundation

public struct EmbeddedBuildMetadata: Codable, Hashable, Sendable {
    public let version: String
    public let build: String
    public let sourceCommit: String
    public let buildDate: Date

    public init(version: String, build: String, sourceCommit: String, buildDate: Date) {
        self.version = version
        self.build = build
        self.sourceCommit = sourceCommit
        self.buildDate = buildDate
    }
}

public enum RuntimeTrustState: String, Codable, CaseIterable, Hashable, Sendable {
    case unsigned
    case developerIDSigned
    case gatekeeperAccepted
    case gatekeeperRejectedUnnotarized
    case rejected
    case unavailable
    case malformed

    public var label: String {
        switch self {
        case .unsigned: "Unsigned"
        case .developerIDSigned: "Developer ID signed"
        case .gatekeeperAccepted: "Gatekeeper accepted"
        case .gatekeeperRejectedUnnotarized: "Gatekeeper rejected: unnotarized"
        case .rejected: "Rejected"
        case .unavailable, .malformed: "Unable to verify"
        }
    }
}

public struct RuntimeTrustCheck: Codable, Hashable, Sendable {
    public let state: RuntimeTrustState
    public let detail: String

    public init(state: RuntimeTrustState, detail: String) {
        self.state = state
        self.detail = detail
    }

    public var label: String { state.label }
}

public struct RuntimeReleaseTrustReport: Codable, Hashable, Sendable {
    public let build: EmbeddedBuildMetadata?
    public let signature: RuntimeTrustCheck
    public let gatekeeper: RuntimeTrustCheck
    public let externalManifest: ReleaseTrustEvidence?
    public let claims: [String]
    public let nonClaims: [String]

    public init(
        build: EmbeddedBuildMetadata?,
        signature: RuntimeTrustCheck,
        gatekeeper: RuntimeTrustCheck,
        externalManifest: ReleaseTrustEvidence?,
        claims: [String],
        nonClaims: [String]
    ) {
        self.build = build
        self.signature = signature
        self.gatekeeper = gatekeeper
        self.externalManifest = externalManifest
        self.claims = claims
        self.nonClaims = nonClaims
    }

    public var signatureSummary: String { signature.label }

    public var gatekeeperSummary: String { gatekeeper.label }

    public var externalManifestSummary: String {
        externalManifest?.state.label ?? "Not provided"
    }
}

public struct RuntimeReleaseTrustProbe: Sendable {
    public static let manifestEnvironmentKey = "RYDDI_RELEASE_MANIFEST_PATH"

    private let runner: any ToolCommandRunning
    private let timeout: TimeInterval
    private let environment: [String: String]
    private let homeDirectory: URL

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        timeout: TimeInterval = 3,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.runner = runner
        self.timeout = max(0.1, min(timeout, 10))
        self.environment = environment
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func inspect(appURL: URL = Bundle.main.bundleURL) -> RuntimeReleaseTrustReport {
        let standardizedAppURL = appURL.standardizedFileURL
        let metadataResult = loadMetadata(appURL: standardizedAppURL)
        let signature = inspectSignature(appURL: standardizedAppURL)
        let gatekeeper = inspectGatekeeper(appURL: standardizedAppURL)
        let manifestResult = loadExternalManifest(appURL: standardizedAppURL, build: metadataResult.metadata)

        var claims: [String] = []
        if signature.state == .developerIDSigned {
            claims.append(signature.label)
        }
        if gatekeeper.state == .gatekeeperAccepted {
            claims.append(gatekeeper.label)
        }
        if manifestResult.evidence != nil {
            claims.append("External release manifest matches embedded build metadata")
        }

        var nonClaims = [
            "Runtime signature and Gatekeeper probes do not prove notarization or stapling.",
            "Gatekeeper acceptance alone does not prove that a notarization ticket is stapled."
        ]
        nonClaims.append(contentsOf: metadataResult.nonClaims)
        nonClaims.append(contentsOf: manifestResult.nonClaims)

        return RuntimeReleaseTrustReport(
            build: metadataResult.metadata,
            signature: signature,
            gatekeeper: gatekeeper,
            externalManifest: manifestResult.evidence,
            claims: claims,
            nonClaims: nonClaims
        )
    }

    private func loadMetadata(appURL: URL) -> (metadata: EmbeddedBuildMetadata?, nonClaims: [String]) {
        let url = appURL.appendingPathComponent("Contents/Resources/Ryddi-build.json")
        guard let data = try? Data(contentsOf: url) else {
            return (nil, ["Embedded build metadata is missing; version and build cannot be verified."])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(EmbeddedBuildMetadata.self, from: data),
              !metadata.version.isEmpty,
              !metadata.build.isEmpty,
              !metadata.sourceCommit.isEmpty else {
            return (nil, ["Embedded build metadata is malformed; its prose and fields grant no release trust."])
        }
        return (metadata, [])
    }

    private func inspectSignature(appURL: URL) -> RuntimeTrustCheck {
        let verify = run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=4", appURL.path]
        )
        if isUnavailable(verify) {
            return RuntimeTrustCheck(state: .unavailable, detail: unavailableDetail(verify))
        }
        guard verify.succeeded else {
            let text = combinedOutput(verify).lowercased()
            if text.contains("not signed") || text.contains("code object is not signed") {
                return RuntimeTrustCheck(state: .unsigned, detail: "codesign reports that the app is unsigned.")
            }
            if text.contains("invalid") || text.contains("not valid") || text.contains("sealed resource") {
                return RuntimeTrustCheck(state: .rejected, detail: preview(verify))
            }
            return RuntimeTrustCheck(state: .malformed, detail: preview(verify))
        }

        let display = run("/usr/bin/codesign", ["--display", "--verbose=4", appURL.path])
        if isUnavailable(display) {
            return RuntimeTrustCheck(state: .unavailable, detail: unavailableDetail(display))
        }
        guard display.succeeded else {
            return RuntimeTrustCheck(state: .malformed, detail: preview(display))
        }
        let signingInformation = combinedOutput(display)
        guard signingInformation.contains("Authority=Developer ID Application:") else {
            if signingInformation.contains("Authority=") {
                return RuntimeTrustCheck(
                    state: .rejected,
                    detail: "The signature is valid but is not a Developer ID Application signature."
                )
            }
            return RuntimeTrustCheck(state: .malformed, detail: "codesign returned no parseable signing authority.")
        }
        return RuntimeTrustCheck(
            state: .developerIDSigned,
            detail: "Strict codesign verification passed with a Developer ID Application authority."
        )
    }

    private func inspectGatekeeper(appURL: URL) -> RuntimeTrustCheck {
        let assessment = run(
            "/usr/sbin/spctl",
            ["--assess", "--type", "execute", "--verbose=4", appURL.path]
        )
        if isUnavailable(assessment) {
            return RuntimeTrustCheck(state: .unavailable, detail: unavailableDetail(assessment))
        }
        let text = combinedOutput(assessment)
        let lowercased = text.lowercased()
        if assessment.succeeded {
            guard lowercased.contains("accepted") else {
                return RuntimeTrustCheck(state: .malformed, detail: "spctl succeeded without a parseable accepted result.")
            }
            return RuntimeTrustCheck(state: .gatekeeperAccepted, detail: "The local Gatekeeper assessment accepted this app.")
        }
        if lowercased.contains("unnotarized developer id") || lowercased.contains("unnotarized") {
            return RuntimeTrustCheck(
                state: .gatekeeperRejectedUnnotarized,
                detail: "The local Gatekeeper assessment rejected an unnotarized Developer ID app."
            )
        }
        if lowercased.contains("rejected") {
            return RuntimeTrustCheck(state: .rejected, detail: preview(assessment))
        }
        return RuntimeTrustCheck(state: .malformed, detail: preview(assessment))
    }

    private func loadExternalManifest(
        appURL: URL,
        build: EmbeddedBuildMetadata?
    ) -> (evidence: ReleaseTrustEvidence?, nonClaims: [String]) {
        guard let manifestURL = externalManifestURL(appURL: appURL) else {
            return (nil, ["No external release manifest was found."])
        }
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return (nil, ["The selected external release manifest could not be read."])
        }
        guard let evidence = ReleaseTrustEvidenceParser.parseRuntimeManifest(text: text, path: manifestURL.path) else {
            return (nil, ["External prose is not a typed release manifest and grants no release trust."])
        }
        guard let build,
              evidence.version == build.version,
              evidence.buildNumber == build.build else {
            return (nil, ["The external release manifest does not match embedded version/build."])
        }
        return (evidence, [])
    }

    private func externalManifestURL(appURL: URL) -> URL? {
        if let override = environment[Self.manifestEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }

        let adjacent = appURL.deletingLastPathComponent().appendingPathComponent("Ryddi-release-manifest.txt")
        if FileManager.default.isReadableFile(atPath: adjacent.path) {
            return adjacent.standardizedFileURL
        }

        let imported = homeDirectory
            .appendingPathComponent("Library/Application Support/Ryddi/ReleaseTrust/Imported", isDirectory: true)
            .appendingPathComponent("Ryddi-release-manifest.txt")
        if FileManager.default.isReadableFile(atPath: imported.path) {
            return imported.standardizedFileURL
        }
        return nil
    }

    private func run(_ executable: String, _ arguments: [String]) -> ToolCommandOutput {
        runner.run(ToolCommandInvocation(executable: executable, arguments: arguments), timeout: timeout)
    }

    private func isUnavailable(_ output: ToolCommandOutput) -> Bool {
        output.timedOut || output.launchError != nil || output.exitCode == nil
    }

    private func unavailableDetail(_ output: ToolCommandOutput) -> String {
        if output.timedOut {
            return "The local trust probe timed out."
        }
        return output.launchError ?? "The local trust probe is unavailable."
    }

    private func combinedOutput(_ output: ToolCommandOutput) -> String {
        [output.stdout, output.stderr].joined(separator: "\n")
    }

    private func preview(_ output: ToolCommandOutput) -> String {
        let value = combinedOutput(output).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "The local trust tool returned no parseable result." }
        return String(value.prefix(512))
    }
}
