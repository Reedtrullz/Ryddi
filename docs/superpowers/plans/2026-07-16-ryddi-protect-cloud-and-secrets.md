# Ryddi Protect: Cloud Readiness and 1Password Secrets Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task by task. Use `superpowers:test-driven-development` for every behavior change, `superpowers:systematic-debugging` for provider or Keychain failures, and `superpowers:verification-before-completion` before every commit and release claim.

**Goal:** Add one coherent Protect workflow to Ryddi that helps users decide what should be backed up, excluded, kept local, or reviewed for cleanup across Dropbox, Google Drive, and MEGA, and helps users migrate exposed environment credentials into 1Password without leaking, silently deleting, or automatically moving secrets.

**Architecture:** Keep `ReclaimerCore` as the only cleanup authority. Add a separate `RyddiProtectCore` library for cloud evidence, protection recommendations, provider plans, verification, and secret-migration metadata. Provider authentication remains app-owned and Keychain-backed. Secret values are handled only by a small isolated `RyddiSecretsHelper` process after explicit approval. A successful backup or migration can issue a short-lived, one-use authorization for a specific local file identity, but it never changes a finding's safety class and never bypasses Ryddi's normal dry-run, open-handle, confirmation, and Trash gates.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 14+, XCTest, Security.framework Keychain APIs, AuthenticationServices, URLSession, official SwiftyDropbox SDK, official MEGA SDK, Google Drive OAuth/Picker APIs, stable 1Password CLI commands, existing Ryddi audit/output/packaging infrastructure.

**Depends on:** `docs/superpowers/plans/2026-07-14-ryddi-v0.4-guided-cleanup-and-e2e.md` is implemented and its five-task navigation, focused app stores, responsive layouts, and full-flow E2E harness are passing. This plan adds one sixth task, Protect, without restoring feature-by-feature sidebar sprawl.

**Implementation start (2026-07-16):** Provider-neutral package boundaries, inert protection assessments, authentication primitives, Keychain storage, and metadata-only secret discovery may be built and tested from released `v0.3.1`. Protect navigation, app state, provider clients, and every cleanup-authority change remain blocked on the `v0.4` guided-cleanup shell and a separate security review.

**Current foundation evidence (2026-07-17):** `feature/protect-foundation` has focused proof for serialized path-policy mutation, live pre-Trash policy revalidation, hard cloud deadlines, conservative metadata-byte accounting, compiler-enforced Protect isolation, and restart-safe non-sensitive Keychain locators. The complete remediation suite passes `693` tests with `1` intentional skip and `0` failures. Neither executable links a Protect target, no provider is contacted, and no real credential or secret file content is read.

## Release Slices

| Release | Bundle build | User-visible promise | Allowed behavior | Explicitly deferred |
| --- | ---: | --- | --- | --- |
| `v0.5.0 Protect Readiness` | `6` | Connect cloud accounts, map local and remote storage, decide what deserves protection, inventory secret sources, and receive safe 1Password handoffs. | Read-only cloud metadata, local cloud-root discovery, metadata-only secret inventory, protection plans, redacted reports, official 1Password handoffs. | Cloud upload, remote delete, source secret mutation, unattended auth, secret-value migration. |
| `v0.6.0 Verified Protection` | `7` | Back up approved files into an app-owned destination, verify the remote copy, and migrate approved environment values into 1Password with rollback. | User-approved cloud upload, provider-specific verification, one-use local Trash release authorization, stable 1Password item/reference migration, source quarantine after verification. | Remote cloud delete, bidirectional sync, conflict resolution, unattended migration, bulk credential-store scraping, scheduled Protect actions. |

## Product Flow

Ryddi's primary journey becomes:

```text
Scan -> Decide -> Protect -> Verify -> Reclaim
```

The app has six top-level destinations after this plan:

1. Clean Up
2. Explore
3. Apps
4. Protect
5. Remote
6. History

Protect has two segmented workspaces, Cloud and Secrets. Dropbox, Google Drive, MEGA, and 1Password are connection or destination choices inside those workspaces, never separate sidebar destinations.

## Research Decisions

