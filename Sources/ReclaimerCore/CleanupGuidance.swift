import Foundation

public enum CleanupGuidance {
    public static func commands(for finding: Finding) -> [String] {
        if let receipt = NativeToolGuidance.receipt(for: finding) {
            return receipt.commands.map { "\($0.command) - \($0.purpose)" }
        }
        return legacyGuidance(for: finding)
    }

    private static func legacyGuidance(for finding: Finding) -> [String] {
        let path = finding.path.lowercased()
        guard finding.actionKind == .openGuidance else {
            return []
        }

        if path.contains("/.colima") {
            return [
                "Inspect first: colima list && docker system df",
                "Review project dependency before reset: colima stop <profile>",
                "Destructive only after backup/review: colima delete <profile>"
            ]
        }

        if path.contains("/.docker") || path.contains("/library/containers/com.docker.docker") || path.contains("docker.raw") {
            return [
                "Inspect first: docker system df",
                "Reclaim unused images/build cache after review: docker system prune",
                "Include volumes only after confirming they do not hold unique data: docker system prune --volumes"
            ]
        }

        if path.contains("/library/caches/homebrew") {
            return [
                "Preview Homebrew cleanup: brew cleanup -n",
                "Run Homebrew cleanup: brew cleanup"
            ]
        }

        if path.contains("/.npm") {
            return [
                "Verify npm cache: npm cache verify",
                "Clean npm cache only when needed: npm cache clean --force"
            ]
        }

        if path.contains("/library/pnpm/store") {
            return [
                "Prune unreferenced pnpm packages: pnpm store prune"
            ]
        }

        if path.contains("/library/caches/yarn") {
            return [
                "Clean Yarn cache after active installs finish: yarn cache clean"
            ]
        }

        if path.contains("/.cargo/registry") || path.contains("/.cargo/git") {
            return [
                "Prefer project-local cleanup first: cargo clean",
                "Review Cargo registry/git cache manually before deleting shared downloads."
            ]
        }

        if path.contains("/go/pkg/mod") {
            return [
                "Clean Go module cache after active builds finish: go clean -modcache"
            ]
        }

        if path.contains("/.gradle/caches") {
            return [
                "Stop Gradle daemons first: gradle --stop",
                "Review shared Gradle cache before removal; it will be re-downloaded."
            ]
        }

        if path.contains("/.m2/repository") {
            return [
                "Review Maven local repository before removal; dependencies will be re-downloaded when online."
            ]
        }

        if path.contains("/library/caches/org.swift.swiftpm") || path.contains("/.swiftpm/cache") || path.contains("/.build/") {
            return [
                "Prefer project-local cleanup first: swift package clean",
                "For build loops, keep scratch bounded with: swift build --scratch-path .build"
            ]
        }

        if path.contains("/library/caches/cocoapods") {
            return [
                "Clean CocoaPods cache selectively: pod cache clean --all"
            ]
        }

        if path.contains("/node_modules") {
            return [
                "Review the project lockfile and package manager before removal.",
                "Reinstall with the project command, for example: npm ci, pnpm install, or yarn install"
            ]
        }

        if path.contains("/library/caches/ms-playwright") {
            return [
                "Reinstall browser binaries later with: npx playwright install"
            ]
        }

        if path.contains("/library/application support/code")
            || path.contains("/library/application support/cursor")
            || path.contains("/library/application support/windsurf")
            || path.contains("/library/caches/jetbrains")
            || path.contains("/library/logs/jetbrains") {
            return [
                "Quit the editor first.",
                "Remove only cache/log folders; keep settings, keybindings, extensions, projects, and workspace state unless reviewed."
            ]
        }

        if path.contains("/library/caches/google/androidstudio")
            || path.contains("/.pub-cache") {
            return [
                "Prefer native cleanup after active builds finish.",
                "Flutter packages can be repaired with: flutter pub get"
            ]
        }

        if path.contains("/library/android/sdk") || path.contains("/.android/avd") {
            return [
                "Review installed SDK platforms and emulator images in Android Studio or sdkmanager.",
                "Remove only versions/images you know projects no longer target."
            ]
        }

        if path.contains("/library/developer/xcode/archives") || path.contains("/library/developer/xcode/ios devicesupport") || path.contains("/library/developer/coresimulator") {
            return [
                "Review Xcode archives/device support by version before removal.",
                "For simulators, prefer Xcode/Simulator device management or xcrun simctl delete unavailable."
            ]
        }

        return []
    }
}

