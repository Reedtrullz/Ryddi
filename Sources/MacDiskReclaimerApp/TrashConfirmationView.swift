import SwiftUI
import ReclaimerCore

struct TrashConfirmationRequest: Identifiable, Hashable {
    let authorizationID: UUID
    let expiresAt: Date
    let model: TrashConfirmationModel

    var id: UUID { authorizationID }

    init(authorization: TrashExecutionAuthorization, plan: ReclaimPlan) {
        authorizationID = authorization.id
        expiresAt = authorization.expiresAt
        model = TrashConfirmationModel.build(plan: plan, pathStyle: .full)
    }
}

struct TrashConfirmationView: View {
    let request: TrashConfirmationRequest
    let isExecuting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var reviewed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Move selected items to Trash", systemImage: "trash")
                .font(.title2.bold())
            Text("These items passed a matching dry run. Ryddi will recheck identity, rules, policy, symlinks, age gates, and open handles immediately before each move.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Label("\(request.model.itemCount) item\(request.model.itemCount == 1 ? "" : "s")", systemImage: "checklist")
                Spacer()
                Text(ByteFormat.string(request.model.totalAllocatedBytes))
                    .monospacedDigit()
            }
            .font(.headline)

            List(request.model.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name).fontWeight(.semibold)
                        Spacer()
                        Text(ByteFormat.string(item.allocatedBytes)).monospacedDigit()
                    }
                    Text(item.displayPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if !item.conditions.isEmpty {
                        Text("Checks: \(item.conditions.joined(separator: "; "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 160, maxHeight: 320)

            ForEach(request.model.nonClaims.prefix(3), id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("I reviewed every item above", isOn: $reviewed)
                .accessibilityIdentifier(AccessibilityID.trashReviewed)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isExecuting)
                    .accessibilityIdentifier(AccessibilityID.trashCancel)
                Button("Move to Trash", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!reviewed || isExecuting)
                    .accessibilityIdentifier(AccessibilityID.trashConfirm)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 430)
    }
}
