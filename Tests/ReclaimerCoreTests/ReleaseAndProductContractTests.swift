import XCTest

final class ReleaseAndProductContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testReleaseScriptFailsClosedAndVerifiesTrust() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build-installer.sh"),
            encoding: .utf8
        )
        for required in [
            "APP_SIGNING_IDENTITY is required",
            "INSTALLER_SIGNING_IDENTITY is required",
            "NOTARY_PROFILE is required",
            "codesign --verify --deep --strict",
            "pkgutil --check-signature",
            "--keychain-profile \"$NOTARY_PROFILE_NAME\"",
            "xcrun stapler validate",
            "spctl --assess --type install",
            "Ryddi_ReclaimerCore.bundle",
            "shasum -a 256 \"$PKG_BASENAME\"",
        ] {
            XCTAssertTrue(script.contains(required), "Missing release gate: \(required)")
        }
        XCTAssertFalse(script.contains("Skipping code signing"))
        XCTAssertFalse(script.contains("Skipping notarization"))

        let archiveScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build-release-archive.sh"),
            encoding: .utf8
        )
        for required in [
            "APP_SIGNING_IDENTITY is required",
            "NOTARY_PROFILE is required",
            "codesign --verify --deep --strict",
            "notarytool submit",
            "stapler validate",
            "spctl --assess --type execute",
            "Ryddi_ReclaimerCore.bundle",
            "status\") == \"Accepted\"",
            "RELEASE_COMPLETE=1",
            "shasum -a 256 \"$RELEASE_BASENAME\"",
        ] {
            XCTAssertTrue(archiveScript.contains(required), "Missing archive release gate: \(required)")
        }
    }

    func testProductDoesNotAutoScanOrPreselect() throws {
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ContentView.swift"),
            encoding: .utf8
        )
        let scanEngine = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ScanEngine.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(contentView.contains(".onAppear { engine.scanAll() }"))
        XCTAssertTrue(scanEngine.contains("selectedIDs = []"))
        XCTAssertTrue(scanEngine.contains("auditSelectedIDs = []"))
        XCTAssertFalse(scanEngine.contains("deleteOriginalAfterCopy"))
        XCTAssertFalse(scanEngine.contains("/bin/bash"))
    }

    func testGroupedCleanUIKeepsStableAndValidState() throws {
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ContentView.swift"),
            encoding: .utf8
        )
        let scanEngine = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ScanEngine.swift"),
            encoding: .utf8
        )
        let models = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/ReclaimerCore/Models.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(contentView.contains("struct BucketSectionView"))
        XCTAssertFalse(contentView.contains("get: { someSelected }"))
        XCTAssertTrue(contentView.contains("let maxSize = max(groups.first?.totalSizeBytes ?? 1, 1)"))
        XCTAssertTrue(contentView.contains("LazyVStack(spacing: 0)"))
        XCTAssertTrue(contentView.contains("minus.square.fill"))
        XCTAssertTrue(scanEngine.contains("@Published private var expandedGroups"))
        XCTAssertTrue(models.contains("public var id: String { baseName }"))
    }

    func testConfirmationAndFirstCustomPathRemainReachable() throws {
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/RyddiApp.swift"),
            encoding: .utf8
        )
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains(".alert(engine.confirmationTitle"))
        XCTAssertTrue(app.contains("engine.pendingAction?()"))
        XCTAssertTrue(contentView.contains("Label(\"Add Path\", systemImage: \"plus.circle\")"))
        XCTAssertFalse(contentView.contains("if !engine.customPaths.isEmpty {\n                    VStack"))
    }

    func testOffloadIsDestinationFirstAndNeverOffersDeletion() throws {
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ContentView.swift"),
            encoding: .utf8
        )
        let scanEngine = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ScanEngine.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentView.contains("1. Choose a destination"))
        XCTAssertTrue(contentView.contains("2. Choose a folder"))
        XCTAssertTrue(contentView.contains("Nothing is moved or deleted"))
        XCTAssertTrue(contentView.contains("struct OffloadProviderCard"))
        XCTAssertTrue(contentView.contains("struct OffloadFolderRow"))
        XCTAssertTrue(contentView.contains("Show Copy"))
        XCTAssertTrue(contentView.contains("Show Original"))
        XCTAssertFalse(contentView.contains("Delete Local Original"))
        XCTAssertFalse(contentView.contains("deleteOriginalAfterCopy"))
        XCTAssertTrue(scanEngine.contains("name.hasPrefix(\"GoogleDrive-\") { return \"Google Drive\" }"))
        XCTAssertTrue(scanEngine.contains("sorted { $0.sizeBytes > $1.sizeBytes }"))
        XCTAssertTrue(scanEngine.contains("allowedSources.contains(identity.canonicalPath)"))
        XCTAssertTrue(scanEngine.contains("lastCopiedProviderName = provider.displayName"))
    }

    func testSessionReviewIsOnDemandBoundedAndFailClosed() throws {
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ContentView.swift"),
            encoding: .utf8
        )
        let scanEngine = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ScanEngine.swift"),
            encoding: .utf8
        )
        let sessionReview = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/SessionReview.swift"),
            encoding: .utf8
        )
        let validator = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/ReclaimerCore/CleanupValidator.swift"),
            encoding: .utf8
        )
        let archiveWriter = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/ReclaimerCore/SessionArchiveWriter.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentView.contains("Button(\"Review Sessions\")"))
        XCTAssertFalse(scanEngine.contains("loadSessionReview()\n                let support"))
        XCTAssertTrue(sessionReview.contains("private let maximumFiles = 5_000"))
        XCTAssertTrue(sessionReview.contains("SELECT rollout_path, title FROM threads"))
        XCTAssertTrue(sessionReview.contains("arguments: [\"-Fn\", \"+D\", root]"))
        XCTAssertTrue(sessionReview.contains("recentProtectionInterval: TimeInterval = 15 * 60"))
        XCTAssertTrue(sessionReview.contains("Archive & Move Original to Trash"))
        XCTAssertTrue(sessionReview.contains("Nothing is selected"))
        XCTAssertTrue(sessionReview.contains("item.source != .hermes"))
        XCTAssertTrue(sessionReview.contains("Hermes sessions are reveal-only"))
        XCTAssertTrue(sessionReview.contains("Use check unavailable"))
        XCTAssertFalse(sessionReview.contains("payload.content"))
        XCTAssertTrue(validator.contains("validateSessionFile"))
        XCTAssertTrue(archiveWriter.contains("O_RDONLY | O_NOFOLLOW"))
        XCTAssertTrue(archiveWriter.contains("openat(destinationDescriptor"))
        XCTAssertTrue(archiveWriter.contains("renameatx_np"))
        XCTAssertTrue(archiveWriter.contains("original.matchesDescriptor(sourceDescriptor)"))
        XCTAssertTrue(archiveWriter.contains("SessionTrashMover"))
    }

    func testSourceVersionMatchesNextRelease() throws {
        let plistURL = repositoryRoot.appendingPathComponent("Assets/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.8.2")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "82")
    }
}
