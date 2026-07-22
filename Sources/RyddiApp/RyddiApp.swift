import SwiftUI
import AppKit
import ReclaimerCore

@main
struct RyddiApp {
    static func main() {
        let args = CommandLine.arguments
        if args.count > 1, args[1] == "audit" {
            AuditCLI().run()
        } else {
            RyddiGUIApp.main()
        }
    }
}

struct RyddiGUIApp: App {
    @StateObject private var engine = ScanEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .frame(minWidth: 700, minHeight: 550)
                .alert(engine.confirmationTitle, isPresented: $engine.showConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    if engine.confirmationIsDestructive {
                        Button("Confirm", role: .destructive) { engine.pendingAction?() }
                    } else {
                        Button("Confirm") { engine.pendingAction?() }
                    }
                } message: { Text(engine.confirmationMessage) }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ryddi") {
                    NSApp.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Ryddi",
                            .applicationVersion: "0.8.0",
                            .credits: NSAttributedString(string: "Local-first disk space manager. MIT License."),
                        ]
                    )
                }
            }
            CommandGroup(after: .appTermination) {
                Button("Preferences…") { }
                    .disabled(true)
            }
            CommandMenu("View") {
                Button("Clean") { engine.activePillar = 0 }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Offload") { engine.activePillar = 1 }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Control") { engine.activePillar = 2 }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Audit") { engine.activePillar = 3 }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("Scan for Space") { Task { await engine.scanAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .windowList) {
                Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
                    .keyboardShortcut("m", modifiers: .command)
                Button("Zoom") { NSApp.keyWindow?.zoom(nil) }
                Divider()
                Button("Bring All to Front") { NSApp.arrangeInFront(nil) }
            }
            CommandGroup(replacing: .help) {
                Button("Ryddi Help") {
                    if let url = URL(string: "https://github.com/Reedtrullz/Ryddi/blob/main/README.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        MenuBarExtra("Ryddi", systemImage: "leaf.circle.fill") {
            if engine.isScanning && !engine.hasEverScanned {
                Text("Scanning...").foregroundStyle(.secondary)
            } else if engine.safeItems.isEmpty {
                Text("Not scanned").foregroundStyle(.secondary)
            } else {
                Text("Free: \(formatBytes(freeBytes))")
                    .font(.headline)
                Text("Reclaimable: \(formatBytes(engine.safeTotalBytes))")
                    .foregroundStyle(.green)
            }
            Divider()
            Button("Open Ryddi") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("Quit Ryddi") { NSApp.terminate(nil) }
        }
    }

    private var freeBytes: Int64 {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(vals?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter().string(fromByteCount: bytes)
}
