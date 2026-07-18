import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testReclaimerCoreDoesNotImportProtectOrProviderFrameworks() throws {
        let source = try combinedSwiftSource(in: repositoryRoot.appendingPathComponent("Sources/ReclaimerCore"))
        for forbiddenImport in [
            "import RyddiProtectCore",
            "import SwiftyDropbox",
            "import GoogleSignIn",
            "import GoogleAPIClientForREST_Drive",
            "import MEGASdk",
            "import AuthenticationServices",
            "import Security"
        ] {
            XCTAssertFalse(source.contains(forbiddenImport), "ReclaimerCore must not contain \(forbiddenImport)")
        }
        for forbiddenProviderName in ["Dropbox", "Google Drive", "MEGA", "1Password"] {
            XCTAssertFalse(
                source.contains(forbiddenProviderName),
                "ReclaimerCore must not know about \(forbiddenProviderName)"
            )
        }
        for forbiddenParallelCapability in [
            "ExternalProtectionAuthorizationStore",
            "ExternalProtectionReleaseRequest"
        ] {
            XCTAssertFalse(
                source.contains(forbiddenParallelCapability),
                "Protect must reuse the existing Trash authorization instead of adding \(forbiddenParallelCapability)."
            )
        }
    }

    func testReadOnlyCloudAdapterHasNoMutationCapability() throws {
        let sourceURL = repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/CloudContracts.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "public protocol CloudProviderAdapter"))
        let tail = source[start.lowerBound...]
        let end = try XCTUnwrap(tail.firstIndex(of: "}"))
        let protocolSource = String(tail[..<end])

        for forbiddenVerb in ["upload(", "delete(", "move(", "rename(", "share(", "overwrite(", "prune("] {
            XCTAssertFalse(protocolSource.contains(forbiddenVerb), "Read-only adapter exposed \(forbiddenVerb)")
        }
    }

    func testProtectCoreDoesNotImportUIOrCredentialRuntime() throws {
        let source = try combinedSwiftSource(in: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore"))
        for forbiddenImport in [
            "import ReclaimerCore",
            "import SwiftUI",
            "import AppKit",
            "import AuthenticationServices",
            "import Security",
            "import SwiftyDropbox",
            "import GoogleSignIn",
            "import MEGASdk",
            "import MacDiskReclaimerApp",
            "import reclaimer"
        ] {
            XCTAssertFalse(source.contains(forbiddenImport), "RyddiProtectCore must not contain \(forbiddenImport)")
        }
    }

    func testRuntimeSensitiveModelsDoNotGainPersistenceConformance() throws {
        let cloudSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/CloudContracts.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "CloudObjectReference", in: cloudSource).contains("Codable"))
        XCTAssertFalse(try declaration(named: "CloudConnectionReference", in: cloudSource).contains("Codable"))

        let inventorySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/CloudInventoryBuilder.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "CloudInventoryReport", in: inventorySource).contains("Codable"))

        let assessmentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/ProtectionAssessment.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "ProtectionSubject", in: assessmentSource).contains("Codable"))
        XCTAssertFalse(try declaration(named: "ProtectionAssessment", in: assessmentSource).contains("Codable"))
        XCTAssertFalse(assessmentSource.contains("cleanupEligible"))
        XCTAssertFalse(assessmentSource.contains("safeToDelete"))

        let proposalSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/ProtectionRuleProposal.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "ProtectionRuleProposal", in: proposalSource).contains("Codable"))

        let secretInventorySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/SecretSourceInventory.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "SecretSourceInventoryEntry", in: secretInventorySource).contains("Codable"))

        let authSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectAuth/ProviderCredentialStore.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(try declaration(named: "ProviderCredential", in: authSource).contains("Codable"))
    }

    func testAuthRuntimeIsIsolatedFromCoreAppAndCLI() throws {
        let source = try combinedSwiftSource(in: repositoryRoot.appendingPathComponent("Sources/RyddiProtectAuth"))
        for forbiddenImport in [
            "import ReclaimerCore",
            "import MacDiskReclaimerApp",
            "import reclaimer",
            "import SwiftUI",
            "import AppKit"
        ] {
            XCTAssertFalse(source.contains(forbiddenImport), "RyddiProtectAuth must not contain \(forbiddenImport)")
        }
        XCTAssertFalse(source.contains("kSecAttrSynchronizable"))
        XCTAssertFalse(source.contains("client_secret"))
    }

    func testProtectionProposalCannotMutateOrWeakenPathPolicy() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiProtectCore/ProtectionRuleProposal.swift"),
            encoding: .utf8
        )

        for forbiddenCapability in [
            "UserPathPolicyStore",
            ".exclude",
            "save(",
            "remove(",
            "importDocument(",
            "replace"
        ] {
            XCTAssertFalse(
                source.contains(forbiddenCapability),
                "Protection proposals must not expose policy capability: \(forbiddenCapability)"
            )
        }
    }

    func testPackageLinksOnlyReadOnlyProtectCoreIntoApp() throws {
        let packageSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        try assertTarget(
            "reclaimer",
            hasExactDependencies: ["ReclaimerCore"],
            in: packageSource
        )
        let appPattern = #"name:\s*\"MacDiskReclaimerApp\"\s*,\s*dependencies:\s*\[\s*\"ReclaimerCore\"\s*,\s*\"RyddiProtectCore\"\s*,\s*\.product\(name:\s*\"Sparkle\",\s*package:\s*\"Sparkle\"\)\s*\]"#
        let appExpression = try NSRegularExpression(pattern: appPattern)
        XCTAssertNotNil(
            appExpression.firstMatch(
                in: packageSource,
                range: NSRange(packageSource.startIndex..., in: packageSource)
            ),
            "MacDiskReclaimerApp may link the read-only Protect core, but not the credential runtime."
        )
        XCTAssertFalse(packageSource.contains("MacDiskReclaimerApp\",\n            dependencies: [\n                \"ReclaimerCore\",\n                \"RyddiProtectAuth"))
        try assertTarget(
            "RyddiProtectCore",
            hasExactDependencies: [],
            in: packageSource
        )
        try assertTarget(
            "RyddiProtectAuth",
            hasExactDependencies: ["RyddiProtectCore"],
            in: packageSource
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func combinedSwiftSource(in directory: URL) throws -> String {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ))
        var source = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            source += try String(contentsOf: url, encoding: .utf8)
        }
        return source
    }

    private func declaration(named typeName: String, in source: String) throws -> String {
        let marker = "struct \(typeName)"
        let start = try XCTUnwrap(source.range(of: marker))
        let tail = source[start.lowerBound...]
        let end = try XCTUnwrap(tail.firstIndex(of: "{"))
        return String(tail[..<end])
    }

    private func assertTarget(
        _ targetName: String,
        hasExactDependencies dependencies: [String],
        in packageSource: String
    ) throws {
        let escapedDependencies = dependencies
            .map { "\\\"\(NSRegularExpression.escapedPattern(for: $0))\\\"" }
            .joined(separator: "\\s*,\\s*")
        let pattern = "name:\\s*\\\"\(NSRegularExpression.escapedPattern(for: targetName))\\\"\\s*,\\s*dependencies:\\s*\\[\\s*\(escapedDependencies)\\s*\\]"
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(packageSource.startIndex..., in: packageSource)
        XCTAssertNotNil(
            expression.firstMatch(in: packageSource, range: range),
            "Target \(targetName) must depend only on \(dependencies)."
        )
    }
}
