import SwiftUI

struct HistoryView: View {
    @Bindable var model: DashboardModel
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.largeTitle.bold())
            Text("Receipts and verification are evidence of what Ryddi observed—not a promise based on scan estimates.")
                .foregroundStyle(.secondary)
            Picker("History view", selection: $tab) {
                Text("Receipts").tag(0)
                Text("Recovery").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            if tab == 0 {
                AuditHistoryView(model: model)
            } else {
                RecoveryCenterView(model: model)
            }
        }
        .padding(22)
        .navigationTitle("History")
    }
}
