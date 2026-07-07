import Foundation

public struct RemoteDURow: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int64

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}

public struct RemoteLargeFileRow: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int64

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}

public enum RemoteParsers {
    public static func parseOSRelease(_ output: String) -> String? {
        let fields = keyValueLines(output)
        return fields["PRETTY_NAME"] ?? fields["NAME"]
    }

    public static func parseDF(_ output: String) -> [RemoteFilesystemSummary] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("filesystem") }
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 6 else { return nil }
                let used = Int64(fields[2]).map { $0 * 1024 }
                let available = Int64(fields[3]).map { $0 * 1024 }
                let capacity = Int(fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "%")))
                return RemoteFilesystemSummary(
                    mount: fields.dropFirst(5).joined(separator: " "),
                    filesystem: fields[0],
                    usedBytes: used,
                    availableBytes: available,
                    capacityPercent: capacity
                )
            }
    }

    public static func parseDU(_ output: String) -> [RemoteDURow] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line in
                let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count == 2, let kb = Int64(fields[0]) else { return nil }
                return RemoteDURow(path: fields[1].trimmingCharacters(in: .whitespacesAndNewlines), bytes: kb * 1024)
            }
    }

    public static func parseLargeFiles(_ output: String) -> [RemoteLargeFileRow] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line in
                let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard fields.count == 2, let bytes = Int64(fields[0]) else { return nil }
                return RemoteLargeFileRow(path: fields[1].trimmingCharacters(in: .whitespacesAndNewlines), bytes: bytes)
            }
    }

    public static func parseJournalctlDiskUsage(_ output: String) -> Int64? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?)(?:i?B|B)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let valueRange = Range(match.range(at: 1), in: output),
              let value = Double(output[valueRange]) else {
            return nil
        }
        let unit: String
        if let unitRange = Range(match.range(at: 2), in: output) {
            unit = String(output[unitRange]).uppercased()
        } else {
            unit = ""
        }
        let multiplier: Double = switch unit {
        case "T": 1024 * 1024 * 1024 * 1024
        case "G": 1024 * 1024 * 1024
        case "M": 1024 * 1024
        case "K": 1024
        default: 1
        }
        return Int64(value * multiplier)
    }

    public static func parseDockerSystemDF(_ output: String) -> [DockerStorageBucket] {
        ContainerInventoryScanner.parseDockerSystemDF(output)
    }

    public static func parsePermissionDeniedPaths(_ stderr: String) -> [String] {
        stderr
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.localizedCaseInsensitiveContains("Permission denied") }
            .map { line in
                if let first = line.firstIndex(of: "'"),
                   let last = line.lastIndex(of: "'"),
                   first < last {
                    return String(line[line.index(after: first)..<last])
                }
                return line
            }
    }

    private static func keyValueLines(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return result
    }
}
