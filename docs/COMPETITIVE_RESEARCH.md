# Ryddi Competitive Research Snapshot

Date: 2026-07-05

This is a product research snapshot for Ryddi, based on current public product pages, GitHub projects, Apple platform guidance, and the MVP scope in this repository. It is not exhaustive, but it is enough to set feature expectations for a credible first public release.

## Executive Takeaways

Ryddi should be useful for general Mac cleanup, but it should not look like a generic one-click optimizer. That market is crowded, trust-sensitive, and often bundled with performance, malware, RAM, and update claims that are not central to Ryddi's thesis.

The stronger position is:

> DaisyDisk-level space understanding + practical general Mac cleanup review + DevCleaner-style developer specificity + Hazel-like auditability, with explicit safety classes and no mystery cleanup.

Users will still expect the basics from mature disk tools:

- a visual or at least highly scannable map of where space is going;
- clear scan modes for general Mac cleanup, developer cleanup, and combined review;
- top offenders ranked by actual reclaim value;
- file preview, reveal-in-Finder, open-in-Terminal, and copy-path actions;
- Trash-first behavior for user-visible files;
- clear Full Disk Access onboarding and degraded-mode labeling;
- app uninstaller or at least app-support leftovers guidance;
- large/old file review plus conservative duplicate review;
- scheduled maintenance that reports first;
- signed/notarized builds and a strong privacy statement.

Ryddi's defensible differentiation is the evidence layer: rule matches, why a path is safe or unsafe, what would happen if removed, native-tool recommendations, active-file checks, dry-run receipts, and local audit history.

## Competitor Lanes

| Lane | Examples | What They Promise | Expected Features | Ryddi Implication |
| --- | --- | --- | --- | --- |
| Broad cleaner suites | CleanMyMac, Cleaner One Pro, BuhoCleaner, Sensei, MacCleaner Pro | Simple cleanup, optimization, app management, sometimes malware/privacy/performance | Smart scan, junk cleanup, big files, duplicates, app uninstall, menu bar status, reminders, subscriptions, polished onboarding | Do not compete on fake speed/optimizer breadth. Borrow polish, onboarding, menu bar/reporting, and clear packaging. |
| Visual disk analyzers | DaisyDisk, GrandPerspective, SquirrelDisk, DiskPilot, Spacie, OmniDiskSweeper | Help users understand what uses space and decide what to remove | Treemap/sunburst/list, drill-down, Quick Look, Finder reveal, Trash/drop zone, all volumes, physical-size correctness | Ryddi needs a visual/scannable evidence map. Even a strong rules engine will feel incomplete without this. |
| App uninstallers | AppCleaner, Pearcleaner, Nektony App Cleaner & Uninstaller, Hazel App Sweep | Remove apps plus related support files | App inventory, related files, leftovers, launch agents, containers, bulk uninstall, deselection, Trash | Ryddi now has review-only Apps & Leftovers plus selected-app preview and app-bundle Trash execution. Keep automatic leftover deletion, bulk uninstall, and smart related-file selection out of the cleanup plan until ownership evidence is stronger. |
| Developer cleaners | DevCleaner, Spacie smart categories, macOS dev-cache cleaners, Megacleaner-style projects | Reclaim Xcode, package-manager, container, and build cache bloat | Xcode DerivedData/Archives/DeviceSupport, simulators, Homebrew, npm/pnpm/yarn, Gradle, Maven, Docker, node_modules | This is Ryddi's beachhead. Go deeper and safer here than the broad suites. |
| Automation/rules | Hazel | Keep folders tidy over time with user-defined rules | Folder watchers, schedules, Trash management, app sweep, rule preview, notifications | Ryddi automation should be report-first. Allow unattended cleanup only for tight, explainable allowlists. |
| Duplicate specialists | Gemini 2, Nektony Duplicate File Finder | Find duplicate/similar files and prevent future clutter | Smart selection, Photos/Music awareness, external drives, duplicate monitoring | Ryddi now has a conservative review-only duplicate slice. Do not compete with specialist smart selection, similar-photo matching, or library management until the safety model is much deeper. |

## Notable Product Signals

### CleanMyMac