public enum NativeToolGuidance {
    public static let reportNonClaims = [
        "No native cleanup command was executed by this report.",
        "Ryddi does not raw-delete VM disks, package stores, or tool-owned state for native-tool findings.",
        "Commands that reclaim space must be run by the user after reviewing project dependencies and backups.",
        "Expected reclaim depends on each native tool and may not equal the scanned folder size."
    ]

    public static func report(for findings: [Finding], ruleVersion: String) -> NativeToolReport {
        let receipts = deduplicateNestedReceipts(findings.compactMap { receipt(for: $0) })
        return NativeToolReport(
            ruleVersion: ruleVersion,
            receipts: receipts,
            nonClaims: reportNonClaims
        )
    }

    public static func receipt(for finding: Finding) -> NativeToolReceipt? {
        guard finding.actionKind == .nativeToolCommand else {
            return nil
        }
        let commands = commandsForNativeFinding(finding)
        guard !commands.isEmpty else {
            return nil
        }
        return NativeToolReceipt(
            findingPath: finding.path,
            displayName: finding.displayName,
            category: finding.primaryCategory,
            allocatedSize: finding.allocatedSize,
            safetyClass: finding.safetyClass,
            actionKind: finding.actionKind,
            status: "preview-only",
            message: "Native-tool cleanup is previewed for manual review; Ryddi will not execute these commands automatically.",
            commands: commands,
            nonClaims: reportNonClaims
        )
    }

