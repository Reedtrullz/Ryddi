import SwiftUI

struct DashboardCommandActions {
    var canScan: Bool
    var canPlan: Bool
    var canDryRun: Bool
    var canExport: Bool
    var scan: () -> Void
    var buildPlan: () -> Void
    var dryRun: () -> Void
    var exportReport: () -> Void
    var exportRedactedReport: () -> Void
    var openSection: (DashboardSection) -> Void
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
            Button("Scan") {
                actions?.scan()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions?.canScan != true)

            Button("Build Plan") {
                actions?.buildPlan()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(actions?.canPlan != true)

            Button("Dry Run") {
                actions?.dryRun()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(actions?.canDryRun != true)

            Divider()

            Button("Cleanup Flow") {
                actions?.openSection(.queues)
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(actions == nil)

            Button("Audit History") {
                actions?.openSection(.audit)
            }
            .keyboardShortcut("2", modifiers: [.command])
            .disabled(actions == nil)

            Divider()

            Button("Export Report") {
                actions?.exportReport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions?.canExport != true)

            Button("Export Redacted Report") {
                actions?.exportRedactedReport()
            }
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .disabled(actions?.canExport != true)

            Divider()

            Button("Ryddi Settings") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
