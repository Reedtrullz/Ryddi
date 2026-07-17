import SwiftUI
import ReclaimerCore

struct HomeSuggestionView: View {
    let suggestion: HomeSuggestion

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(suggestion.title)
                        .font(.headline)
                    Spacer()
                    Text(ByteFormat.string(suggestion.allocatedBytes))
                        .font(.subheadline.monospacedDigit())
                }
                Text(suggestion.explanation)
                    .foregroundStyle(.secondary)
                Text(suggestion.consequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reclaim = suggestion.estimatedReclaimBytes {
                    Label(
                        "Up to \(ByteFormat.string(reclaim)) estimated reclaim after safety checks",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