    private static func commandsForNativeFinding(_ finding: Finding) -> [NativeToolCommand] {
        let path = finding.path.lowercased()

        if path.contains("/.colima") {
            return [
                command("colima.inspect", "colima list", "Inventory Colima profiles before cleanup.", .inspect, false, "Shows profile names, status, runtime, architecture, CPU, memory, and disk allocation where available."),
                command("colima.docker-df", "docker system df", "Inspect Docker-managed reclaimable images, containers, local volumes, and build cache.", .inspect, false, "Reports native Docker reclaim estimates without deleting state."),
                command("docker.builder-prune", "docker builder prune --force", "Remove Docker build cache only after reviewing a fresh Docker inventory and active context.", .reclaim, true, "Reclaims Docker build cache while leaving containers, images, volumes, and VM files untouched."),
                command("colima.stop", "colima stop <profile>", "Stop the reviewed Colima profile before destructive profile cleanup.", .inspect, true, "Stops the VM profile; does not reclaim much space on its own."),
                command("colima.delete", "colima delete <profile>", "Delete a reviewed Colima VM profile only after confirming volumes and databases are disposable or backed up.", .destructive, true, "Removes the selected Colima profile and its tool-owned runtime state.")
            ]
        }

        if path.contains("/.docker") || path.contains("/library/containers/com.docker.docker") || path.contains("docker.raw") {
            return [
                command("docker.df", "docker system df", "Inspect Docker reclaimable images, containers, local volumes, and build cache.", .inspect, false, "Reports native Docker reclaim estimates without deleting state."),
                command("docker.builder-prune", "docker builder prune --force", "Remove Docker build cache only after reviewing a fresh Docker inventory and active context.", .reclaim, true, "Reclaims Docker build cache while leaving containers, images, volumes, and VM files untouched."),
                command("docker.prune", "docker system prune", "Prune stopped containers, unused networks, dangling images, and build cache after review.", .reclaim, true, "Reclaims Docker-managed unused state while preserving named volumes."),
                command("docker.prune-volumes", "docker system prune --volumes", "Also prune unused local volumes only after confirming they do not contain unique databases or project state.", .destructive, true, "Can remove unused Docker volumes, including data that may not be reproducible.")
            ]
        }

        if path.contains("/library/caches/homebrew") {
            return [
                command("brew.preview", "brew cleanup -n", "Preview Homebrew cleanup before deleting cached downloads or old versions.", .inspect, false, "Shows what Homebrew would remove."),
                command("brew.cleanup", "brew cleanup", "Let Homebrew remove old downloads and outdated package versions.", .reclaim, true, "Reclaims Homebrew-owned cache and old package artifacts.")
            ]
        }

        if path.contains("/.npm") {
            return [
                command("npm.verify", "npm cache verify", "Verify npm cache integrity and report cache state.", .inspect, false, "Checks npm cache contents without deleting project files."),
                command("npm.cache-clean", "npm cache clean --force", "Clear npm's shared cache only after a successful verify preview and explicit confirmation.", .reclaim, true, "Forces npm to drop its cache; packages are re-downloaded later.")
            ]
        }

        if path.contains("/library/pnpm/store") {
            return [
                command("pnpm.status", "pnpm store status", "Inspect pnpm store packages before pruning.", .inspect, false, "Reports modified packages in the content-addressable store."),
                command("pnpm.prune", "pnpm store prune", "Prune unreferenced packages from the pnpm store after active installs finish.", .reclaim, true, "Removes packages not referenced by current projects.")
            ]
        }

        if path.contains("/library/caches/yarn") {
            return [
                command("yarn.dir", "yarn cache dir", "Locate the active Yarn cache path before cleanup.", .inspect, false, "Prints the cache directory Yarn will operate on."),
                command("yarn.clean", "yarn cache clean", "Clear Yarn cache after active installs finish.", .reclaim, true, "Drops cached packages; future installs may re-download.")
            ]
        }

        if path.contains("/.cargo/registry") || path.contains("/.cargo/git") {
            return [
                command("cargo.project-clean", "cargo clean", "Prefer project-local Rust build cleanup before touching shared Cargo downloads.", .reclaim, true, "Removes target artifacts for the current project."),
                command("cargo.review", "du -sh ~/.cargo/registry ~/.cargo/git", "Review Cargo shared download/cache size manually.", .inspect, false, "Shows shared Cargo cache size without deleting it.")
            ]
        }

        if path.contains("/go/pkg/mod") {
            return [
                command("go.clean", "go clean -modcache", "Clear Go's module download cache after active builds finish.", .reclaim, true, "Removes downloaded module cache; modules are fetched again later.")
            ]
        }

        if path.contains("/.gradle/caches") {
            return [
                command("gradle.stop", "gradle --stop", "Stop Gradle daemons before reviewing caches.", .inspect, true, "Reduces active handles before cleanup."),
                command("gradle.review", "du -sh ~/.gradle/caches", "Review Gradle shared cache size before manual cleanup.", .inspect, false, "Shows cache size without deleting shared dependencies.")
            ]
        }

        if path.contains("/.m2/repository") {
            return [
                command("maven.review", "du -sh ~/.m2/repository", "Review Maven local repository size before manual cleanup.", .inspect, false, "Shows local repository size without deleting dependencies.")
            ]
        }

        if path.contains("/library/caches/org.swift.swiftpm") || path.contains("/.swiftpm/cache") || path.contains("/.build/") {
            return [
                command("swift.clean", "swift package clean", "Prefer project-local SwiftPM cleanup first.", .reclaim, true, "Removes build artifacts for the current package."),
                command("swift.bounded-build", "swift build --scratch-path .build", "Keep future autonomous build output bounded to the project directory.", .inspect, false, "Does not reclaim by itself; constrains future build growth.")
            ]
        }

        if path.contains("/library/caches/cocoapods") {
            return [
                command("pods.clean", "pod cache clean --all", "Clean CocoaPods cache through CocoaPods after active installs finish.", .reclaim, true, "Removes CocoaPods-owned cached pods.")
            ]
        }

        return []
    }

    private static func deduplicateNestedReceipts(_ receipts: [NativeToolReceipt]) -> [NativeToolReceipt] {
        var output: [NativeToolReceipt] = []
        let sorted = receipts.sorted { lhs, rhs in
            let lhsPath = standardizedPath(lhs.findingPath)
            let rhsPath = standardizedPath(rhs.findingPath)
            let lhsDepth = URL(fileURLWithPath: lhsPath).pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhsPath).pathComponents.count
            if lhsDepth == rhsDepth {
                return lhsPath < rhsPath
            }
            return lhsDepth < rhsDepth
        }

        for receipt in sorted {
            let path = standardizedPath(receipt.findingPath)
            if output.contains(where: { isDescendant(path, of: standardizedPath($0.findingPath)) }) {
                continue
            }
            output.append(receipt)
        }
        return output
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let ancestorWithSlash = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(ancestorWithSlash)
    }

    private static func command(
        _ id: String,
        _ command: String,
        _ purpose: String,
        _ risk: NativeToolRisk,
        _ requiresReview: Bool,
        _ expectedEffect: String
    ) -> NativeToolCommand {
        NativeToolCommand(
            id: id,
            command: command,
            purpose: purpose,
            risk: risk,
            requiresReview: requiresReview,
            expectedEffect: expectedEffect
        )
    }
}
