import SwiftUI
import ReclaimerCore

struct HomeSuggestionView: View {
    let suggestion: HomeSuggestion
    let isActionable: Bool
    let onReview: () -> Void

    @ViewBuilder
    var body: some View {
        if isActionable {
            Button(action: onReview) {
                cardContent(showsChevron: true)
            }
            .buttonStyle(HomeSuggestionButtonStyle())
            .accessibilityIdentifier("home.suggestion.\(suggestion.id)")
            .accessibilityLabel("\(suggestion.title), \(ByteFormat.string(suggestion.allocatedBytes)). \(suggestion.consequence)")
            .accessibilityHint("Opens the appropriate review workspace without selecting anything.")
        } else {
            cardContent(showsChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.suggestion.\(suggestion.id)")
        }
    }

    private func cardContent(showsChevron: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Label(suggestion.title, systemImage: systemImage)
                        .font(.headline)
                    Spacer()
                    Text(ByteFormat.string(suggestion.allocatedBytes))
                        .font(.subheadline.monospacedDigit())
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
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
