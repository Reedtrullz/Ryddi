import SwiftUI
import ReclaimerCore

struct CleanupReviewView: View {
    @Bindable var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    private var reviewFindings: [Finding] {
        let suggestedIDs = Set(model.homeSnapshot.suggestions.flatMap(\.findingIDs))
        return model.findings
            .filter { suggestedIDs.contains($0.id) }
            .sorted {
                if $0.allocatedSize == $1.allocatedSize { return $0.displayName < $1.displayName }
                return $0.allocatedSize > $1.allocatedSize
            }
    }

    var body: some View {
        Group {
            if let request = model.pendingTrashConfirmation {
                TrashConfirmationView(
                    request: request,
                    isExecuting: model.isWorking,
                    onCancel: { Task { await model.cancelPendingTrashExecution() } },
                    onConfirm: { Task { await model.executeConfirmedTrash() } }
                )
            } else {
                reviewContent
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onDisappear {
            if model.lastExecutionReceipt != nil {
                model.clearReviewSelection()
            }
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review cleanup").font(.title2.bold())
                    Text("Nothing is selected until you choose it.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("cleanup-review.done")
            }

            if reviewFindings.isEmpty {
                ContentUnavailableView(
                    "Nothing ready for cleanup",
                    systemImage: "checkmark.shield",
                    description: Text("Explore your map or scan again after changing access.")
                )
            } else {
                List {
                    SwiftUI.ForEach(reviewFindings) { finding in
                        let eligible = isEligible(finding)
                        Toggle(isOn: Binding(
                            get: { model.reviewSelectionIDs.contains(finding.id) },
                            set: { _ in model.toggleReviewSelection(finding.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(finding.displayName)
                                    Spacer()
                                    Text(ByteFormat.string(finding.allocatedSize))
                                        .monospacedDigit()
                                }
                                Text(eligible
                                     ? "Eligible for current safety checks"
                                     : finding.safetyClass.label)
                                    .font(.caption)
                                    .foregroundStyle(eligible ? Color.secondary : Color.orange)
                            }
                        }
                        .disabled(!eligible)
                        .accessibilityIdentifier("cleanup-review.item.\(finding.id)")
                    }
                }
            }

            if let receipt = model.lastDryRunReceipt {
                GroupBox("Safety check") {
                    Text("\(receipt.actions.filter { $0.status == "would-execute" || $0.status == "success" }.count) ready, \(receipt.actions.filter { $0.status != "would-execute" && $0.status != "success" }.count) skipped")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let message = model.trashExecutionMessage {
                Text(message)
                    .accessibilityIdentifier(AccessibilityID.trashResult)
            }

            HStack {
                Button("Select safe maintenance") {
                    Task { await model.selectSafeMaintenance() }
                }
                .disabled(model.isWorking || reviewFindings.isEmpty)
                .accessibilityIdentifier("cleanup-review.select-safe")

                Button("Clear") { model.clearReviewSelection() }
                    .disabled(model.reviewSelectionIDs.isEmpty || model.isWorking)

                Spacer()

                Text("\(model.reviewSelectionIDs.count) selected")
                    .foregroundStyle(.secondary)

                Button("Check safely") {
                    Task { await model.checkSelectedItemsSafely() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.reviewSelectionIDs.isEmpty || model.isWorking)
                .accessibilityIdentifier("cleanup-review.check-safely")

                if model.trashExecutionReadiness.isReady {
                    Button("Move to Trash") {
                        Task { await model.prepareTrashExecution() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("cleanup-review.move-to-trash")
                }
            }

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private func isEligible(_ finding: Finding) -> Bool {
        finding.safetyClass == .autoSafe
            && [.deleteCache, .trash].contains(finding.actionKind)
            && !finding.isSymbolicLink
    }
}
