import SwiftUI

@main
struct MacDiskReclaimerApp: App {
    @State private var statusModel = StatusMenuModel()

    var body: some Scene {
        WindowGroup("Ryddi", id: "dashboard") {
            DashboardView()
                .frame(
                    minWidth: RyddiWindowLayout.minimumContentWidth,
                    minHeight: RyddiWindowLayout.minimumContentHeight
                )
        }
        .defaultSize(width: RyddiWindowLayout.defaultContentWidth, height: RyddiWindowLayout.defaultContentHeight)
        .windowResizability(.contentMinSize)
        .commands {
            DashboardCommands()
        }

        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            Label(statusModel.menuTitle, systemImage: statusModel.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            DashboardSettingsView()
        }
    }
}
