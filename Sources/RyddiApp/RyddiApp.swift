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
                .frame(minWidth: 600, minHeight: 500)
                .alert(engine.confirmationTitle, isPresented: $engine.showConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    if engine.confirmationIsDestructive {
                        Button("Confirm", role: .destructive) { engine.pendingAction?() }
                    } else {
                        Button("Confirm") { engine.pendingAction?() }
                    }
                } message: { Text(engine.confirmationMessage) }
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
