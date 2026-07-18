import SwiftUI
import ReclaimerCore

struct HomeReclaimCard: View {
    let suggestion: HomeSuggestion
    let isWorking: Bool
    let visibilityIsLimited: Bool
    let onReview: () -> Void

    var body: some View {
        GroupBox {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    summary
                    Spacer(minLength: 16)
                    reviewButton
                }
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    reviewButton
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Ready for your review", systemImage: "checkmark.shield")
                .font(.headline)
        }
        .accessibilityIdentifier("home.reclaim-card")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Up to \(ByteFormat.string(suggestion.estimatedReclaimBytes ?? 0)) may be reclaimable")
                .font(.title2.bold())
            Text("\(itemCountText) from this scan. Nothing is selected. Ryddi checks each choice again before Move to Trash.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if visibilityIsLimited {
                Text("This estimate uses only the locations Ryddi could measure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Choose items  →  Check safely  →  Move to Trash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var reviewButton: some View {
        Button("Review safe maintenance", action: onReview)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
            .accessibilityIdentifier("home.primary-action")
    }

    private var itemCountText: String {
        let count = suggestion.findingIDs.count
        return count == 1 ? "1 recreatable item" : "\(count) recreatable items"
    }
}
