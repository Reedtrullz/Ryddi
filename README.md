# Ryddi

Ryddi is a fast, local-first disk-space cleaner for macOS. It keeps the common path short: scan, select, confirm, Trash.

## Four focused tools

| Tool | What it does |
|---|---|
| Clean | Quickly measures known cache, log, package, and developer-storage roots and groups results by safety. |
| Offload | Copies a large local folder into a provider-managed folder while always preserving the original. |
| Control | Shows large tool-owned storage and offers one recoverable DerivedData action; uncertain operations remain guidance-only. |
| Audit | Inspects a chosen folder for build output, old logs/installers, dependency storage, and content-verified duplicates. |

## Safety model

- Scans start only when you ask.
- Nothing is preselected.
- Only unconditional `autoSafe` Trash/cache rules are directly selectable in Clean.
- Conditional, native-tool, unknown, duplicate, and protected findings remain review-only.
- Cleanup revalidates containment, filesystem identity, symbolic-link state, open-file state, classification, and action immediately before Finder Trash.
- Overlapping scan results are deduplicated.
- Offload never deletes originals or claims cloud upload completion.

## Install

Trusted releases provide a signed, notarized, stapled, Gatekeeper-accepted ZIP. Expand it, move `Ryddi.app` to `/Applications`, then open it. Keep the downloaded checksum beside the archive if you want to verify it with `shasum -a 256 -c`.

Building from source remains available for development. It does not produce public-release trust proof:

Requires macOS 14+ and Swift 6:

```bash
swift build --scratch-path "$PWD/.build"
swift test --scratch-path "$PWD/.build"
swift run --scratch-path "$PWD/.build" RyddiApp
```

## Signed release build

The archive release path fails closed unless a Developer ID Application identity and Apple notary keychain profile are available:

```bash
export APP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="ryddi-notary"
./Scripts/build-release-archive.sh 0.8.2
```

The script signs the app with hardened runtime, submits it to Apple, requires an accepted result, staples and validates the ticket, runs strict signature and Gatekeeper checks, then creates the public ZIP and checksum.

An installer package can additionally be built when a separate Developer ID Installer identity and API-key notarization credentials are available:

```bash
export APP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
export NOTARY_KEY_ID="KEYID"
export NOTARY_ISSUER_ID="ISSUER-UUID"
export NOTARY_KEY_PATH="/secure/path/AuthKey_KEYID.p8"
./Scripts/build-installer.sh 0.8.2
```

The installer script independently verifies strict app signing, Installer signing, notarization, stapling, and Gatekeeper acceptance before producing its checksum. The installer workflow is manual and fails closed when its credentials are absent.

## Privacy

No telemetry and no remote analysis. See [PRIVACY.md](PRIVACY.md) for exact reads, writes, and limits.

MIT licensed. No third-party runtime dependencies.
