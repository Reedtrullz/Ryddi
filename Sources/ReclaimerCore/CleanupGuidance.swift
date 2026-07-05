import Foundation

public enum CleanupGuidance {
    public static func commands(for finding: Finding) -> [String] {
        let path = finding.path.lowercased()
        guard finding.actionKind == .nativeToolCommand || finding.actionKind == .openGuidance else {
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
