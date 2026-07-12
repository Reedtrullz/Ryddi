# Ryddi Recoverable Trash And Release Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users complete one useful, recoverable cleanup flow while making installed-build signing and notarization claims independently verifiable and conservative.

**Architecture:** Add a capability-bound Trash execution lane for selected `autoSafe` items only. Re-run every safety check immediately before `FileManager.trashItem`, record the resulting Trash URL, and keep direct cache deletion, compression, and holding-area mutation disabled. Separately, combine signed embedded build metadata with bounded local runtime signature/Gatekeeper probes and an optional external release manifest.

**Tech Stack:** Swift 6, Foundation `FileManager`, Darwin file metadata, Security/codesign verification, `spctl`, SwiftUI confirmation sheets, SwiftPM, shell packaging/notary scripts, GitHub Actions.

## Global Constraints

- No root helper, scheduled destructive work, direct cache delete, remote cleanup, VM disk deletion, or app-state deletion.
- Only `.trash` actions from `autoSafe` findings may execute in this release.
- Protected paths, symlinks, active files, changed identities, stale sessions, and unmatched dry-run receipts fail closed.
- A final path check reduces but cannot make pathname replacement atomic; the UI and receipt must not claim atomicity.
- A release is called notarized only after Apple reports `Accepted`, stapling validates, and Gatekeeper accepts the exact app.
- Run disk guardrails and bounded Swift scratch paths from the global instructions.

---

## Task 1: Trash Capability Contract

**Files:**
- Create: `Sources/ReclaimerCore/TrashExecutionAuthorization.swift`
- Create: `Tests/ReclaimerCoreTests/TrashExecutionAuthorizationTests.swift`
- Modify: `Sources/ReclaimerCore/Models.swift`
- Modify: `Sources/ReclaimerCore/ScanSession.swift`

**Interfaces:**

```swift
public struct FileIdentity: Codable, Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let kind: FileIdentityKind
    public let standardizedPath: String
}

public struct TrashExecutionAuthorization: Codable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let planID: String
    public let dryRunReceiptID: String
    public let findingIDs: [String]
    public let identities: [String: FileIdentity]
    public let issuedAt: Date
    public let expiresAt: Date
}
```

- [ ] Write failing tests proving authorization requires `.reclaimReady`, matching plan and receipt IDs, selected `.trash` actions, `autoSafe`, and satisfied typed conditions.
- [ ] Write failing tests proving `.deleteCache`, `.compress`, `.quarantineHold`, protected rule evidence, and Codex sessions/memories/auth/config are rejected.
- [ ] Write a failing test proving an authorization expires after 15 minutes and can be consumed only once in-process.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter TrashExecutionAuthorizationTests`; expect failures.
- [ ] Implement `FileIdentityReader` using `lstat` and reject symbolic links before capturing identity.
- [ ] Build authorization only from the clean dry-run receipt bound to the current session.
- [ ] Store only the authorization ID in app state; keep the one-time capability in an actor-backed in-memory registry.
- [ ] Run focused and full tests.
- [ ] Commit: `feat: add one-time trash execution authorization`

## Task 2: Final-State Trash Execution

**Files:**
- Modify: `Sources/ReclaimerCore/ReclaimerExecutor.swift`
- Modify: `Sources/ReclaimerCore/OpenFileChecker.swift`
- Create: `Tests/ReclaimerCoreTests/TrashExecutionTests.swift`

**Interfaces:**

```swift
public protocol Trashing: Sendable {
    func trashItem(at url: URL) throws -> URL
}

public struct TrashExecutionResult: Codable, Hashable, Sendable {
    public let originalPath: String
    public let resultingTrashPath: String?
    public let identity: FileIdentity
    public let reclaimedBytes: Int64
}
```

- [ ] Create disposable fixture tests proving successful execution moves only selected items into a fake Trash and records a `done` receipt.
- [ ] Write failing tests for replacement inode, file-to-directory change, symlink replacement, recursive open child, protected reclassification, policy change, expired authorization, and a second use of the same authorization.
- [ ] Write a failing test proving one blocked item does not weaken checks for later items; each action receives its own final classification and open-handle check.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter TrashExecutionTests`; expect current executor skips all filesystem actions.
- [ ] Inject `Trashing` and use `FileManager.trashItem(at:resultingItemURL:)` in production.
- [ ] Immediately before each Trash call: standardize path, `lstat`, compare identity, re-run rule classification, user policy, never-touch guard, recursive open-handle check, and parent/root containment.
- [ ] If any check fails, write a typed skipped receipt; do not retry or fall back to direct deletion.
- [ ] Extend `ExecutionActionReceipt` additively with optional `resultingPath`, `fileIdentity`, and `skipReason` fields using backward-compatible decoding defaults.
- [ ] Run focused/full tests under a temporary fixture root and verify protected fixtures are byte-identical.
- [ ] Commit: `feat: execute recoverable auto-safe trash actions`

