import SwiftUI

struct DashboardSidebarView: View {
    @Binding var selection: DashboardPrimaryDestination

    private var selectionBinding: Binding<DashboardPrimaryDestination?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )
    }

    var body: some View {
        List(DashboardPrimaryDestination.allCases, selection: selectionBinding) { destination in
            Label(destination.title, systemImage: destination.systemImage)
                .tag(destination)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.sidebarDestination(destination))
        }
        .listStyle(.sidebar)
        .navigationTitle("Ryddi")
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .accessibilityIdentifier(AccessibilityID.sidebar)
    }
}
