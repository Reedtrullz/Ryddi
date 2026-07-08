# Ryddi Screenshot Checklist

This file tracks the public screenshots and short clips needed before a polished release page. Do not use screenshots that expose private paths, hostnames, project names, usernames, remote targets, receipts, or customer data.

## Required For v0.2 Public Release

- Summary screen after a scan, showing the Next Safe Action, disk status, trust readiness, and review queues.
- Review Queues screen showing Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Personal/App Assets, and Unknown.
- Package Cache review showing preview-only native command guidance.
- AI Agent Storage review showing cache cleanup candidates, valuable history, and protected state.
- Remote Targets report showing degraded/partial evidence and explicit no-cleanup non-claims.
- Release Trust proof showing `reclaimer release-trust --json --manifest dist/Ryddi-release-manifest.txt` for a signed/notarized manifest.

## Capture Rules

- Use a disposable fixture or redacted report data.
- Prefer dark and light mode pairs for the Summary and Review Queues screens.
- Keep the window wide enough that text does not truncate in the primary proof area.
- Do not show real SSH aliases, known-host fingerprints, home paths, app-specific passwords, Apple IDs, bundle signing identities, or notary submission details unless they are test fixtures.
- Re-run `git diff --check` after adding image assets.

## Candidate Asset Paths

- `docs/assets/screenshots/summary-next-safe-action.png`
- `docs/assets/screenshots/review-queues.png`
- `docs/assets/screenshots/package-cache-preview.png`
- `docs/assets/screenshots/ai-agent-retention.png`
- `docs/assets/screenshots/remote-targets-report.png`
- `docs/assets/screenshots/release-trust-proof.png`

## Current Non-claims

- No screenshot assets are committed yet.
- This checklist is not visual proof that the app has been smoke-tested after the latest UI changes.
- Public release copy should not imply signed/notarized trust until the typed release manifest reports `stapledAndAccepted`.