## Task 3: Confirmation, Progress, And Recovery UI

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift` (`RecoveryCenterView`)
- Create: `Sources/MacDiskReclaimerApp/TrashConfirmationView.swift`
- Create: `Tests/ReclaimerCoreTests/TrashConfirmationModelTests.swift`

- [ ] Write tests for a confirmation model that lists exact item count, paths using the selected path style, estimated bytes, conditions, and non-claims.
- [ ] Write tests proving the confirmation button is disabled without a current clean dry run and one-time authorization.
- [ ] Replace hardcoded `canExecuteCoreReclaim = false` with typed `TrashExecutionReadiness` from core.
- [ ] Present a sheet titled `Move selected items to Trash`; require an explicit checkbox acknowledging estimates and final checks.
- [ ] Show per-item progress and final Done/Skipped/Error totals without blocking the main actor.
- [ ] Add `Reveal in Trash` and restore guidance for successful receipt entries; do not implement silent automatic restore in this slice.
- [ ] Keep any non-Trash item visibly blocked with the specific reason and Finder/native-tool route.
- [ ] Run focused/full tests and manually exercise a disposable fixture.
- [ ] Commit: `feat: add guided recoverable cleanup confirmation`

## Task 4: Embedded Build Metadata And Runtime Trust Probe

**Files:**
- Create: `Sources/ReclaimerCore/RuntimeReleaseTrustProbe.swift`
- Create: `Tests/ReclaimerCoreTests/RuntimeReleaseTrustProbeTests.swift`
- Modify: `Sources/ReclaimerCore/ReleaseTrustEvidence.swift`
- Modify: `Scripts/package-app.sh`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`

**Interfaces:**

```swift
public struct EmbeddedBuildMetadata: Codable, Hashable, Sendable {
    public let version: String
    public let build: String
    public let sourceCommit: String
    public let buildDate: Date
}

public struct RuntimeReleaseTrustReport: Codable, Hashable, Sendable {
    public let build: EmbeddedBuildMetadata?
    public let signature: RuntimeTrustCheck
    public let gatekeeper: RuntimeTrustCheck
    public let externalManifest: ReleaseTrustEvidence?
    public let claims: [String]
    public let nonClaims: [String]
}
```

- [ ] Write fake-runner tests for unsigned, valid Developer ID, Gatekeeper accepted, unnotarized Developer ID rejected, tool unavailable, and malformed output.
- [ ] Write tests proving prose or an embedded metadata file can never set notarized/stapled state.
- [ ] Generate `Contents/Resources/Ryddi-build.json` before codesigning with version, build, commit, and UTC date.
- [ ] Verify code signature using Security APIs or bounded `/usr/bin/codesign --verify --deep --strict`; verify Gatekeeper using bounded `/usr/sbin/spctl --assess --type execute`.
- [ ] Read an external release manifest only from an explicit environment override, an adjacent release artifact, or the app-managed imported-proof directory; validate version/build before merging it.
- [ ] Make Trust Readiness distinguish `Developer ID signed`, `Gatekeeper accepted`, `Gatekeeper rejected: unnotarized`, and `Unable to verify`.
- [ ] Never claim stapling from `spctl` alone; stapling proof remains a release-manifest/release-gate fact.
- [ ] Run focused/full tests.
- [ ] Commit: `feat: verify installed build trust locally`

## Task 5: Release Artifact And Notary Credential Precedence

**Files:**
- Modify: `Scripts/package-app.sh`
- Modify: `Scripts/notarize-app.sh`
- Modify: `Scripts/release-check.sh`
- Modify: `.github/workflows/release-preview.yml`
- Create: `Tests/ScriptTests/release-trust-smoke.sh`

- [ ] Add shell smoke cases proving complete direct Apple credentials take precedence in CI and `NOTARY_PROFILE` is used only when direct credentials are absent.
- [ ] Add cases for Accepted, In Progress timeout/resume, Invalid with log, missing manifest, failed stapler validation, and Gatekeeper rejection.
- [ ] Stage release output as `dist/Ryddi-v0.3.0/Ryddi.app`, `Ryddi-release-manifest.txt`, and checksums, then zip the directory so proof travels with the app.
- [ ] Make the manifest record exact version/build/commit, app signing identity, notarization submission ID/status, stapler validation, Gatekeeper result, and artifact SHA-256.
- [ ] Ensure `release-check.sh` refuses a final artifact until notarization is Accepted and all validation commands pass.
- [ ] Keep preview builds visibly unsigned and name artifacts `preview`; never publish them under `v0.3.0`.
- [ ] Run `bash -n Scripts/package-app.sh Scripts/notarize-app.sh Scripts/release-check.sh` and the fake-tool smoke.
- [ ] Commit: `build: package verifiable release trust evidence`

## Task 6: Product Wording And Acceptance

**Files:**
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Modify: `docs/RELEASE_CHECKLIST.md`
- Modify: `Scripts/app-e2e-smoke.sh`

- [ ] Rewrite first-screen claims to say Ryddi can move explicitly confirmed auto-safe items to Trash; all other core cleanup remains guidance/manual.
- [ ] Document the final-state checks, recoverability boundary, non-atomic pathname caveat, and APFS estimate caveat.
- [ ] Add a disposable app E2E fixture that scans, plans, dry-runs, confirms Trash, verifies the original path is gone, verifies the Trash result exists, and verifies protected fixtures remain unchanged.
- [ ] Add a negative E2E case that replaces an item after dry-run and expects a skipped identity-mismatch receipt.
- [ ] Run `df -h /System/Volumes/Data`.
- [ ] Run `swift test --scratch-path "$PWD/.build"`.
- [ ] Run `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`.
- [ ] Run script tests, app E2E, `Scripts/release-check.sh`, and `git diff --check`.
- [ ] Do not run the required signed gate unless credentials are available; if run, record exact proof without secrets.
- [ ] Commit: `docs: define recoverable cleanup and release trust boundaries`

## Completion Criteria

- Ryddi can complete one explicit, recoverable cleanup path: current-session auto-safe items moved to Trash.
- Changed, active, protected, stale, or non-Trash items are skipped with typed evidence.
- The installed app reports runtime signature/Gatekeeper facts accurately and does not infer notarization.
- The final release archive carries matching manifest and checksum proof.
- Direct deletion, compression, quarantine-hold mutation, remote cleanup, and scheduled cleanup remain disabled.
