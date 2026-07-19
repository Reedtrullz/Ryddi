import SwiftUI

@main
struct RyddiApp: App {
    @StateObject private var engine = ScanEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .frame(minWidth: 520, minHeight: 600)
                .alert(engine.confirmationTitle, isPresented: $engine.showConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    if engine.confirmationIsDestructive {
                        Button("Confirm", role: .destructive) { engine.pendingAction?() }
                    } else {
                        Button("Confirm") { engine.pendingAction?() }
                    }
                } message: { Text(engine.confirmationMessage) }
        }
    }
}
