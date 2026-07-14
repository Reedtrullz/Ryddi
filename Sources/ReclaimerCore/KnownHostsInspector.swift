import CryptoKit
import Foundation

public struct KnownHostEvidence: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case known
        case unknown
        case unavailable
    }

    public let state: State
    public let keyType: String?
    public let fingerprint: String?

    public init(state: State, keyType: String?, fingerprint: String?) {
        self.state = state
        self.keyType = keyType
        self.fingerprint = fingerprint
    }
}

public struct KnownHostsInspector: Sendable {
    private static let maximumOutputBytes = 512_000
    private static let maximumOutputLines = 128

    private let runner: any ToolCommandRunning

    public init(runner: any ToolCommandRunning = ProcessToolCommandRunner()) {
        self.runner = runner
    }

    public func inspect(host: String, port: Int?, file: URL) -> KnownHostEvidence {
        let query = queryHost(host: host, port: port)
        let invocation = ToolCommandInvocation(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-F", query, "-f", file.standardizedFileURL.path]
        )
        let output = runner.run(invocation, timeout: 5)

        guard !output.timedOut, output.launchError == nil, output.exitCode != nil else {
            return unavailableEvidence
        }
        guard output.exitCode == 0 else {
            return output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? unknownEvidence
                : unavailableEvidence
        }
        guard let key = firstKey(in: output.stdout) else {
            return unknownEvidence
        }

        let digest = SHA256.hash(data: key.bytes)
        let encodedDigest = Data(digest)
            .base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return KnownHostEvidence(
            state: .known,
            keyType: key.type,
            fingerprint: "SHA256:\(encodedDigest)"
        )
    }

    private var unknownEvidence: KnownHostEvidence {
        KnownHostEvidence(state: .unknown, keyType: nil, fingerprint: nil)
    }

    private var unavailableEvidence: KnownHostEvidence {
        KnownHostEvidence(state: .unavailable, keyType: nil, fingerprint: nil)
    }

    private func queryHost(host: String, port: Int?) -> String {
        guard let port, port != 22 else { return host }
        let unbracketedHost: Substring
        if host.hasPrefix("["), host.hasSuffix("]") {
            unbracketedHost = host.dropFirst().dropLast()
        } else {
            unbracketedHost = Substring(host)
        }
        return "[\(unbracketedHost)]:\(port)"
    }

    private func firstKey(in output: String) -> (type: String, bytes: Data)? {
        let boundedData = Data(output.utf8.prefix(Self.maximumOutputBytes))
        let boundedOutput = String(decoding: boundedData, as: UTF8.self)
        for line in boundedOutput.split(whereSeparator: \.isNewline).prefix(Self.maximumOutputLines) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = fields.first, !first.hasPrefix("#") else { continue }
            for index in fields.indices.dropLast() where isKeyType(fields[index]) {
                guard let bytes = decodeBase64(fields[index + 1]) else { continue }
                return (fields[index], bytes)
            }
        }
        return nil
    }

    private func isKeyType(_ value: String) -> Bool {
        value.hasPrefix("ssh-") || value.hasPrefix("ecdsa-") || value.hasPrefix("sk-")
    }

    private func decodeBase64(_ value: String) -> Data? {
        guard value.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || "+/=".unicodeScalars.contains($0)
        }) else {
            return nil
        }
        let paddingCount = (4 - value.utf8.count % 4) % 4
        return Data(base64Encoded: value + String(repeating: "=", count: paddingCount))
    }
}
