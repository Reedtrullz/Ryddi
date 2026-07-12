# Ryddi Storage Truth and Native Maintenance

## Status

Proposed design for the next v0.3 trust-to-action slice. This scope combines the approved Storage Truth work with a narrow native-maintenance lane.

## Problem

The first real cleanup pass exposed three product failures that need to be fixed together:

- APFS clone-backed Chrome code-sign directories can have a large logical `du` total without producing the same physical `df` gain after removal.
- A hard-linked executable can make every sibling clone appear open to a path-by-path `lsof` check, even though one preserved link is enough for the active process.
- Broad scans repeatedly measure large parent trees and can run for many minutes without a useful partial report.

The same pass also identified native cleanup commands with clear ownership boundaries: Docker build cache pruning and npm cache cleaning are safer through their native tools than through raw filesystem deletion. Codex sessions, archives, memories, configuration, auth, and state remain valuable or protected and must not be included in generic cleanup.

## Goals

1. Make storage evidence distinguish logical size, allocated-size estimates, shared clone/hard-link observations, and observed `df` deltas.
2. Make open-file checks group-aware without weakening the default fail-closed behavior for ordinary files and directories.
3. Make broad scans bounded, resumable in meaning, and explicit when coverage or accounting is incomplete.
4. Add precise rule-pack coverage for Chrome code-sign clones, Codex retention lanes, Docker/Colima build cache, npm/npx cache, and named disposable app caches.
5. Add explicit, preview-gated native actions for allowlisted Docker build-cache and npm-cache maintenance using existing receipts and audit history.
6. Keep all destructive work user-confirmed, local, auditable, and unavailable to report-only automation.

## Non-goals

- No raw deletion of Colima VM disks, Docker volumes, containers, browser profiles, Codex sessions, memories, credentials, or app state databases.
- No automatic Chrome process termination, Vivaldi cache deletion while the app is open, or hidden “clean everything” command.
- No promise that logical deletion equals physical APFS reclaim.
- No scheduled native prune or cache deletion in the first implementation slice.
- No new root helper, privileged service, telemetry, remote execution, or cloud analysis.

## Design

### 1. Storage accounting

Add a backward-compatible `StorageAccounting` value carried by scan findings and summaries:

- `logicalBytes`: apparent file content size.
- `allocatedBytes`: filesystem-reported allocation estimate.
- `physicalReclaimStatus`: `unknown`, `estimated`, `sharedCloneBacked`, or `observedDelta`.
- `physicalReclaimBytes`: optional value populated only by a before/after filesystem snapshot or a native tool receipt.
- `deduplicationNote`: optional evidence for hard links, APFS clones, sparse files, or other shared allocation.

Existing `logicalSize` and `allocatedSize` fields remain decoded and encoded for compatibility. New presentation and reclaim calculations use `StorageAccounting`; legacy receipts continue to display their existing values with an explicit accounting caveat.

The executor records `df` before and after every native or filesystem action. It reports observed physical change separately from the finding's logical or allocated estimate. A zero or negative observed delta is valid evidence and must not be rewritten as a successful reclaim estimate.

### 2. Clone-aware open-file checks

Introduce a small filesystem identity helper backed by `lstat`/Darwin metadata for the current volume, file-resource identity, regular-file state, and hard-link count. Extend open-file evidence with:

- a stable open identity key,
- the number of distinct open identities,
- whether the open identity is shared by more than one link,
- whether a preserved link exists outside the candidate path.

`LsofOpenFileChecker` continues to fail closed for ordinary files and directories. For a declared clone-group rule, the checker may report `sharedOpenIdentityOnly` when all open hits resolve to a shared identity and the action preserves at least one verified link. It must still block if any unique descendant is open, the candidate is a symlink, the preservation link cannot be verified, or metadata changes between planning and execution.

Chrome code-sign clones are represented as a grouped review finding rather than twenty independent reclaim promises. The group keeps the active clone, reports duplicate members, and reports reclaim as logical/estimated until an actual `df` delta is observed.

### 3. Bounded scanning

Extend `ScanOptions` with a measurement item budget and coverage metadata. The scanner will:

- use a lower default recursive measurement depth for broad presets;
- measure each scope through one bounded traversal where practical;
- deduplicate hard-linked file identities within a measurement;
- stop measuring a scope when the item budget is exhausted;
- retain findings already collected and add a coverage/measurement-limited evidence record;
- avoid repeating a full deep measurement for every parent and child finding.

