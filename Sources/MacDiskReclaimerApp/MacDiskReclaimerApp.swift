import SwiftUI

@main
struct MacDiskReclaimerApp: App {
    @State private var appModel = RyddiAppModel()
    @State private var updates = RyddiUpdateController()

    var body: some Scene {
        WindowGroup("Ryddi", id: "dashboard") {
            DashboardView(model: appModel.dashboard)
                .frame(
                    minWidth: RyddiWindowLayout.minimumContentWidth,
                    minHeight: RyddiWindowLayout.minimumContentHeight
                )
        }
        .defaultSize(width: RyddiWindowLayout.defaultContentWidth, height: RyddiWindowLayout.defaultContentHeight)
        .windowResizability(.contentMinSize)
        .commands {
            DashboardCommands(updates: updates)
        }

        MenuBarExtra {
            StatusMenuView(model: appModel.dashboard) {
                await appModel.scanFromMenuBar()
            }
        } label: {
            Label(appModel.menuTitle, systemImage: appModel.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            DashboardSettingsView(model: appModel.dashboard, updates: updates)
        }
    }
}
