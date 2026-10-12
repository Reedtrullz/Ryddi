import SwiftUI
import AppKit
import ReclaimerCore

struct CleanupReceiptView: View {
    let receipt: CleanupReceipt
    let dismiss: () -> Void
    @State private var includePaths = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action receipt").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(receipt.summary).font(.headline)
            Text(CleanupReceipt.spaceStatement).font(.callout)
            Text("Kept in memory for 30 minutes, until dismissed or replaced. Recovery locations reflect the action time; they may change afterward.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(receipt.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.outcome.rawValue): \(URL(fileURLWithPath: entry.sourcePath).lastPathComponent)")
                                .font(.headline).accessibilityAddTraits(.isHeader)
                            Text(entry.sourcePath).font(.caption)
                            Text(entry.detail)
                            if let path = entry.recoveryPath {
                                Text("Recorded recovery location: \(path)").font(.caption)
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }
                                .accessibilityLabel("Reveal recovery location for \(URL(fileURLWithPath: entry.sourcePath).lastPathComponent)")
                                .help("Reveal the recorded location; this does not restore or delete anything.")
                            } else {
                                Text("Recovery location unverified. Review source and Trash manually.")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            Toggle("Include private paths and error details in copied receipt", isOn: $includePaths)
            HStack {
                Button(includePaths ? "Copy with paths" : "Copy redacted receipt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(receipt.text(includePaths: includePaths), forType: .string)
                }
                .keyboardShortcut("c", modifiers: .command)
                Spacer()
                Button("Dismiss receipt", action: dismiss).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}