The CLI and app show `Complete`, `Bounded`, or `Degraded` coverage next to totals. A bounded scan remains useful for ranking, but its totals are labelled estimates and cannot authorize destructive work without a fresh targeted plan.

### 4. Rule pack updates

Add versioned rules with typed gates and explicit next actions:

- `chrome.code-sign-clone.review`: matches the per-user `X/com.google.Chrome.code_sign_clone` family, preserves active/shared links, requires clone-group open-file evidence and minimum age, and defaults to review or safe-after-condition rather than unattended deletion.
- `codex.desktop-logs.safe-condition`: requires open-file clearance, a three-day retention gate, and final classification; current-day/open logs remain protected from selection.
- `codex.rebuildable-cache.auto`: keeps the existing open-file gate for `~/.codex/cache`, `~/.codex/.tmp`, and Codex app caches; session/archived-session rules remain preserve-by-default.
- `docker.build-cache.native`: surfaces parsed native Docker build-cache reclaimable bytes and recommends the allowlisted native action; it never maps directly to raw VM-disk deletion.
- `package.npm-cache.native`: separates npm cache and inactive npx sandboxes from project `node_modules`, lockfiles, and user config.
- `stremio.cache.safe-condition`: identifies the named Stremio cache leaf without treating the surrounding app-support directory as disposable.

### 5. Native maintenance lane

Reuse the existing `NativeAction`/receipt/audit architecture and add only these command IDs:

- `docker.builder-prune`: runs `docker builder prune --force` after a read-only Docker inventory, with the current Docker context bound into the preview receipt. It does not prune containers, volumes, images, reset Colima, or touch VM files.
- `npm.cache-clean`: runs `npm cache clean --force` after npm cache inspection. It does not remove project dependencies, npm config, credentials, or active npx sandboxes.

Each action follows this sequence:

1. Inspect and record the current tool/context state.
2. Produce a dry-run preview with the exact bounded argv and estimated reclaim.
3. Require explicit user confirmation for perform mode.
4. Revalidate the tool identity, preview digest, selected command ID, and current policy immediately before launch.
5. Capture stdout/stderr previews, exit status, `df` before/after, and skipped/failed state in an audit receipt.
6. Refresh the relevant scan and label the result as observed, estimated, or unverified.

The scheduler and `ReclaimerAgent` remain report/plan-only and must reject these native perform paths.

### 6. App and CLI presentation

- Summary and Review Queues show `Logical`, `Estimated allocation`, and `Observed reclaim` as separate values.
- A clone-group row explains “one active shared link preserved” instead of showing many identical open-file blockers.
- Native tool rows show the command owner, context, preview status, confirmation requirement, and non-claims.
- A bounded scan shows its scope coverage and offers a targeted rescan before any perform action.
- CLI JSON adds optional fields only; existing keys remain stable.

## Testing

### Unit tests

- Hard-linked fixture files share one identity and are counted once for unique accounting.
- An open shared executable does not falsely block removal of verified sibling clone directories when the preserved link remains.
- A unique open descendant, missing preservation link, symlink substitution, changed identity, or changed link count blocks execution.
- Logical/allocated/shared-clone accounting and observed `df` deltas are reported separately.
- Measurement budgets stop traversal, preserve partial findings, and mark coverage as bounded.
- Chrome clone, Codex retention, Docker build-cache, npm cache, npx, and Stremio rules match the intended safety class and typed gates.
- Native command allowlists reject Docker prune/reset/volume commands and arbitrary npm arguments.

### Integration and E2E

- Fixture clone groups produce one grouped finding and a dry-run plan with no mutation.
- Disposable Docker runner fixtures verify preview binding and receipt generation; no real Docker prune runs in tests.
- Disposable npm runner fixtures verify preview binding and receipt generation.
- A large synthetic tree proves bounded scan completion and explicit coverage.
- Packaged app E2E proves Summary, Review Queues, Native Tool preview, confirmation, receipt readback, and no remote/scheduled destructive path.

## Rollout

Implement in four slices: storage/open-file primitives, bounded scanner and rules, native actions and receipts, then UI/CLI presentation and packaged verification. Run focused RED/GREEN tests before each production edit, keep the worktree clean between slices, and do not build until the disk guardrail is checked.

## Acceptance

The slice is complete when a disposable fixture can reproduce the Chrome hard-link case without a false open-file block, a broad scan finishes within its budget with honest coverage, Docker/npm actions are preview-bound and receipt-backed, protected Codex history remains untouched, the full Swift suite and release-check pass, and the app never claims an exact APFS reclaim amount without observed `df` evidence.
