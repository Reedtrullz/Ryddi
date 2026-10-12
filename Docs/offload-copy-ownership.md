# Offload copy ownership

Offload retains its reviewed folder allowlist, copy-only flow and allocated-size warning. The core writer opens and checks source/provider identities, reserves a unique private staging directory relative to the provider descriptor, and copies into that directory's current checked path. Copying into the source itself is refused.

Foundation byte copying remains path-based; it is not a filesystem snapshot. Publication uses exclusive descriptor-relative rename, followed by payload/provider identity verification. A final-name collision preserves the existing destination. Only the captured, empty staging directory is removed through its pinned parent; there is no recursive failure cleanup.

Failed payloads are retained intentionally. The UI error includes the current location obtained from the held descriptor and the failure reason, or explicitly says that an external change made the location unknown. Review that location before any separate manual recovery or disposal. Originals are kept. Retention can consume disk space after failures.

Local fixtures cover files, directories, partial-copy failure, final-name collision, payload/staging replacement, provider rename/symlink redirection and rejected overlapping roots. No fixture uses real cloud folders or originals. These checks do not certify content integrity, copy-time source immutability, remote synchronization, backup acceptance or adversarial same-user namespace changes.
