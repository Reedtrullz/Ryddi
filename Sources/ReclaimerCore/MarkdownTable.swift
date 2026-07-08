import Foundation

enum MarkdownTable {
    static func cell(_ value: String) -> String {
        let compact = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "-" : compact
    }
}
