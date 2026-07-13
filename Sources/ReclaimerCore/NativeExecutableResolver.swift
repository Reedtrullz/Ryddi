import Foundation

public struct NativeExecutableResolution: Hashable, Sendable {
    public let launchPath: String
    public let resolvedPath: String
    public let identity: FilesystemIdentity?

    public init(launchPath: String, resolvedPath: String, identity: FilesystemIdentity?) {
        self.launchPath = launchPath
        self.resolvedPath = resolvedPath
        self.identity = identity
    }
}

public protocol NativeExecutableResolving: Sendable {
    func resolve(_ executable: String) throws -> NativeExecutableResolution
}

public enum NativeExecutableResolutionError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case unavailable(String)
    case outsideApprovedRoots(String)
    case notExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "Invalid native executable name: \(name)"
        case .unavailable(let name): "Native executable is unavailable in approved tool locations: \(name)"
        case .outsideApprovedRoots(let path): "Native executable is outside approved tool locations: \(path)"
        case .notExecutable(let path): "Native tool path is not an executable regular file: \(path)"
        }
    }
}

public struct SystemNativeExecutableResolver: NativeExecutableResolving {
    private let pathEntries: [URL]
    private let approvedRoots: [URL]

    public init(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.pathEntries = path
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).standardizedFileURL }
        var roots = [
            URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
            URL(fileURLWithPath: "/usr/local", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        ]
        #if DEBUG
        if let testRoot = ProcessInfo.processInfo.environment["RYDDI_TEST_NATIVE_TOOL_ROOT"], !testRoot.isEmpty {
            roots.append(URL(fileURLWithPath: testRoot, isDirectory: true))
        }
        #endif
        self.approvedRoots = roots.map(\.standardizedFileURL)
    }

    public func resolve(_ executable: String) throws -> NativeExecutableResolution {
        guard !executable.isEmpty,
              executable.unicodeScalars.allSatisfy({
                  !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw NativeExecutableResolutionError.invalidName(executable)
        }

        if executable.contains("/") {
            guard executable.hasPrefix("/") else {
                throw NativeExecutableResolutionError.invalidName(executable)
            }
            return try resolution(for: URL(fileURLWithPath: executable).standardizedFileURL)
        }
        for directory in pathEntries where isContained(directory, in: approvedRoots) {
            let candidate = directory.appendingPathComponent(executable).standardizedFileURL
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            return try resolution(for: candidate)
        }
        throw NativeExecutableResolutionError.unavailable(executable)
    }

    private func resolution(for candidate: URL) throws -> NativeExecutableResolution {
        guard isContained(candidate, in: approvedRoots) else {
            throw NativeExecutableResolutionError.outsideApprovedRoots(candidate.path)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(resolved, in: approvedRoots) else {
            throw NativeExecutableResolutionError.outsideApprovedRoots(candidate.path)
        }
        guard FileManager.default.isExecutableFile(atPath: resolved.path),
              let identity = try? FilesystemIdentity.capture(at: resolved),
              identity.isRegularFile,
              !identity.isSymbolicLink else {
            throw NativeExecutableResolutionError.notExecutable(candidate.path)
        }
        return NativeExecutableResolution(
            launchPath: candidate.path,
            resolvedPath: resolved.path,
            identity: identity
        )
    }

    private func isContained(_ candidate: URL, in roots: [URL]) -> Bool {
        let path = candidate.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}

struct PassthroughNativeExecutableResolver: NativeExecutableResolving {
    func resolve(_ executable: String) throws -> NativeExecutableResolution {
        NativeExecutableResolution(launchPath: executable, resolvedPath: executable, identity: nil)
    }
}

extension ToolCommandInvocation {
    func replacingExecutable(with executable: String) -> ToolCommandInvocation {
        ToolCommandInvocation(executable: executable, arguments: arguments)
    }
}
