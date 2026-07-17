import SwiftUI

struct DashboardCommandActions {
    var canScan: Bool
    var startScan: () -> Void
    var openDestination: (DashboardPrimaryDestination) -> Void
}

private struct DashboardCommandActionsKey: FocusedValueKey {
    typealias Value = DashboardCommandActions
}

extension FocusedValues {
    var dashboardCommandActions: DashboardCommandActions? {
        get { self[DashboardCommandActionsKey.self] }
        set { self[DashboardCommandActionsKey.self] = newValue }
    }
}

struct DashboardCommands: Commands {
    @FocusedValue(\.dashboardCommandActions) private var actions
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Ryddi") {
            Button("Scan Again") { actions?.startScan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(actions?.canScan != true)
            Divider()
            Button("Home") { actions?.openDestination(.home) }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(actions == nil)
            Button("Explore") { actions?.openDestination(.explore) }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(actions == nil)
            Button("History") { actions?.openDestination(.history) }
                .keyboardShortcut("3", modifiers: [.command])
                .disabled(actions == nil)
            Divider()
            Button("Ryddi Settings") { openSettings() }
                .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
