# Security Policy

Ryddi is a local-first disk reclaim assistant. Security reports are welcome, especially when a bug could expose private paths, credentials, secrets, user data, remote target metadata, or cause unsafe cleanup behavior.

## Supported Versions

Ryddi is pre-1.0. Security fixes target the current `main` branch and the active release branch when one exists. Unsigned developer preview artifacts are testing builds, not trusted release proof.

## Private Reporting

Use GitHub Security Advisories for private reports:

https://github.com/Reedtrullz/Ryddi/security/advisories/new

Use a private advisory for:

- credential, token, private-key, or secret exposure;
- cleanup execution that can delete protected files without the documented gates;
- sandbox, permission, or Full Disk Access behavior that is misleading;
- SSH/remote-target behavior that can run unintended commands or leak target identity;
- release trust bugs where unsigned, unstapled, unnotarized, or Gatekeeper-rejected builds appear trusted;
- report redaction failures involving private paths, hostnames, project names, or user-entered reasons.

For public bugs that do not expose sensitive information, use the issue templates.

## What To Include

- Ryddi version, commit SHA, or artifact name.
- macOS version and install method.
- Redacted command output, report snippets, receipts, manifests, or screenshots.
- Whether Full Disk Access was granted, if relevant.
- For release trust issues, include `dist/Ryddi-release-manifest.txt` with secrets removed.
- For remote-target issues, redact hostnames, usernames, IPs, paths, Docker object names, and project names unless they are essential.

Do not include passwords, API keys, private keys, app-specific passwords, notary credentials, SSH private keys, tokens, or unredacted customer data.

## Trust Boundaries

Ryddi should not:

- upload paths, reports, scans, or remote command output;
- store SSH private keys, passwords, sudo passwords, or app-specific passwords;
- run remote destructive cleanup in the first Remote Targets release;
- treat browser profiles, VM/container disks, credentials, user documents, photos, music projects, GarageBand/Logic assets, app state databases, Codex sessions/memories/config/auth, or unknown user data as auto-safe;
- claim signed/notarized release trust unless typed manifest evidence proves Developer ID signing, Hardened Runtime, Apple notarization acceptance, stapling, Gatekeeper acceptance, and strict codesign verification.

## Response Expectations

This is an early project. I will aim to acknowledge private reports within a few days, prioritize safety-impacting cleanup and privacy issues first, and keep public release claims conservative until fixes are verified.
