# Ryddi Ponytail Architecture

The July 2026 rebuild deliberately replaced the large pre-v0.5 architecture with one small product: a fast local scanner, four focused tools, and a native SwiftUI shell.

## Keep the product small

Ryddi should not regain separate subsystems for every cache type, remote-machine cleanup, provider authentication, schedulers, dashboards, policy languages, report stores, or arbitrary native-command execution. A new abstraction must remove more product complexity than it adds.

The intended common path is:

1. User starts a scan.
2. Ryddi quickly measures known roots with bounded concurrency.
3. Nothing is preselected.
4. The user selects an unconditional Safe item.
5. Ryddi revalidates it and moves it to Finder Trash.
6. Ryddi scans again.

Offload is copy-only. Control offers one exact recoverable DerivedData action and otherwise gives guidance. Deep Audit is a focused directory inspection, not a second cleanup framework.

## The irreducible safety kernel

Small does not mean path-only deletion. Before any executable cleanup, Ryddi retains a compact set of gates:

- reviewed-root containment;
- captured device/inode identity;
- symbolic-link refusal;
- bounded open-file check;
- current safety reclassification;
- exact allowed action;
- Finder Trash rather than permanent deletion;
- fail-closed behavior when proof is missing or stale.

These checks are product behavior, not speculative infrastructure. They protect the short workflow from becoming a fast route to data loss.

## Distribution boundary

Release packaging must fail unless the app is signed with its Developer ID Application identity and Apple notarization, stapling, strict signature verification, and Gatekeeper assessment all succeed. Installer packages additionally require a distinct Developer ID Installer identity. A build or test success alone is not release proof.

## Current scale target

Keep production code understandable in one review session and tests focused on destructive boundaries. Prefer a few reusable models and direct platform APIs over framework-like layers. Add features only when they strengthen the scan → understand → explicitly clean loop.
