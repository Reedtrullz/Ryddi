import Foundation
#if os(macOS)
import AppKit
#endif

protocol RelaunchCommandRunning: Sendable {
    func runOpenCommand(for applicationURL: URL) async throws -> Int32
}

protocol ApplicationTerminating: Sendable {
    @MainActor func terminate()
}

enum RelaunchApplicationFailure: Error, Equatable {
    case launchFailed
    case commandFailed(exitStatus: Int32)

    var message: String {
        switch self {
        case .launchFailed:
            "Ryddi could not start the macOS open command. The current app is still running."
        case .commandFailed(let exitStatus):
            "The macOS open command exited with status \(exitStatus). The current app is still running."
        }
    }
}

private struct ProcessRelaunchCommandRunner: RelaunchCommandRunning {
    func runOpenCommand(for applicationURL: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", applicationURL.path]
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

#if os(macOS)
private struct NSApplicationTerminator: ApplicationTerminating {
    @MainActor
    func terminate() {
        NSApp.terminate(nil)
    }
}
#endif

enum PathActions {
    static var applicationPath: String {
        #if os(macOS)
        Bundle.main.bundleURL.path
        #else
        ""
        #endif
    }

    static func copyPath(_ path: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #endif
    }

    static func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func revealInFinder(_ path: String) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }

    static func revealApplicationInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        #endif
    }

    static func quickLook(_ path: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", path]
        try? process.run()
        #endif
    }

    static func openTerminal(at path: String, isDirectory: Bool) {
        #if os(macOS)
        let target = isDirectory ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", target]
        try? process.run()
        #endif
    }

    static func openFullDiskAccessSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    @MainActor
    static func relaunchApplication() async -> Result<Void, RelaunchApplicationFailure> {
        #if os(macOS)
        return await relaunchApplication(
            commandRunner: ProcessRelaunchCommandRunner(),
            applicationTerminator: NSApplicationTerminator(),
            applicationURL: Bundle.main.bundleURL
        )
        #else
        return .failure(.launchFailed)
        #endif
    }

    @MainActor
    static func relaunchApplication(
        commandRunner: any RelaunchCommandRunning,
        applicationTerminator: any ApplicationTerminating,
        applicationURL: URL
    ) async -> Result<Void, RelaunchApplicationFailure> {
        do {
            let exitStatus = try await commandRunner.runOpenCommand(for: applicationURL)
            guard exitStatus == 0 else {
                return .failure(.commandFailed(exitStatus: exitStatus))
            }
            applicationTerminator.terminate()
            return .success(())
        } catch {
            return .failure(.launchFailed)
        }
    }
}
