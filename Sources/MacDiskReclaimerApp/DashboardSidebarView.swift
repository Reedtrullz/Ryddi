import SwiftUI

struct DashboardSidebarView: View {
    @Binding var selection: DashboardSection

    private var selectionBinding: Binding<DashboardSection?> {
        Binding<DashboardSection?>(
            get: { selection },
            set: { nextSelection in
                if let nextSelection {
                    selection = nextSelection
                }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(DashboardSidebarGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(sections(in: group)) { section in
                        DashboardSidebarRow(section: section)
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Ryddi")
        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
    }

    private func sections(in group: DashboardSidebarGroup) -> [DashboardSection] {
        DashboardSection.sidebarSections.filter { $0.sidebarGroup == group }
    }
}

private struct DashboardSidebarRow: View {
    let section: DashboardSection

    var body: some View {
        Label {
            Text(section.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
