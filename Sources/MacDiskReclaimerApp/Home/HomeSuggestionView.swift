import SwiftUI
import ReclaimerCore

struct HomeSuggestionView: View {
    let suggestion: HomeSuggestion
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            GroupBox {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(suggestion.title, systemImage: systemImage)
                            .font(.headline)
                        Spacer()
                        Text(ByteFormat.string(suggestion.allocatedBytes))
                            .font(.subheadline.monospacedDigit())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
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
        }
        .buttonStyle(HomeSuggestionButtonStyle())
        .accessibilityIdentifier("home.suggestion.\(suggestion.id)")
        .accessibilityLabel("\(suggestion.title), \(ByteFormat.string(suggestion.allocatedBytes)). \(suggestion.consequence)")
        .accessibilityHint("Opens this group for review with nothing selected outside it.")
    }

    private var systemImage: String {
        switch suggestion.kind {
        case .safeMaintenance: "checkmark.shield"
        case .quitAndCheckAgain: "pause.circle"
        case .nativeMaintenance: "wrench.and.screwdriver"
        case .reviewPersonalFiles: "doc.text.magnifyingglass"
        case .keepByDefault: "lock"
        case .protected: "hand.raised.fill"
        case .insufficientEvidence: "questionmark.diamond"
        }
    }
}

private struct HomeSuggestionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}
