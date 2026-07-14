# Task 6 Report: Correct Known-Hosts Evidence

Date: 2026-07-14

## Status

Implementation and local review complete. Subagent review was unavailable because
the account reached its subagent usage limit, so the controller performed the
task review and reran focused and full verification directly.

## RED Evidence

```bash
swift test --scratch-path "$PWD/.build" --filter KnownHostsInspectorTests
```

Exit `1`: the focused test target could not find `KnownHostsInspector` or
`KnownHostEvidence`. This was the intended pre-implementation failure.

## Implementation

- Added `KnownHostsInspector` and `KnownHostEvidence`.
- Resolves literal and hashed entries through `/usr/bin/ssh-keygen -F` rather
  than parsing host tokens in `known_hosts` directly.
- Uses bracketed host syntax for nondefault ports, including IPv6 hosts.
- Parses at most 512,000 bytes and 128 output lines.
- Accepts only a valid key type followed by valid base64 key bytes.
- Computes the full `SHA256:<base64-without-padding>` fingerprint with
  CryptoKit.
- Distinguishes a clean no-match (`unknown`) from launch, timeout, missing-file,
  or command failures (`unavailable`).
- `RemoteTargetResolver` now uses the inspector for resolved host and port
  evidence.
- Moved the resolver/config/include regression test from the monolithic core
  test file into `KnownHostsInspectorTests.swift`.
- Left `RemoteSSHCommandRunner` unchanged; its `StrictHostKeyChecking=yes`
  contract remains independently tested.

## Verification

```text
KnownHostsInspectorTests: 7 tests, 0 failures
RemoteTarget filter: 7 tests, 0 failures
RemoteSSH filter: 3 tests, 0 failures
Full suite: 596 tests, 1 existing release-only skip, 0 failures
swift build: exit 0
git diff --check: exit 0
```

A disposable local `ssh-keygen` behavior probe also confirmed:

```text
no match: exit 1, empty stdout/stderr
missing known_hosts file: exit 255 with stderr
```

## Local Review

- The runner receives one argument per field, so host and file values are not
  shell-interpreted.
- Hashed host tokens are never decoded or exposed by Ryddi; OpenSSH performs the
  lookup.
- Fingerprints are calculated from decoded key bytes, not from truncated key
  text.
- Malformed or over-bound output cannot produce a `known` result.
- Unknown display evidence does not weaken SSH host-key enforcement.

## Non-Claims

- No live SSH target was contacted.
- No private key, SSH agent, password, Keychain, cleanup, signing, install, CI,
  push, tag, notarization, or release action was performed.