- Dropbox uses OAuth 2 with PKCE, least-privilege scopes, stable file IDs/revisions/content hashes, and the official [SwiftyDropbox SDK](https://dropbox.github.io/SwiftyDropbox/api-docs/10.0.0/). Follow the official [Dropbox OAuth guide](https://developers.dropbox.com/oauth-guide) and pin the reviewed SDK release.
- Google Drive uses the official desktop/mobile Picker authorization flow in the system browser with `trigger_onepick=true` and the non-sensitive `drive.file` scope only. The current desktop flow explicitly disallows combining other scopes, so Ryddi does not request identity, broad metadata, or restricted Drive scopes and does not host or embed a JavaScript Picker relay. Use the official [Drive scopes guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth) and [desktop/mobile Picker flow](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker).
- MEGA uses the official [MEGA SDK](https://github.com/meganz/sdk). Do not parse MEGAcmd human output, invoke `mega-session`, or expose an exported session in process output.
- 1Password Developer Environments remain a guided app handoff because the current stable CLI surface is not sufficient for a reliable native import/cutover. Follow the official [Environments](https://www.1password.dev/environments), [local environment destination](https://www.1password.dev/environments/local-env-file), [Shell Plugins](https://www.1password.dev/cli/shell-plugins), and [item creation](https://www.1password.dev/cli/item-create) guidance.
- Sensitive 1Password item values are supplied as structured JSON on stdin. They must never be command-line arguments, shell source text, logs, audit JSON, crash metadata, analytics, or clipboard contents.

## Global Constraints

- Minimum OS remains macOS 14+ and distribution remains signed/notarized outside the Mac App Store.
- No telemetry, path upload, remote AI analysis, root helper, sudo-password handling, cloud service operated by Ryddi, or Mac App Store sandbox migration.
- Do not add cloud or secret work to the LaunchAgent. Protect is interactive only in `v0.5` and `v0.6`.
- Never automatically upload or migrate credentials, Keychains, browser profiles, SSH private keys, signing certificates, OAuth databases, Photos libraries, GarageBand/Logic assets, VM/container disks, live databases, unknown app state, or unknown user data.
- Never infer deletion permission because a matching cloud object exists. Only verified, current, provider-specific evidence can create a one-use release authorization, and normal `ReclaimerCore` execution checks still apply.
- Never delete remote provider data in these releases. Upload destinations are app-owned and no-overwrite by default.
- Never force-download File Provider placeholders during inventory. Distinguish logical bytes, locally allocated bytes, remotely protected bytes, and estimated immediate reclaim.
- OAuth refresh tokens and MEGA sessions live only in the macOS data-protection Keychain with `kSecUseDataProtectionKeychain=true` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Ryddi omits `kSecAttrSynchronizable` entirely so the item is device-local; access tokens remain in memory when provider refresh semantics permit it.
- No provider client secret is bundled. Public client IDs and restricted API keys are configuration, not secrets.
- Audit records omit account email, access tokens, refresh tokens, MEGA sessions, full remote paths, secret values, and raw 1Password references.
- Before long build/test loops, run `df -h /System/Volumes/Data` and stop below `30Gi` free.
- Use `swift test --scratch-path "$PWD/.build"`, `swift build --scratch-path "$PWD/.build"`, and bounded run-local fixture directories.

## Package Boundaries

```text
MacDiskReclaimerApp
  |-- ReclaimerCore          cleanup authority and final execution guards
  |-- RyddiProtectCore       cloud/secrets evidence, plans, and verification
  |-- RyddiProtectAuth       app-only Keychain and authentication capability
  `-- RyddiSecretsHelper     isolated approved secret-value operations

reclaimer
  |-- ReclaimerCore
  `-- RyddiProtectCore       metadata-only/report commands; no cloud credentials

RyddiProtectCore -> ReclaimerCore is forbidden; Protect owns neutral evidence types and cannot compile against cleanup authority.
RyddiProtectAuth -> RyddiProtectCore is allowed.
ReclaimerCore -> RyddiProtectCore is forbidden.
RyddiProtectCore -> RyddiProtectAuth is forbidden.
reclaimer -> RyddiProtectAuth is forbidden.
```

The app target owns interactive OAuth/UI sessions and the `RyddiProtectAuth` capability, then injects authenticated provider clients into `RyddiProtectCore`. The CLI can inspect local cloud roots, build redacted reports, and inspect secret-source metadata, but it cannot link the credential target, read cloud credentials, or perform value-bearing migrations.

## Core Public Contracts

### Advisory protection boundary

The readiness slice creates no Protect bridge, provider rule, or second authorization store in `ReclaimerCore`. Protect evidence is an inert runtime-only assessment bound to the item observed by a scan:

```swift
public struct ProtectionSubject: Hashable, Sendable {
    public let scanSessionID: String
    public let findingID: String
    public let filesystemIdentity: ProtectionFilesystemIdentity
}

public enum ProtectionAssessmentState: String, Hashable, Sendable {
    case unknown
    case requiresProtection
    case providerEvidenceObserved
    case nativeExportRequired
    case rebuildableExclusionCandidate
}

public struct ProtectionAssessment: Hashable, Identifiable, Sendable {
    public let subject: ProtectionSubject
    public let state: ProtectionAssessmentState
    public let reasons: Set<ProtectionAssessmentReason>
    public let assessedAt: Date
    public var isAdvisoryOnly: Bool { true }
}
```

The type has no raw path, provider account identity, free-form reason, `Codable` conformance, cleanup-eligible state, or execution method. If `v0.6` later allows verified protection evidence to clear an explicit backup gate, it must extend the existing one-use `TrashExecutionAuthorizationRegistry`; a second capability store is forbidden. The extension must remain identity-, scan-, plan-, dry-run-, finding-, user-confirmation-, and expiry-bound and must preserve every final ReclaimerCore check.

### RyddiProtectCore cloud contracts

```swift
public enum CloudProviderKind: String, Codable, CaseIterable, Sendable {
    case dropbox
    case googleDrive
    case mega
}

public enum CloudPathStyle: String, Codable, CaseIterable, Sendable {
    case full
    case homeRelative
    case redacted
}

public struct CloudRequestContext: Hashable, Sendable {
    public let deadlineUptime: TimeInterval
    public let maximumResponseBytes: Int
}

public struct CloudConnectionLocator: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let provider: CloudProviderKind
    public let ordinal: Int
}

public struct CloudConnectionReference: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let provider: CloudProviderKind
    public let ordinal: Int
    public let connectedAt: Date
    public let grantedCapabilities: Set<CloudCapability>
}

public struct CloudObjectReference: Hashable, Identifiable, Sendable {
    public let id: String
    public let provider: CloudProviderKind
    public let parentID: String?
    public let displayName: String
    public let objectKind: CloudObjectKind
    public let logicalBytes: Int64?
    public let modifiedAt: Date?
    public let revision: String?
    public let providerHash: String?
    public let selectedByUser: Bool
}

public struct CloudInventoryPage: Sendable {
    public let objects: [CloudObjectReference]
    public let nextCursor: String?
    public let truncated: Bool
    public let rawResponseByteCount: Int
    public let responseByteCount: Int
}

public protocol CloudProviderAdapter: Sendable {
    var kind: CloudProviderKind { get }
    func connectionStatus(context: CloudRequestContext) async throws -> CloudConnectionStatus
    func accountReference(context: CloudRequestContext) async throws -> CloudConnectionReference
    func listPage(
        parentID: String?,
        cursor: String?,
        context: CloudRequestContext
    ) async throws -> CloudInventoryPage
    func metadata(
        for objectID: String,
        context: CloudRequestContext
    ) async throws -> CloudObjectReference
    func disconnect(context: CloudRequestContext) async throws
}
```

Raw provider account identities, object IDs, display names, revisions, provider hashes, and local/provider correlations are runtime-only and intentionally not `Codable`. Only the provider kind, Ryddi-generated UUID, and neutral ordinal in `CloudConnectionLocator` may survive restart. The readiness slice persists no provider identity or inventory. Any future audit type must be separately designed, bounded, redacted, and proven not to permit cross-install correlation.

`CloudProviderAdapter` has no upload, delete, move, rename, share, overwrite, or prune methods. Every adapter call receives the same absolute monotonic deadline and response-size bound for an inventory operation. A separate write capability may be designed for `v0.6` only after a new security review, and only app-owned destinations may implement it.

### Protection plans and future verification

```swift
public struct ProtectionPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let scanSessionID: UUID
    public let provider: CloudProviderKind
    public let entries: [ProtectionPlanEntry]
    public let expectedUploadBytes: Int64
    public let nonClaims: [String]
}

public struct CloudVerificationEvidence: Hashable, Sendable {
    public let subject: ProtectionSubject
    public let provider: CloudProviderKind
    public let byteCount: Int64
    public let verifiedAt: Date
    public let exactMatch: Bool
}
```

`CloudConnectionReference.displayLabel` is an app-generated neutral label such as `Dropbox 1`, not an account email or account hash. Raw local and provider digests exist only in non-`Codable`, short-lived comparison values. Audit records never contain reusable verification material.

### Secret hygiene contracts

No `Codable`, audit, report, or app-state model may contain a secret value.

```swift
public enum SecretSourceKind: String, Codable, Hashable, Sendable {
    case dotenv
}

public struct SecretSourceInventoryEntry: Hashable, Sendable {
    public let path: String
    public let fileIdentity: ProtectionFileIdentity
    public let fileSize: Int64
    public let posixMode: UInt32
    public let age: TimeInterval
    public let sourceKind: SecretSourceKind
    public let inspectionEligibility: SecretSourceInspectionEligibility
}
```

This foundation entry is runtime-only and records filesystem metadata before any content inspection. Future key-name findings, migration plans, and receipts must use Protect-owned neutral identity and evidence types rather than importing `FileIdentity`, `SafetyClass`, or `Evidence` from `ReclaimerCore`. Their exact redacted serialization contracts remain deferred until the isolated helper work has failing leak and rollback tests.

---

## Task 1: Baseline, Package Boundary, and Dependency Audit

**Files:**
- Modify: `Package.swift`
- Create: `Sources/RyddiProtectCore/CloudContracts.swift`
- Create: `Sources/RyddiProtectCore/ProtectionAssessment.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudContractsTests.swift`
- Create: `Tests/RyddiProtectCoreTests/ProtectionAssessmentTests.swift`
- Create: `Tests/RyddiProtectCoreTests/ArchitectureBoundaryTests.swift`
- Create: `docs/architecture/PROTECT_BOUNDARIES.md`

- [x] Start backend/security foundations from released `v0.3.1` on dedicated `feature/protect-foundation`; rebase app/UI work onto released `v0.4.0` before adding Protect navigation.
- [x] Run `df -h /System/Volumes/Data`; stop below `30Gi` free.
- [x] Run the full existing test suite and record the exact baseline test count (`601` tests, `1` intentional skip, `0` failures).
- [x] Add an isolated `RyddiProtectCore` library target with no dependency on `ReclaimerCore`; map neutral evidence only in a future app-owned integration layer.
- [x] Add focused `RyddiProtectCoreTests`; defer fixture resources until a real provider fixture exists.
- [x] Do not add `RyddiSecretsHelper` or provider SDK dependencies until their owning tasks have failing tests.
- [x] Add architecture tests that reject reverse/provider imports and keep both executables linked only to `ReclaimerCore`.
- [x] Document allowed dependency arrows, credential ownership, process boundaries, and release slicing.
- [ ] Review direct and transitive dependency licenses before pinning SwiftyDropbox and MEGA SDK.

**Verification:**

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
swift test --scratch-path "$PWD/.build" --filter ArchitectureBoundaryTests
swift build --scratch-path "$PWD/.build"
git diff --check
```

**Commit:** `build: add Ryddi Protect package boundary`

## Task 2: Add Inert Protection Assessments Without Cleanup Authority

**Files:**
- Create: `Sources/RyddiProtectCore/ProtectionAssessment.swift`
- Create: `Tests/RyddiProtectCoreTests/ProtectionAssessmentTests.swift`
- Modify: `Tests/RyddiProtectCoreTests/ArchitectureBoundaryTests.swift`

- [x] Bind each assessment to exact scan-session ID, finding ID, and Protect-owned `ProtectionFilesystemIdentity`.
- [x] Use typed source, state, and reason enums; reject non-unknown states without their required reason.
- [x] Keep assessment models runtime-only, path-free, provider-account-free, and non-`Codable`.
- [x] Expose no cleanup selection, safety-class mutation, plan-builder hook, executor hook, or authorization method.
- [x] Add architecture tests proving `ReclaimerCore` contains no provider names/imports and the CLI/app do not link Protect in this foundation slice.
- [x] Before any provider-derived additive path protection is implemented, harden `UserPathPolicyStore` so missing is an explicit empty first-run state while corrupt, unreadable, oversized, and unsafe-storage states fail closed; serialize app/CLI mutation transactions with stable process and file locks.
- [x] Model provider-suggested path protection as a runtime-only, additive `.protect` proposal that requires explicit user confirmation and has no save/remove/replace/exclude capability. No application path applies proposals yet.
- [x] Reserve future cleanup handoff in the security contract for an extension to the existing `TrashExecutionAuthorizationRegistry`; explicitly forbid a second authorization store.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter ProtectionAssessmentTests
swift test --scratch-path "$PWD/.build" --filter ArchitectureBoundaryTests
```

**Commit:** `feat: add inert protection assessment boundary`

## Task 3: Build the App-Only Keychain and Interactive Authentication Substrate

**Files:**
- Create: `Sources/RyddiProtectAuth/ProviderCredentialStore.swift`
- Create: `Sources/RyddiProtectCore/PKCE.swift`
- Create: `Tests/RyddiProtectAuthTests/ProviderCredentialStoreTests.swift`
- Create: `Tests/RyddiProtectCoreTests/PKCETests.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Modify: `Scripts/package-app.sh`
- Modify: `Scripts/release-check.sh`

- [x] Implement a bounded Security.framework-backed opaque credential store with a protocol and fakeable backend.
- [x] Use Keychain service names scoped by provider and connection UUID; never use an email address as the Keychain account key.
- [x] Set `kSecUseDataProtectionKeychain=true` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, omit `kSecAttrSynchronizable`, and update existing entries atomically.
- [x] Persist only a non-sensitive provider/UUID/ordinal locator in Keychain attributes and enumerate locators after relaunch without loading credential bytes.
- [ ] Store only refresh/access token envelopes or MEGA session material needed to resume the connection.
- [ ] Keep access tokens in memory when a provider supports refresh-token-only persistence.
- [ ] Disable or bypass provider SDK default token persistence when it cannot meet Ryddi's Keychain accessibility and audit requirements; one Ryddi-owned credential store remains authoritative.
- [ ] Implement delete/disconnect and revocation-aware invalidation.
- [ ] Load public provider client IDs/app keys from signed bundle configuration. The desktop/mobile Google Picker flow uses its OAuth client ID and does not add a Ryddi-hosted relay or bundled Picker API key. Fail closed with a setup diagnostic when required public configuration is absent.
- [ ] Prohibit provider client secrets in source, resources, environment exports, package scripts, and release artifacts. Source-level boundary tests are complete; bundle/release checks remain.
- [x] Implement RFC 7636 S256 generation, bounded anti-forgery state, exact callback/state validation, duplicate-parameter rejection, and public-client token parameters without a client-secret field.
- [ ] Add the `ASWebAuthenticationSession` wrapper, cancellation, timeout, and fakeable interactive session after the app target adopts Protect.
- [ ] Keep MEGA password and MFA codes in `SecureField` state only and hand them directly to the SDK; never store them.
- [ ] Add release checks that inspect the app bundle and manifest for known secret-key field names and test canaries.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter CloudCredentialStoreTests
swift test --scratch-path "$PWD/.build" --filter CloudAuthenticationTests
bash -n Scripts/package-app.sh Scripts/release-check.sh
```

**Commit:** `feat: add local-only cloud authentication substrate`

## Task 4: Implement the Provider-Neutral Read-Only Cloud Engine

**Files:**
- Create: `Sources/RyddiProtectCore/CloudProviderAdapter.swift`
- Create: `Sources/RyddiProtectCore/CloudInventoryStore.swift`
- Create: `Sources/RyddiProtectCore/CloudInventoryBuilder.swift`
- Create: `Sources/RyddiProtectCore/CloudRateLimiter.swift`
- Create: `Sources/RyddiProtectCore/CloudPrivacyRedactor.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudProviderConformanceTests.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudInventoryTests.swift`
- Create: `Tests/RyddiProtectCoreTests/Fixtures/Cloud/`

- [ ] Write one conformance suite that every provider adapter must pass.
- [x] Require bounded page size, total object count, raw-plus-canonical response accounting, absolute request deadlines, clamped retry delays, retry count, and serial requests in the shared builder.
- [ ] Treat provider output as untrusted and reject invalid UTF-8, negative sizes, path traversal, duplicate stable IDs with conflicting metadata, and oversized fields. Typed-model checks are complete; raw-byte and invalid-UTF-8 checks remain mandatory in each future adapter.
- [x] Implement cancellation that stops cooperative adapter work and produces an explicit cancelled/partial report, never a complete-looking report.
- [x] Handle 401/403 as revoked/degraded connection, 429 with bounded provider-aware backoff, and 5xx with bounded retries and jitter.
- [ ] Persist only redacted inventory snapshots; omit raw tokens, account email, and full provider paths.
- [x] Expose logical bytes and object counts with explicit non-claims and no local disk reclaim field.
- [x] Ensure read-only adapters cannot be cast to or reach `CloudBackupWriting` in `v0.5`; the foundation source contains no writer protocol.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter CloudProviderConformanceTests
swift test --scratch-path "$PWD/.build" --filter CloudInventoryTests
```

**Commit:** `feat: add bounded read-only cloud inventory engine`

## Task 5: Add Dropbox Read-Only Connection and Inventory

**Files:**
- Modify: `Package.swift`
- Modify: `Package.resolved`
- Create: `Sources/RyddiProtectCore/DropboxCloudAdapter.swift`
- Create: `Sources/MacDiskReclaimerApp/DropboxConnectionCoordinator.swift`
- Create: `Tests/RyddiProtectCoreTests/DropboxCloudAdapterTests.swift`
- Create: `Tests/RyddiProtectCoreTests/Fixtures/Cloud/dropbox-*.json`

- [ ] Pin the reviewed official SwiftyDropbox release exactly; do not use a floating branch.
- [ ] Request only account identity and file metadata/content capabilities needed by the feature.
- [ ] Implement OAuth authorization-code flow with PKCE, refresh-token persistence, exact state validation, cancel, disconnect, and revoked-token handling.
- [ ] Inventory with recursive `list_folder` pagination using stable IDs, revisions, server-modified timestamps, sizes, and `content_hash`.
- [ ] Preserve Dropbox namespace/root semantics and never construct identity from display path alone.
- [ ] Bound cursors, pages, object counts, and previews through the provider-neutral engine.
- [ ] Add fixtures for team-space-like roots, deleted entries, renamed paths, cursor continuation, rate limit, revoked auth, malformed hashes, and partial results.
- [ ] Verify the adapter contains no upload/delete/move calls in `v0.5` with a source-level denylist test.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter DropboxCloudAdapterTests
swift package show-dependencies
```

**Commit:** `feat: add read-only Dropbox protection evidence`

## Task 6: Add Google Drive Desktop Picker-Scoped Connection and Inventory

**Files:**
- Create: `Sources/RyddiProtectCore/GoogleDriveCloudAdapter.swift`
- Create: `Sources/RyddiProtectCore/GoogleDrivePickerSelection.swift`
- Create: `Sources/MacDiskReclaimerApp/GoogleDriveConnectionCoordinator.swift`
- Create: `Tests/RyddiProtectCoreTests/GoogleDriveCloudAdapterTests.swift`
- Create: `Tests/MacDiskReclaimerAppTests/GoogleDrivePickerTests.swift`
- Create: `Tests/RyddiProtectCoreTests/Fixtures/Cloud/google-*.json`

- [ ] Use OAuth authorization-code with PKCE and request exactly `drive.file`; the desktop/mobile Picker flow must not combine identity or other scopes.
- [ ] Do not request `drive`, `drive.readonly`, or `drive.metadata.readonly` in `v0.5` or `v0.6`.
- [ ] Present Google's official desktop/mobile Picker flow through `ASWebAuthenticationSession` using the documented `trigger_onepick=true`, `prompt=consent`, and optional bounded multiple/folder-selection parameters.
- [ ] Accept only `picked_file_ids`, authorization code, exact callback state, returned scope, and documented error fields from the callback. Reject duplicate parameters, unexpected hosts/schemes, missing state, scope expansion, oversized IDs, and excessive selection counts.
- [ ] Exchange the one-use authorization code through the native token endpoint with the PKCE verifier. Do not expose an access token to an embedded web view, JavaScript bridge, local HTTP server, or Ryddi-hosted relay.
- [ ] Validate selected object count, object IDs, returned scope, and later Drive API MIME metadata before inventory.
- [ ] Inventory selected individual files. Enable selected-folder recursion only if the integration test proves child access under `drive.file`; otherwise show a precise individual-file limitation and do not silently request broader scope.
- [ ] If the official desktop/mobile Picker flow cannot complete with the registered native callback and exact `drive.file` scope, fail the integration gate and ship Google local-root analysis without account connection rather than broadening scopes or adding a relay.
- [ ] Distinguish binary files from Google-native Docs, Sheets, and Slides. Native documents remain `nativeExportRequired` and cannot authorize local reclaim.
- [ ] Capture provider file ID, version/modified time, size, MIME type, and provider `md5Checksum` where available.
- [ ] Add fixtures for shortcuts, shared files, native documents, missing checksums, revoked access, inaccessible selected IDs, and partial page failure.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter GoogleDriveCloudAdapterTests
swift test --scratch-path "$PWD/.build" --filter GoogleDrivePickerTests
```

**Commit:** `feat: add picker-scoped Google Drive evidence`

## Task 7: Add MEGA SDK Read-Only Connection and Inventory

**Files:**
- Modify: `Package.swift`
- Modify: `Package.resolved`
- Create: `Sources/RyddiProtectCore/MegaCloudAdapter.swift`
- Create: `Sources/MacDiskReclaimerApp/MegaConnectionCoordinator.swift`
- Create: `Tests/RyddiProtectCoreTests/MegaCloudAdapterTests.swift`
- Create: `Tests/RyddiProtectCoreTests/Fixtures/Cloud/mega-*.json`
- Modify: `Scripts/package-app.sh`
- Modify: `Scripts/release-check.sh`

- [ ] Pin the reviewed official MEGA SDK release exactly and audit its binary/native transitive footprint.
- [ ] Wrap SDK callbacks behind Swift continuations with cancellation and single-resume protection.
- [ ] Support password login and MFA through ephemeral secure UI, then export only the resumable session into Ryddi's Keychain store.
- [ ] Disclose that MEGA does not provide Dropbox/Google-style granular OAuth scopes; Ryddi's read-only guarantee is enforced by its narrow adapter and mutation-API denylist.
- [ ] Resume with the Keychain session when valid; on invalid session, delete it and require interactive login.
- [ ] Enumerate nodes by stable handle, parent handle, type, name, size, modification time, and SDK fingerprint metadata.
- [ ] Never invoke MEGAcmd, parse terminal output, log in through a shell, or call any API that prints/exports a session to stdout.
- [ ] Add tests for duplicate callbacks, cancellation races, invalid sessions, MFA-required state, malformed names, large trees, and permission errors.
- [ ] Ensure packaging embeds/signs any required native frameworks with Hardened Runtime and release checks verify them recursively.
- [ ] Add a source denylist for remove, move, rename, share, export-session logging, and transfer APIs in the read-only adapter.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter MegaCloudAdapterTests
swift build --scratch-path "$PWD/.build"
Scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 dist/Ryddi.app
```

**Commit:** `feat: add read-only MEGA protection evidence`

## Task 8: Discover Local Cloud Roots and Correlate Protection Evidence

**Files:**
- Create: `Sources/RyddiProtectCore/CloudStorageRootDiscovery.swift`
- Create: `Sources/RyddiProtectCore/CloudMaterialization.swift`
- Create: `Sources/RyddiProtectCore/CloudCorrelation.swift`
- Create: `Sources/RyddiProtectCore/ProtectionPolicy.swift`
- Create: `Sources/RyddiProtectCore/ProtectionPlan.swift`
- Create: `Sources/RyddiProtectCore/ProtectionReport.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudStorageRootDiscoveryTests.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudCorrelationTests.swift`
- Create: `Tests/RyddiProtectCoreTests/ProtectionPolicyTests.swift`
- Modify: `Sources/ReclaimerCore/UserPathPolicy.swift`

- [ ] Discover candidate sync roots under `~/Library/CloudStorage` and user-selected MEGA sync roots without following symlinks or traversing their full contents during discovery.
- [ ] Require explicit user confirmation before treating an inferred folder as a provider root.
- [ ] Save confirmed root identity, provider, connection ID, and bookmark/reference needed for later access; revalidate identity every run.
- [ ] Inspect File Provider materialization metadata without triggering download or hydration.
- [ ] Distinguish local allocated bytes, logical bytes, placeholder-only bytes, and remote object bytes.
- [ ] Correlate by provider stable ID/revision where metadata supports it; otherwise require exact relative path, byte size, modification tolerance, and provider cryptographic hash before saying `alreadyProtected`.
- [ ] Never call a filename/size-only match protected.
- [ ] Classify rebuildable caches and generated developer artifacts as `rebuildableExclude`, ordinary documents/history as `backUpBeforeReview`, databases/VMs/Photos/creative libraries as `nativeExportRequired`, and secrets as `secretNeverCloud`.
- [ ] Preserve unknown and personal data by default.
- [ ] Build plans from explicit user choices: Protect always, Back up before review, Keep local, Exclude rebuildable, Native guidance.
- [ ] Present confirmed cloud roots and discovered secret-source paths as additive `.protect` rule suggestions. Persist them only after explicit user confirmation and a successful `UserPathPolicyStore` write/readback.
- [ ] Provider suggestions can never create `.exclude` rules or remove/replace existing user protection.
- [ ] Export Markdown/JSON reports with full, home-relative, and redacted paths plus explicit non-claims.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter CloudStorageRootDiscoveryTests
swift test --scratch-path "$PWD/.build" --filter CloudCorrelationTests
swift test --scratch-path "$PWD/.build" --filter ProtectionPolicyTests
```

**Commit:** `feat: map local storage to cloud protection evidence`

## Task 9: Ship the v0.5 Protect Workspace, CLI Reports, and Audit Records

**Files:**
- Create: `Sources/MacDiskReclaimerApp/ProtectWorkspaceView.swift`
- Create: `Sources/MacDiskReclaimerApp/CloudConnectionSheet.swift`
- Create: `Sources/MacDiskReclaimerApp/CloudProtectionInspector.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+Protect.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardDestination.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardDependencies.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/AccessibilityIDs.swift`
- Create: `Sources/reclaimer/ProtectCommands.swift`
- Modify: `Sources/reclaimer/ReclaimerCLI.swift`
- Modify: `Sources/ReclaimerCore/AuditStore.swift`
- Modify: `Sources/ReclaimerCore/AuditStoreSnapshot.swift`
- Create: `Tests/MacDiskReclaimerAppTests/ProtectWorkspaceTests.swift`
- Create: `Tests/ReclaimerCLITests/ProtectCommandTests.swift`
- Create: `Tests/ReclaimerCoreTests/ProtectAuditTests.swift`

- [ ] Change destination tests from five to six and migrate unknown/legacy routes safely to Clean Up.
- [ ] Build one Protect workspace with a Cloud/Secrets segmented control.
- [ ] Cloud first-run state shows provider connection choices and local root discovery, not an empty dashboard.
- [ ] Connected state shows: connection health, local coverage, protected bytes, local-only bytes, placeholders, native-export items, rebuildable exclusions, unknowns, and last evidence time.
- [ ] Make the primary action advance one step: Connect, Scan Protection, Review Decisions, or Export Report.
- [ ] Add provider connection/disconnect sheets with explicit scope and local-data language.
- [ ] Do not render Upload, Back Up Now, Delete Remote, or Reclaim Protected in `v0.5`.
- [ ] Add local-only CLI commands:

```text
reclaimer protect cloud roots [--json]
reclaimer protect cloud report --input AUDIT_ID [--path-style full|home-relative|redacted] [--output FILE]
reclaimer protect secrets scan --path ROOT [--json]
reclaimer protect audit list [--json]
```

- [ ] Make CLI cloud credential access fail with a clear app-only message.
- [ ] Add typed audit prefixes for cloud connection metadata, inventory reports, protection plans, and secret-source reports.
- [ ] Hash provider object IDs, revisions, account IDs, vault IDs, item IDs, and reference strings before audit persistence.
- [ ] Add test and release scans proving canary account email, remote path, token, session, and secret values are absent from audit JSON.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter ProtectWorkspaceTests
swift test --scratch-path "$PWD/.build" --filter ProtectCommandTests
swift test --scratch-path "$PWD/.build" --filter ProtectAuditTests
swift run --scratch-path .build reclaimer protect cloud roots --json
```

**Commit:** `feat: add Protect readiness workspace`

## Task 10: Add Metadata-Only Secret Source Inventory

**Files:**
- Create: `Sources/RyddiProtectCore/SecretSourceInventory.swift`
- Create: `Sources/RyddiProtectCore/DotenvMetadataParser.swift`
- Create: `Sources/RyddiProtectCore/GitTrackingInspector.swift`
- Create: `Sources/RyddiProtectCore/SecretSourcePolicy.swift`
- Create: `Sources/MacDiskReclaimerApp/SecretSourcesView.swift`
- Create: `Tests/RyddiProtectCoreTests/SecretSourceInventoryTests.swift`
- Create: `Tests/RyddiProtectCoreTests/DotenvMetadataParserTests.swift`
- Create: `Tests/RyddiProtectCoreTests/GitTrackingInspectorTests.swift`
- Create: `Tests/RyddiProtectCoreTests/Fixtures/Secrets/`

- [x] Scan only explicitly supplied roots with bounded depth, visited-entry count, elapsed time, and hard upper limits.
- [x] Detect `.env` and `.env.*` while excluding examples/samples; explicitly configured shell exports and supported CLI credential-store metadata remain deferred.
- [x] Skip `.env.example`, `.env.sample`, vendor/build directories, symlinks, device files, sockets, FIFOs, unreadable files, and files over 1 MiB.
- [x] Initial inventory records path, `lstat` identity, size, mode, age, and source kind without opening file contents. Owner and Git state remain deferred.
- [ ] Require a second explicit Inspect Key Names action before parsing key names.
- [ ] Parse a strict documented dotenv subset and fail closed on command substitution, shell evaluation, heredocs, NUL/control data, malformed quoting, duplicate ambiguous keys, and more than 512 keys.
- [ ] Keep values in a short-lived local buffer only long enough to skip/validate syntax; never retain them in models, errors, UI, logs, reports, search indexes, or audit.
- [ ] Display only key names, duplicate-key warnings, Git tracking/ignore state, and supported destination lanes.
- [ ] Present every discovered secret source as `doNotTouch` in Protect and offer an explicit additive `.protect` rule; discovery alone does not mutate cleanup policy.
- [ ] Add Git tests for tracked, staged, ignored, nested repo, worktree, absent Git, and command timeout.
- [ ] Treat tracked, staged, or historically committed secret sources as a separate exposure incident: migration may copy approved values into 1Password, but automatic source quarantine is blocked and the UI must recommend rotation and Git-history review.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter SecretSourceInventoryTests
swift test --scratch-path "$PWD/.build" --filter DotenvMetadataParserTests
swift test --scratch-path "$PWD/.build" --filter GitTrackingInspectorTests
```

**Commit:** `feat: inventory secret sources without retaining values`

## Task 11: Add Stable 1Password Capability Probes and Guided Handoffs

**Files:**
- Create: `Sources/RyddiProtectCore/OnePasswordCapabilityProbe.swift`
- Create: `Sources/RyddiProtectCore/OnePasswordCommandPolicy.swift`
- Create: `Sources/RyddiProtectCore/OnePasswordCommandRunner.swift`
- Create: `Sources/MacDiskReclaimerApp/OnePasswordHandoffView.swift`
- Create: `Tests/RyddiProtectCoreTests/OnePasswordCapabilityProbeTests.swift`
- Create: `Tests/RyddiProtectCoreTests/OnePasswordCommandPolicyTests.swift`

- [ ] Resolve `op` through a trusted executable resolver and require a supported stable CLI version.
- [ ] Probe command availability and auth state without reading item values or inventorying vault contents.
- [ ] Detect supported Shell Plugin IDs from a bundled allowlist and map known environment key groups conservatively.
- [ ] For Shell Plugins, launch `op plugin init <allowlisted-plugin-id>` in a real Terminal/TTY after confirmation; no secret values or source paths enter argv.
- [ ] For Developer Environments, open the official 1Password import flow and present a bounded checklist for destination creation and project cutover.
- [ ] Validate a user-selected local Environment destination as a FIFO, owned by the current user, mode-restricted, not a symlink, and connected to the expected project path.
- [ ] Do not depend on beta `op environment` commands or pretend an Environment import completed when only a handoff occurred.
- [ ] Keep the original source file untouched in `v0.5`.
- [ ] Add non-claims: no values migrated, no source changed, no vault inspected, no unattended credential work.
- [ ] Reject commands containing `op read`, `op item get`, `--reveal`, service-account tokens, shell interpolation, arbitrary plugin IDs, or value-bearing arguments in the handoff lane.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter OnePasswordCapabilityProbeTests
swift test --scratch-path "$PWD/.build" --filter OnePasswordCommandPolicyTests
swift run --scratch-path .build reclaimer protect secrets scan --path Tests --json
```

**Commit:** `feat: add guided 1Password protection handoffs`

## Task 12: Complete v0.5 Privacy, Accessibility, E2E, and Release Proof

**Files:**
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Modify: `docs/RELEASE_CHECKLIST.md`
- Create: `docs/CLOUD_PROVIDERS.md`
- Create: `docs/SECRETS_HYGIENE.md`
- Create: `docs/releases/v0.5.0.md`
- Modify: `Scripts/app-e2e-smoke.sh`
- Modify: `Scripts/release-check.sh`

- [ ] Document exact cloud metadata, Keychain material, local paths, key names, object IDs, and audit fields Ryddi handles.
- [ ] Explain redaction limits: display names and key names can themselves reveal sensitive context.
- [ ] Document provider scope/revocation steps and how Disconnect affects local evidence.
- [ ] Document `v0.5` as read-only readiness, not backup, sync, secret migration, or cleanup authorization.
- [ ] Add Accessibility identifiers and labels for Protect destination, segment, providers, connection state, scan, decisions, reports, source inventory, and 1Password handoffs.
- [ ] Add deterministic E2E fixtures for disconnected, connected, expired auth, partial inventory, no local root, placeholders, secret sources, unsupported dotenv, missing `op`, and locked 1Password.
- [ ] Test 760x600, 980x680, and 1440x900 in light/dark, keyboard-only, reduced motion, increased contrast, and large text.
- [ ] Add canary leak scan across app logs, reports, audits, `/tmp`, process argv snapshots, and packaged artifacts.
- [ ] Run provider sandbox smoke only with disposable accounts and disposable files; never use user production data for release proof.
- [ ] Sign/notarize only after the full local release gate passes.

**Verification:**

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
swift build --scratch-path "$PWD/.build"
Scripts/app-e2e-smoke.sh
Scripts/release-check.sh
git diff --check
```

**Release gate:** Create `v0.5.0` only when the manifest proves tests, E2E, signed nested frameworks, notarization accepted, stapling valid, Gatekeeper accepted, and canary leak scan clean.

**Commit:** `docs: complete v0.5 Protect readiness evidence`

## Task 13: Add the Isolated 1Password Migration Helper for v0.6

**Files:**
- Modify: `Package.swift`
- Create: `Sources/RyddiSecretsHelper/main.swift`
- Create: `Sources/RyddiProtectCore/SecretHelperProtocol.swift`
- Create: `Sources/RyddiProtectCore/SecretMigrationPlan.swift`
- Create: `Sources/RyddiProtectCore/SecretMigrationReceipt.swift`
- Create: `Sources/RyddiProtectCore/SecretHoldingStore.swift`
- Create: `Sources/MacDiskReclaimerApp/SecretMigrationView.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+SecretMigration.swift`
- Create: `Tests/RyddiSecretsHelperTests/SecretHelperSecurityTests.swift`
- Create: `Tests/RyddiProtectCoreTests/SecretMigrationTests.swift`
- Modify: `Scripts/package-app.sh`
- Modify: `Scripts/release-check.sh`

- [ ] Add a nested helper executable signed with the same team and Hardened Runtime.
- [ ] Pass one bounded control plan on stdin. No secret, source path, destination path, field name, item title, vault title, or smoke command may appear in helper argv.
- [ ] Limit stdin to 1 MiB, maximum 512 keys, maximum field size 64 KiB, and one source file.
- [ ] Call `setrlimit(RLIMIT_CORE, 0)`, set `umask(077)`, close inherited descriptors, and construct a minimal allowlisted environment.
- [ ] Verify the direct parent process satisfies Ryddi's designated code requirement and Team ID before reading the control plan; refuse standalone or unsigned-parent invocation.
- [ ] Open the source with `openat`, `O_NOFOLLOW`, mode/owner checks, and exact descriptor-bound identity captured by the approved plan; reject all changes after planning.
- [ ] Parse values from mutable byte buffers rather than long-lived Swift `String` values and zero those buffers as soon as practical.
- [ ] Allow vault metadata listing only on the explicit destination-selection step; never enumerate items or fields.
- [ ] Create one user-reviewed Secure Note item with concealed custom fields for a supported dotenv source. Refuse automatic migration above the provider-tested field limit and require a manual split.
- [ ] Create 1Password items with structured JSON via `op item create - --format json`; sensitive fields travel on stdin only.
- [ ] Never invoke a shell. Resolve `op` from a small trusted location allowlist, bind its filesystem/code identity into the plan, and launch that exact executable with an argv allowlist.
- [ ] Treat the JSON returned by `op item create` as secret-bearing: parse it only in helper memory, extract the minimum stable IDs, and never log or persist the response.
- [ ] Generate a reference-only `.env.1password` using `SafeFileOutput`, `O_EXCL`, no symlink following, and mode `0600`. Refuse overwrite.
- [ ] Build references from stable vault/item IDs rather than display names. Let the user decide whether to commit the reference-only file; never edit `.gitignore`, stage, commit, or rewrite history.
- [ ] Verify value equality inside the helper by resolving generated references through bounded `op inject` stdin/stdout pipes; do not emit resolved values.
- [ ] Optionally run a user-selected smoke command only through explicit `op run --env-file` confirmation in a visible Terminal session. Record only command hash, exit status, and duration.
- [ ] Keep the source untouched until item creation, reference-file creation, equality verification, and optional smoke check all succeed.
- [ ] Offer source quarantine only as a separate final confirmation.
- [ ] Permit automatic source quarantine only for an ignored or non-repository dotenv source whose identity and parent are unchanged. Tracked/staged/history-exposed sources remain in place for explicit source-control remediation.
- [ ] Quarantine with same-volume atomic rename into a mode-0700 app holding directory. Refuse automatic cross-volume movement.
- [ ] Store mode, identity, original parent identity, key-set hash, and restoration metadata, but no values, in the receipt.
- [ ] Support Restore and Expire actions. Expiry is manual in `v0.6`; no scheduled source deletion.
- [ ] On any failure, remove only helper-created incomplete local reference files, leave the source untouched, never auto-delete a created 1Password item, and produce a redacted receipt that lets the user open/review the orphaned item.
- [ ] State explicitly that migration does not rotate or revoke an exposed credential and does not remove it from Git history, deployment logs, CI variables, or third-party systems.

**Security tests:**

- [ ] Canary values never appear in parent/helper argv, environment snapshots, stdout, stderr, logs, audit JSON, reports, filenames, temporary files, or crash/core artifacts.
- [ ] Kill helper before item creation, after item creation, during reference write, during equality verification, and before quarantine; source remains recoverable in every case.
- [ ] Reject symlink swaps, inode replacements, hard-link surprises, permission changes, owner changes, FIFO/socket/device input, oversized files, malformed dotenv, and output-path races.
- [ ] Verify no helper code path can invoke arbitrary `op` subcommands or arbitrary executables.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter SecretHelperSecurityTests
swift test --scratch-path "$PWD/.build" --filter SecretMigrationTests
swift build --scratch-path "$PWD/.build"
Scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 dist/Ryddi.app
```

**Commit:** `feat: add verified 1Password environment migration`

## Task 14: Add Verified Provider Uploads and Reclaim Authorization for v0.6

**Files:**
- Create: `Sources/RyddiProtectCore/CloudBackupExecutor.swift`
- Create: `Sources/RyddiProtectCore/CloudVerification.swift`
- Create: `Sources/RyddiProtectCore/DropboxContentHash.swift`
- Create: `Sources/RyddiProtectCore/DropboxBackupWriter.swift`
- Create: `Sources/RyddiProtectCore/GoogleDriveBackupWriter.swift`
- Create: `Sources/RyddiProtectCore/MegaBackupWriter.swift`
- Create: `Sources/MacDiskReclaimerApp/CloudBackupReviewView.swift`
- Create: `Sources/MacDiskReclaimerApp/CloudVerificationView.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+CloudBackup.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudBackupExecutorTests.swift`
- Create: `Tests/RyddiProtectCoreTests/CloudVerificationTests.swift`
- Create: `Tests/RyddiProtectCoreTests/ProviderBackupWriterTests.swift`

- [ ] Add `CloudBackupWriting` only to authenticated writer types; keep read-only adapters unchanged.
- [ ] Upload only explicitly selected regular files, maximum 5 GiB each, into `Ryddi Backups/<device>/<plan-id>/`.
- [ ] Refuse directories, packages, sparse VM disks, databases, symlinks, hard-linked surprises, cloud placeholders, credentials, Keychains, browser profiles, Photos/creative libraries, and unknown protected state.
- [ ] Re-resolve source identity and open a stable read descriptor immediately before upload. Abort if the file changes while reading.
- [ ] Hash from the same stable descriptor used for upload, compare `fstat` before/after streaming, and keep raw digest bytes in memory only.
- [ ] Use provider resumable/chunked upload flows where applicable. Persist only non-secret resumable state in a bounded receipt.
- [ ] Never overwrite an existing remote object. A collision creates a new immutable plan-scoped destination or fails for review.
- [ ] Dropbox verification computes the documented local Dropbox content hash and compares it with server `content_hash`, exact size, object ID, and revision.
- [ ] Google Drive verification compares local MD5 with provider-computed `md5Checksum`, exact size, object ID, and version. Google-native documents remain unsupported.
- [ ] MEGA verification streams the completed remote object back through the SDK and compares SHA-256 and exact byte count. SDK fingerprint alone cannot authorize reclaim.
- [ ] Verification failure never deletes the remote object automatically and never marks the local source protected.
- [ ] On exact verification, request a narrowly reviewed extension of the existing `TrashExecutionAuthorizationRegistry`; do not create a parallel authorization store. Bind any resulting one-use capability to current local identity, provider evidence, scan session, reclaim plan, protection plan, finding, user confirmation, and a maximum 15-minute expiry.
- [ ] Return the user to Clean Up with a preselected, still-reviewable candidate. Require a new dry run, explicit authorization, and Trash action.
- [ ] Keep remote provider data immutable from Ryddi. No delete, overwrite, move, rename, retention enforcement, or cleanup API.
- [ ] Add an audit chain: protection plan -> upload receipt -> verification evidence -> authorization issue/consume -> reclaim receipt, all linked by IDs and redacted hashes.

**Verification:**

```bash
swift test --scratch-path "$PWD/.build" --filter CloudBackupExecutorTests
swift test --scratch-path "$PWD/.build" --filter CloudVerificationTests
swift test --scratch-path "$PWD/.build" --filter ProviderBackupWriterTests
swift test --scratch-path "$PWD/.build" --filter TrashExecutionAuthorization
```

**Commit:** `feat: verify cloud backups before local reclaim`

## Task 15: Complete v0.6 Full-Flow E2E, Recovery, and Release Proof

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/ProtectWorkspaceView.swift`
- Modify: `Sources/MacDiskReclaimerApp/AuditHistoryView.swift`
- Create: `Sources/MacDiskReclaimerApp/ProtectionTimelineView.swift`
- Modify: `Sources/MacDiskReclaimerApp/AccessibilityIDs.swift`
- Modify: `Scripts/app-e2e-smoke.sh`
- Modify: `Scripts/release-check.sh`
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Modify: `docs/RELEASE_CHECKLIST.md`
- Modify: `docs/CLOUD_PROVIDERS.md`
- Modify: `docs/SECRETS_HYGIENE.md`
- Create: `docs/releases/v0.6.0.md`

- [ ] Add one visible Protection timeline in History linking scan, decision, backup/migration, verification, source disposition, reclaim, and restore evidence.
- [ ] Add Restore Original for quarantined dotenv sources and Open Provider for completed cloud backups.
- [ ] Ensure cancellation and app relaunch show an honest resumable/failed state rather than a success card.
- [ ] Add deterministic fake-provider E2E for:
  - connect -> inventory -> decide -> upload -> verify -> return to cleanup -> dry run -> Trash -> receipt;
  - upload interruption and retry;
  - verification mismatch;
  - expired/consumed authorization;
  - source identity change;
  - secret inventory -> plan -> item creation -> equality verification -> reference file -> quarantine -> restore;
  - helper interruption at every transaction boundary;
  - 1Password locked, cancelled Touch ID, missing CLI, unsupported CLI, and failed smoke command.
- [ ] Add provider sandbox integration tests using disposable accounts and generated canary files for Dropbox, Google Drive, and MEGA.
- [ ] Prove sandbox tests never call remote delete and clean test artifacts manually through provider-native tooling after evidence capture.
- [ ] Run responsive/accessibility matrix at 760x600, 980x680, and 1440x900 in light/dark, keyboard-only, VoiceOver smoke, reduced motion, increased contrast, and large text.
- [ ] Add process-boundary leak tests that inspect app/helper/op argv, inherited environment, logs, reports, audit files, holding metadata, crash/core configuration, and packaged artifacts.
- [ ] Add release manifest entries for provider SDK versions, scopes, nested signatures, Keychain posture, helper signature, E2E scenarios, sandbox account run IDs, and explicit non-claims.
- [ ] Do not publish if any provider was tested only through mocks, any nested code is unsigned, notarization is not Accepted, stapling fails, Gatekeeper rejects, or leak scans find a canary.

**Final verification:**

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
swift build --scratch-path "$PWD/.build"
Scripts/app-e2e-smoke.sh
Scripts/release-check.sh
RYDDI_RELEASE_SIGNING=required RYDDI_ARTIFACT_BASENAME=Ryddi-v0.6.0 Scripts/release-check.sh
git diff --check
```

**Release gate:** Publish `v0.6.0` only when all tests, fake-provider E2E, disposable-provider integration tests, helper security tests, signatures, notarization, stapling, Gatekeeper, and privacy scans are evidenced in the release manifest.

**Commit:** `docs: complete verified Protect release evidence`

---

## Task Dependencies and Parallel Workstreams

```text
Task 1 package boundary
  |-- Task 2 cleanup protection guard
  |-- Task 3 Keychain/auth
  |     |-- Task 5 Dropbox
  |     |-- Task 6 Google Drive
  |     `-- Task 7 MEGA
  |            `-- Task 8 correlation/policy
  |                    `-- Task 9 v0.5 app/CLI/audit
  |-- Task 10 secret inventory
  |       `-- Task 11 1Password handoffs
  |                    `-- Task 12 v0.5 release
  |-- Task 13 verified secret migration
  `-- Task 14 verified cloud backup
          `-- Task 15 v0.6 full-flow release
```

Safe parallel goals after Task 1:

```text
/goal Cloud authentication and provider-neutral adapter
Own CloudCredentialStore, CloudAuthentication, CloudProviderAdapter, conformance tests.
Do not implement provider-specific adapters, UI, cleanup policy, or secret handling.
```

```text
/goal Dropbox read-only adapter
Own DropboxCloudAdapter and fixtures after the neutral conformance suite lands.
No upload/delete/move APIs.
```

```text
/goal Google Picker-scoped adapter
Own GoogleDriveCloudAdapter, Picker selection contract, and fixtures.
Use drive.file only; no restricted broad scopes.
```

```text
/goal MEGA SDK read-only adapter
Own MegaCloudAdapter, SDK bridge, packaging proof, and fixtures.
No MEGAcmd and no mutation APIs.
```

```text
/goal Secret metadata inventory
Own SecretSourceInventory, DotenvMetadataParser, GitTrackingInspector, and tests.
No migration or secret-value persistence.
```

```text
/goal Protect workspace and audit presentation
Own Protect SwiftUI surfaces, accessibility IDs, redacted reports, and audit views after core contracts settle.
No cleanup authority or credential storage.
```

Tasks 2, 13, and 14 require a single safety owner and should not be split across concurrent workers touching executor/helper transaction boundaries.

## Test Matrix

| Layer | Required proof |
| --- | --- |
| Architecture | Import boundary, no provider SDK in ReclaimerCore, read-only adapter has no mutation surface. |
| Keychain | Accessibility class, non-synchronizing entries, update/delete, locked/cancelled/revoked state, no account email keys. |
| Auth | PKCE, callback state, timeout, cancellation, revocation, MFA, no client secrets, no token logs. |
| Provider parsers | Pagination, malformed output, duplicate IDs, invalid sizes, rate limits, partial results, bounded work. |
| Local roots | Symlinks, bookmarks, identity changes, File Provider placeholders, no hydration, allocated vs logical bytes. |
| Correlation | Exact hash/revision evidence, rename, stale metadata, false filename/size match, native-document limits. |
| Cleanup bridge | One use, expiry, identity/plan/session binding, rescan requirement, normal dry-run/Trash checks remain. |
| Secret inventory | Metadata-only first, explicit key inspection, strict dotenv grammar, Git state, no value retention. |
| Helper | stdin control, argv/env hygiene, core dumps disabled, transaction interruption, path races, canary leakage. |
| 1Password | Supported CLI, structured item stdin, equality check, reference-only output, smoke check, quarantine/restore. |
| UI | Six-task navigation, Protect flow, empty/degraded states, responsive sizes, keyboard, VoiceOver, dark/light. |
| Integration | Disposable Dropbox, Google Drive, MEGA, and 1Password data; no production user data or remote deletion. |
| Release | Full suite, E2E, signed nested code, notarization Accepted, stapling, Gatekeeper, leak scan, manifest. |

## Definition of Done

`v0.5.0` is done only when a user can safely connect each provider, inspect bounded local/remote evidence, make protection decisions, inventory secret sources without exposing values, and follow supported 1Password handoffs, with no write controls or misleading backup claims.

`v0.6.0` is done only when a user can explicitly back up one supported regular file, verify it with provider-specific cryptographic evidence, return through Ryddi's normal cleanup flow, migrate one supported dotenv source into a stable 1Password item/reference workflow, verify equality, quarantine and restore the original, and inspect a redacted end-to-end receipt.

## Non-Goals Through v0.6

- No bidirectional or continuous cloud sync.
- No remote cloud cleanup, deduplication, delete, overwrite, move, rename, retention enforcement, or provider Trash management.
- No broad Google Drive restricted scope.
- No background cloud scans, scheduled backups, or scheduled secret migration.
- No autonomous choice of what personal content to upload or delete.
- No password manager replacement, vault browser, secret search, service-account automation, or bulk vault inventory.
- No migration of SSH private keys, Keychains, browser credential databases, signing identities, certificates, or hardware-backed keys.
- No automatic modification of project scripts, shell profiles, CI settings, deployment environments, or source-control history.
- No promise that remote bytes equal immediately reclaimable APFS bytes.
- No cleanup authorization from a cloud filename, path, size, thumbnail, placeholder, fingerprint-only value, or stale receipt.

## Assumptions

- Provider developer applications, callback URLs, public client IDs, restricted API keys, and disposable test accounts will be configured before live integration gates.
- The official provider SDK releases named during implementation will be re-verified and pinned at implementation time rather than copied blindly from this planning date.
- 1Password desktop app and a supported stable `op` CLI are user-managed prerequisites for migration; Ryddi does not store 1Password credentials.
- A user may choose a native provider client instead of connecting an API account. In that case Ryddi can analyze confirmed local cloud roots but must label remote verification unavailable.
- Source files remain authoritative until verification and explicit source-disposition approval complete.
- This plan intentionally favors reversible, user-driven protection over automatic backup or credential movement.