[CleanMyMac](https://macpaw.com/cleanmymac) positions itself as an all-in-one cleaner and maintenance app covering junk, duplicates, malware, and performance issues. It emphasizes Smart Care, broad polish, a huge installed base, and Apple notarization.

Ryddi should learn from the trust packaging: notarization, clear privacy, high-quality screenshots, and an understandable first-run experience. It should not inherit broad claims like "optimize everything" unless Ryddi can prove them locally and safely.

### DaisyDisk

[DaisyDisk](https://daisydiskapp.com/) is the clearest benchmark for disk understanding. It emphasizes fast scans, hidden-space visibility, admin scanning, user-decided deletion, and safeguards around system files. It also discusses physical-size correctness, hard links, APFS clones, snapshots, cloud storage, and privacy.

Ryddi should treat APFS accounting as a first-class feature, not a footnote. Users with developer machines often see confusing gaps between logical size, allocated size, purgeable space, VM images, local snapshots, and cloud placeholders.

### GrandPerspective and OmniDiskSweeper

[GrandPerspective](https://grandperspectiv.sourceforge.net/) and [OmniDiskSweeper](https://www.omnigroup.com/more) show that a simple, durable disk analyzer can remain useful for years. Their core strength is directness: show what is large, let the user inspect it, reveal it, and delete or trash it.

Ryddi needs this plain mode alongside rule-based cleanup. A user should always be able to answer: "What are my largest folders and files right now?"

### SquirrelDisk, DiskPilot, and Spacie

[SquirrelDisk](https://www.squirreldisk.com/) emphasizes spatial navigation, internal/external drives, and direct removal. [DiskPilot](https://mhkasif.github.io/DiskPilot/) emphasizes open-source, local/no telemetry, multi-platform scanning, allocated usage, hardlink deduplication, multiple views, and keyboard-first workflows. [Spacie](https://github.com/AlexGladkov/Spacie) is especially relevant: it combines native macOS UI, treemap/sunburst, APFS-aware accounting, large/old/duplicate files, smart categories, FSEvents-backed cache, staged deletion, SIP blocklists, dotfile warnings, and graceful behavior without Full Disk Access.

Spacie is the closest open-source reference for "modern native macOS disk analyzer plus smart categories." Ryddi's differentiator must be deeper safety/explanation, developer/AI-agent rules, receipts, and command-aware cleanup.

### AppCleaner, Pearcleaner, and Nektony

[AppCleaner](https://freemacsoft.net/appcleaner/) set the expectation that uninstalling an app includes related files. [Pearcleaner](https://github.com/alienator88/Pearcleaner) shows strong open-source interest in this category. [Nektony App Cleaner & Uninstaller](https://nektony.com/mac-app-cleaner) has expanded the category into app updates, startup items, extensions, leftovers, and app security signals.

Ryddi should not auto-delete app support data in v1. But it should eventually detect app leftovers and separate:

- installed app support data;
- support data for removed apps;
- high-value user assets;
- recoverable caches/logs;
- launch agents/background items;
- dangerous state databases.

### DevCleaner

[DevCleaner](https://github.com/vashpan/xcode-dev-cleaner) is a focused Xcode cleanup app. It treats Device Support, Archives, DerivedData, documentation cache, simulator logs, and old logs as distinct categories with different risk profiles.

This is exactly the right shape for Ryddi rule packs: a category is not just a folder path; it needs age, version, owner, regeneration story, and "what breaks if removed."

### Hazel

[Hazel](https://www.noodlesoft.com/) and its [manual](https://www.noodlesoft.com/manual/hazel/hazel-overview/) set expectations for trusted automation: user-defined rules, folder watching, moving/renaming/tagging/archiving, Trash management, and App Sweep.

Ryddi should borrow the rule-preview and audit mindset, not broad unattended deletion. Scheduled Ryddi should start as "scan and report." Later, allow "clean only these exact auto-safe classes older than N days."

### Apple Platform Requirements

Apple's privacy guidance makes Full Disk Access and Files & Folders access explicit user-controlled permissions: [Apple Privacy & Security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac). Apple's launchd guidance distinguishes per-user agents for background work: [Creating launchd jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html). `FileManager.trashItem` provides the platform-native Trash path for uncertain user-visible removals: [FileManager trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem%28at%3Aresultingitemurl%3A%29).

Ryddi should make permission state visible, avoid root/helper behavior in v1, use a per-user LaunchAgent for scheduled reports, and prefer Trash or an app-managed holding area over direct deletion except for allowlisted reproducible caches.

## Feature Expectation Matrix

| Feature | Market Expectation | Ryddi Status | Recommendation |
| --- | --- | --- | --- |
| Scan mode selection | Expected from tools that span simple cleanup and expert/developer use | Exists/partial | `ScanScopePreset`, `ScopeTemplateCatalog`, `SavedScopeSetStore`, `reclaimer scopes`, `reclaimer scopes templates`, `reclaimer scopes saved`, app Scan Scope, and app Scope Sets now separate Developer, General Mac, All, guided templates, explicit custom roots, saved per-user scope sets, and report-only scheduling against those scopes. Future work should add richer template editing and onboarding polish. |
| Top offenders overview | Baseline for all disk analyzers | Exists/partial | `TopOffenderTable`, CLI overview `--sort/--group`, and app Top Offenders now show path, size, category, safety, age, action, owner, confidence, and conservative reclaim estimate. Future work should add richer row filtering and visual table/detail transitions. |
| Owner/app/tool grouping | Expected from app uninstallers and increasingly important for developer-cleaner trust | Exists/partial | `ScanOverview.ownerSummaries`, CLI overview, app Top Owners, and evidence reports now group non-overlapping findings by owner hints or category fallback. Future work should deepen app identity confidence. |
| Rule transparency | Rare in broad cleaners but important for open-source trust | Exists/partial | `reclaimer rules`, app Rule Catalog, and `RuleCatalogReport` expose bundled and opt-in user rule sources, safety/action/category summaries, match hints, conditions, recovery notes, and non-claims. `reclaimer rules user preview/import/export` and app Rule Catalog preview/import/export add local user rule-pack review with validation that rejects cleanup-granting imports. Future work should add shared rule-pack signing and richer provenance review. |
| Visual disk map | Expected by DaisyDisk, GrandPerspective, SquirrelDisk, DiskPilot, Spacie users | Exists/partial | Ryddi now has non-overlapping proportional category map nodes plus bounded hierarchical drill-down via `reclaimer drilldown` and app Disk Drilldown. A full treemap/sunburst with richer spatial interaction remains future work. |
| Evidence details | Rare in broad cleaners, central to Ryddi | Exists/partial | `FindingExplanationReport`, CLI `reclaimer explain`, and app detail view now answer what the path is, why it matched, risk, cleanup permission, exact action semantics, removal effect, recovery path, conditions, next steps, and non-claims. Future work should add richer visual transitions from maps/tables into the same explanation surface. |
| Review queues | Expected from cleaners that need to turn scan output into action | Exists/partial | `ReviewQueueReport`, `ReviewQueueDetailReport`, CLI `reclaimer queues --queue`, and app Review Queues now separate Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Personal/App Assets, and Unknown findings with counts, bytes, sample rows, single-queue reports, row-to-detail navigation, and non-claims. Future work should add saved queue filters and bulk queue actions. |
| Dry-run plan | Strong differentiator | Partial | Keep as default. Receipt exports now add action counts and skipped/error visibility; plan diff remains future work. |
| Exportable reports | Expected in trust-sensitive admin tools, useful for before/after review | Exists/partial | Markdown evidence reports, growth reports, reclaim plan reports, and receipt reports now capture scan coverage, saved-snapshot deltas, proposed actions, blocked/review items, policy, accounting notes, action counts, skipped/errors, before/after free-space fields, path privacy controls, and non-claims. Future work should add richer trend charts and visual comparisons. |
| Active-file guard | Strong safety differentiator | Exists/partial | Active-handle review now surfaces open/process summaries and failed checks for cleanup candidates. Future work should add richer app-name mapping and notification flows. |
| Downloads and installer review | Expected in general Mac cleaners because old DMGs/PKGs/ZIPs are common visible bloat | Exists/partial | `reclaimer downloads` and app Downloads Review now report old downloads, installers, archives, app bundles, kind summaries, largest items, Finder guidance, and local audit records without moving or deleting files. Future work should add saved Finder-style filters and user-controlled archive/Trash workflows. |
| Browser cache review | Expected in broad cleaners, high-risk if profiles are blurred with cache | Exists/partial | `reclaimer browsers` and app Browser Cache Review now report browser cache roots, browser/cache-kind summaries, largest cache items, protected profile roots, quit-first guidance, and local audit records without modifying browser cache or profile state. Future work should add richer app-running detection and browser-specific cleanup guidance. |
| Package cache review | Expected for developer cleaners and useful in broad cache review | Exists/partial | `reclaimer packages` and app Package Cache Review now report Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots with protected config/auth paths and native cleanup guidance, without modifying package-manager state. Future work should add richer tool-installed detection and per-manager command UX. |
| Device backup review | Expected in general Mac cleaners because local iPhone/iPad backups can be large but valuable | Exists/partial | `reclaimer device-backups` and app Device Backups Review now report MobileSync backup roots, size, age, encryption, parsed/missing metadata, Apple/Finder guidance, and local audit records without modifying backups. Future work should add richer Finder/Storage-management deep links where macOS allows it. |
| Trash-first cleanup | Expected safety behavior | Exists/partial | Use Trash for uncertain/user-visible data. Direct delete only for allowlisted caches. `reclaimer trash` and app Trash Review now report current user Trash size, largest items, permission state, Finder guidance, and local audit records without emptying Trash. Future work should add richer Finder Trash integration where macOS allows it. |
| App-managed holding area | Strong differentiator | Exists/partial | Holding metadata, CLI restore/expire, app Holding Area, and Recovery Center restore controls exist. Future work should add expiration reminders and richer restore conflict handling. |
| Recovery and undo guidance | Expected when cleaners offer destructive actions; often vague in broad suites | Exists/partial | `RecoveryCenter`, `reclaimer recovery`, and app Recovery Center distinguish app-held restores from Finder Trash review, dry-run/skipped no-ops, native-tool guidance, and non-recoverable direct deletes. Future work should add richer Trash integration where macOS allows it. |
| User exclusions/protections | Expected from Hazel-like automation and serious cleanup tools | Exists/partial | Local path policy now supports scan exclusions, cleanup protections, versioned JSON export, merge import, and explicit replace import. User rule packs add custom review/preserve/never-touch classification signals, disabled by default unless explicitly included in a CLI scan or the app User Rules scan toggle is on. Future work should add richer rule conditions and shared rule-pack signing/provenance UX. |
| Full Disk Access onboarding | Expected for any serious disk scanner | Exists/partial | Permission advisor and walkthrough now report coverage level, denied/missing scopes, Full Disk Access actions, rescan/report-only commands, affected scopes, exportable guidance, and non-claims; screenshots/GIFs remain future release polish. |
| APFS physical accounting | Expected by expert users; DaisyDisk/Spacie benchmark this | Exists/partial | Logical/allocated notes and non-overlap accounting exist; clone/hardlink/purgeable/snapshot depth remains future work. |
| Large file review | Baseline | Exists/partial | `LargeOldReviewReport`, CLI `reclaimer large`, and app Large & Old Files now expose large/old rows with signal/category/safety summaries, concrete child-row preference, row actions, and non-claims. `ArchiveReviewReport`, CLI `reclaimer archive`, and the app Archive Candidates panel turn those rows into keep/archive/Trash-review/cleanup-plan/manual/blocked checklists without moving files. Future work should add richer saved filters and visual transitions into evidence detail. |
| Duplicate finder | Common suite feature | Experimental review-only slice | Keep local hashing explicit and bounded. No smart selection, no automatic deletion, no Photos/Music/iCloud duplicate management. |
| App uninstaller | Common suite/app-cleaner feature | Exists/partial | Apps & Leftovers plus `reclaimer apps uninstall-preview` now separate the app bundle Trash preview from related support-file review. `reclaimer apps uninstall --dry-run/--yes` can move only the selected app bundle to Trash after receipt, open-file, user-policy, and final protection checks. Bulk deletion, vendor uninstallers, and smart leftover deletion remain future work. |
| Developer cache packs | Ryddi beachhead | Partial | Go deeper on Xcode, SwiftPM, node_modules, JetBrains, VS Code, Android/Flutter, Docker/Colima. |
| Docker/Colima cleanup | Risky but important for target user | Exists/partial | Native-tool preview receipts describe inspect/prune/reset commands, risk, and non-claims; read-only inventory adds Docker storage buckets, objects, Colima profiles, and command outcomes; native command execution receipts now exist for one selected non-destructive/non-placeholder command at a time. Future work is deeper confirmation UX for destructive Docker/Colima native prune flows. Never raw-delete VM disks automatically. |
| Codex/AI-agent cleanup | Ryddi-specific differentiator | Exists/partial | `reclaimer agents`, `DefaultScopes.aiAgentStorage`, and app AI Agent Storage now review Codex, Claude, Cursor, Windsurf, and Ollama roots with cache/history/protected/manual buckets. `reclaimer agents retention` and the app retention report add conservative/balanced/aggressive report-only guidance for cleanup-plan, compression-review, keep, and protect recommendations. Future work should add saved trend reports, per-tool profile tuning, and explicit user-controlled compression flows. |
| Scheduled maintenance | Expected from automation tools | Exists/partial | `ScheduleConfiguration`, `schedule preview`, and `schedule install` now generate XML-safe report-only LaunchAgent plists for Developer/General/All presets, built-in templates, or saved scope sets. Only allow unattended cleanup for explicit allowlisted classes in a future release. |
| Menu bar/status item | Common in Sensei/Cleaner One/BuhoCleaner | Exists/partial | Disk-pressure status and report-only scan controls exist; reminders/notifications remain future work. |
| Notarized releases | Expected for trust | Planned | Add signed/notarized release process and GitHub release artifacts. |
| CI/test badge | Expected for open-source trust | Exists | GitHub Actions runs Swift build/test on `main`. |
| Privacy page | Expected for cleaners | Exists | `PRIVACY.md` documents no telemetry, no uploads, local receipts, duplicate hashing, and app-review reads. |

## Suggested Ryddi Roadmap

### Release Credibility

1. Add GitHub Actions CI for Swift build/test.
2. Add signed/notarized release workflow notes and a first downloadable artifact.
3. Add `PRIVACY.md` and a short "What Ryddi never touches" section.
4. Add screenshots or a short GIF of the app and CLI.
5. Add issue templates for false positives, new rule packs, and safety concerns.

### Product Core

1. Make scan modes feel first-class: General Mac, Developer, All, custom paths, guided templates, saved per-user scope sets, and scope-aware scheduled reports now exist; next depth is richer template editing and onboarding polish.
2. Add drill-down detail pages that explain evidence and recovery.
3. Shared review queues now mirror user intent and support queue-specific reports plus app row-to-detail navigation; next depth is saved queue filters and bulk actions.
4. Large-file and old-file review mode plus archive-candidate checklists now exist; Trash Review reports current Trash contents without emptying; Device Backups Review reports local MobileSync backups without modifying them. Next depth is saved filters, evidence-detail transitions, user-controlled archive/Trash workflows, and richer Apple/Finder backup-management guidance.
5. Add Finder, Quick Look, Terminal, copy-path, and exclude actions.
6. Add local protection/exclusion management so users can tune noisy or sensitive paths.
7. Add richer top-offender row filtering and visual transitions from table row to evidence detail.

### Safety Depth

1. Permission advisor and first-run walkthrough now cover readable/denied/missing scopes, Full Disk Access guidance, rescan/report-only commands, affected scopes, exportable guidance, and non-claims. Add screenshots/GIFs for release polish.
2. Add APFS size model: logical, allocated, clone/hardlink caveat, purgeable/snapshot explanation.
3. Add final re-stat and reclassification immediately before action.
4. Recovery Center now covers app-held restores and receipt-based guidance for Trash, dry-run, skipped, native-tool, and direct-delete actions. Add richer Trash integration where macOS allows it.
5. Evidence, growth, plan, and receipt report export exist for scan, saved-snapshot comparison, proposed cleanup, and execution review, including path privacy controls. Add richer trend charts and visual comparisons.

### Developer/AI Niche

1. AI-agent storage review now separates Codex, Claude, Cursor, Windsurf, and Ollama cache/log churn from valuable history and protected state. Next: saved trend reports, per-tool retention profiles, compression workflows, and deeper non-Codex rule packs.
2. Container rule pack: Docker/Colima inventory, volumes/images/build cache, native prune guidance, VM disk warnings. Preview receipts, read-only live inventory, and one-command non-destructive native execution receipts exist; future work should add deeper confirmation UX for destructive Docker/Colima native prune flows.
3. Xcode rule pack: DerivedData, ModuleCache, DeviceSupport, Archives, simulator logs, old runtimes with version/age gates.
4. Package manager review now has a report-only cache inventory for Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright, with protected config/auth paths and native cleanup guidance. Next: richer tool-installed detection, per-manager command UX, and project-local dependency review.
5. IDE/mobile packs: JetBrains, VS Code/Cursor/Windsurf, Android Studio/Gradle, Flutter, Playwright browsers.

### Later Modules

1. Apps & Leftovers depth: explicit app-bundle Trash execution with confirmation now exists; next depth is deselection, launch-agent/background-item detail, and stronger orphan ownership evidence before any related-file cleanup.
2. Duplicate depth: partial-hash prefiltering, volume/hardlink accounting, external-drive flows, and richer review UX while keeping Photos/Music/iCloud protections.
3. Folder automation: Hazel-like custom report rules, not arbitrary delete rules.
4. Menu bar assistant depth: scan reminders, notification summaries, and richer scheduled-scan status.
5. Growth history: local category/scope/safety snapshot deltas and Markdown growth reports exist; richer trend charts and longer history views remain future work.

## Product Principles To Keep

- Never market "speed boost" unless the app measures and proves a specific local effect.
- Never make "clean all" the hero.
- General Mac cleanup is in scope, but broad personal roots should remain review-first unless a specific rule proves low risk.
- Never raw-delete VM disks, browser profiles, Photos libraries, Music libraries, GarageBand/Logic assets, Codex memories, credentials, or unknown app state.
- Treat user documents and creative assets as preserve-by-default even if large.
- Prefer native cleanup commands for tools that own complex state.
- Make every destructive action reviewable, dry-runnable, and receipted.
- Use privacy as a product feature: local-only scan, no path upload, no telemetry by default.

## First Public Release Bar

The first public release should have:

- CLI commands for scan, plan, explain, dry-run, execute, holding, and schedule.
- SwiftUI app with overview, visual map/drill-down, queues, large/old review, details, plan builder, and audit history.
- Rules for Codex, Docker/Colima, Xcode, package caches, browser caches, temp dirs, and large-file review.
- Dry-run receipts and local audit history.
- Recovery Center for app-held restores and receipt-based guidance.
- Trash/holding-area cleanup for safe selections.
- Active-file checks before action.
- Full Disk Access guidance and degraded-mode labels.
- Review-only duplicate grouping with local hashes and no automatic cleanup.
- Menu bar disk-pressure status with report-only scan shortcut.
- Safety tests for never-touch paths.
- GitHub CI.
- Privacy documentation.
- A signed/notarized direct-distribution build or a clearly labeled unsigned developer preview.

## Source Links

- [CleanMyMac](https://macpaw.com/cleanmymac)
- [Cleaner One Pro](https://www.trendmicro.com/en_us/forHome/products/cleaner-one-mac.html)
- [BuhoCleaner](https://www.drbuho.com/buhocleaner)
- [Sensei](https://cindori.com/sensei)
- [DaisyDisk](https://daisydiskapp.com/)
- [GrandPerspective](https://grandperspectiv.sourceforge.net/)
- [OmniDiskSweeper](https://www.omnigroup.com/more)
- [SquirrelDisk](https://www.squirreldisk.com/)
- [DiskPilot](https://mhkasif.github.io/DiskPilot/)
- [Spacie](https://github.com/AlexGladkov/Spacie)
- [AppCleaner](https://freemacsoft.net/appcleaner/)
- [Pearcleaner](https://github.com/alienator88/Pearcleaner)
- [Nektony App Cleaner & Uninstaller](https://nektony.com/mac-app-cleaner)
- [Gemini 2](https://macpaw.com/gemini)
- [DevCleaner](https://github.com/vashpan/xcode-dev-cleaner)
- [Hazel](https://www.noodlesoft.com/)
- [Hazel manual](https://www.noodlesoft.com/manual/hazel/hazel-overview/)
- [Apple privacy and security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)
- [Apple launchd jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [FileManager trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem%28at%3Aresultingitemurl%3A%29)
