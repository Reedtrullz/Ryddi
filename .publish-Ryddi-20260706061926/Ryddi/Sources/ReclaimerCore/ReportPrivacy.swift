import Foundation

public enum ReportPathStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case full
    case homeRelative = "home-relative"
    case redacted

    public var label: String {
        switch self {
        case .full: "Full paths"
        case .homeRelative: "Home-relative paths"
        case .redacted: "Redacted paths"
        }
    }
}

public struct ReportPrivacyOptions: Codable, Hashable, Sendable {
    public let pathStyle: ReportPathStyle
    public let redactUserText: Bool
    public let homeDirectoryPath: String

    public init(
        pathStyle: ReportPathStyle = .full,
        redactUserText: Bool = false,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.pathStyle = pathStyle
        self.redactUserText = redactUserText
        self.homeDirectoryPath = homeDirectory.standardizedFileURL.path
    }

    public static let `default` = ReportPrivacyOptions()

    public var summary: String {
        var parts = ["Path style: \(pathStyle.rawValue)"]
        if redactUserText {
            parts.append("user-entered text redacted")
        }
        return parts.joined(separator: "; ")
    }

    public func displayPath(_ path: String) -> String {
        switch pathStyle {
        case .full:
            return path
        case .homeRelative:
            return homeRelativePath(path)
        case .redacted:
            return "<path redacted>"
        }
    }

    public func displayUserText(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "-"
        }
        return redactUserText ? "<redacted>" : displayText(text)
    }

    public func displayText(_ text: String, knownPaths: [String] = []) -> String {
        var output = text
        let paths = knownPaths
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for path in paths {
            output = output.replacingOccurrences(of: path, with: displayPath(path))
        }

        guard pathStyle != .full else {
            return output
        }

        let home = standardized(homeDirectoryPath)
        if !home.isEmpty {
            output = output.replacingOccurrences(
                of: home,
                with: pathStyle == .homeRelative ? "~" : "<home>"
            )
        }
        return output
    }

    private func homeRelativePath(_ path: String) -> String {
        let standardizedPath = standardized(path)
        let home = standardized(homeDirectoryPath)
        guard !home.isEmpty else { return path }
        guard standardizedPath == home || standardizedPath.hasPrefix(home + "/") else {
            return path
        }
        let suffix = standardizedPath.dropFirst(home.count)
        return suffix.isEmpty ? "~" : "~\(suffix)"
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
