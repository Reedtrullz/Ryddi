import SwiftUI

struct DashboardSidebarView: View {
    @Binding var selection: DashboardSection
    @AppStorage("dashboard.advanced-sidebar-expanded") private var advancedExpanded = false

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
            ForEach(DashboardSidebarGroup.allCases.filter { $0 != .trust }) { group in
                Section(group.rawValue) {
                    ForEach(sections(in: group)) { section in
                        DashboardSidebarRow(section: section)
                            .tag(section)
                            .accessibilityIdentifier(AccessibilityID.sidebarSection(section))
                    }
                }
            }

            Section(DashboardSidebarGroup.trust.rawValue) {
                ForEach(trustEssentials) { section in
                    DashboardSidebarRow(section: section)
                        .tag(section)
                        .accessibilityIdentifier(AccessibilityID.sidebarSection(section))
                }
                DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                    ForEach(advancedSections) { section in
                        DashboardSidebarRow(section: section)
                            .tag(section)
                            .accessibilityIdentifier(AccessibilityID.sidebarSection(section))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Ryddi")
        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        .accessibilityIdentifier(AccessibilityID.sidebar)
    }

    private func sections(in group: DashboardSidebarGroup) -> [DashboardSection] {
        DashboardSection.sidebarSections.filter { $0.sidebarGroup == group }
    }

    private var trustEssentials: [DashboardSection] {
        [.permissions, .recovery, .automation]
    }

    private var advancedSections: [DashboardSection] {
        sections(in: .trust).filter { !trustEssentials.contains($0) }
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
