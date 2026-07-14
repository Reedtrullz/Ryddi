import Foundation

public enum ScopeAccessOperation: String, Codable, Hashable, Sendable {
    case metadata
    case listDirectory
    case openFile
}

public struct ScopeAccessProbeResult: Hashable, Sendable {
    public let state: ScopeReadability
    public let operation: ScopeAccessOperation
    public let errorCode: Int?
    public let detail: String

    public init(
        state: ScopeReadability,
        operation: ScopeAccessOperation,
        errorCode: Int? = nil,
        detail: String
    ) {
        self.state = state
        self.operation = operation
        self.errorCode = errorCode
        self.detail = detail
    }
}

public protocol ScopeAccessProbing: Sendable {
    func probe(_ url: URL) -> ScopeAccessProbeResult
}

public struct FileManagerScopeAccessProbe: ScopeAccessProbing, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func probe(_ url: URL) -> ScopeAccessProbeResult {
        let fileType: FileAttributeType
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return ScopeAccessProbeResult(
                    state: .unknown,
                    operation: .metadata,
                    detail: "Metadata did not identify a filesystem object type; no open was attempted."
                )
            }
            fileType = type
        } catch {
            return failure(error, operation: .metadata)
        }

        switch fileType {
        case .typeDirectory:
            do {
                _ = try fileManager.contentsOfDirectory(atPath: url.path)
                return ScopeAccessProbeResult(
                    state: .readable,
                    operation: .listDirectory,
                    detail: "Directory listing succeeded; returned entry names were discarded."
                )
            } catch {
                return failure(error, operation: .listDirectory)
            }
        case .typeRegular:
            do {
                let handle = try FileHandle(forReadingFrom: url)
                try handle.close()
                return ScopeAccessProbeResult(
                    state: .readable,
                    operation: .openFile,
                    detail: "Regular file opened read-only and closed without reading contents."
                )
            } catch {
                return failure(error, operation: .openFile)
            }
        default:
            return ScopeAccessProbeResult(
                state: .unknown,
                operation: .metadata,
                detail: "Metadata identified a non-regular special file; no open was attempted."
            )
        }
    }

    private func failure(_ error: Error, operation: ScopeAccessOperation) -> ScopeAccessProbeResult {
        let code = normalizedPOSIXCode(in: error)
        let state: ScopeReadability
        switch code {
        case Int(ENOENT), Int(ENOTDIR):
            state = .missing
        case Int(EACCES), Int(EPERM):
            state = .permissionDenied
        default:
            state = .unknown
        }

        return ScopeAccessProbeResult(
            state: state,
            operation: operation,
            errorCode: code,
            detail: detail(for: state, operation: operation, hasPOSIXCode: code != nil)
        )
    }

    private func normalizedPOSIXCode(in error: Error) -> Int? {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            if candidate.domain == NSPOSIXErrorDomain {
                return candidate.code
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    private func detail(
        for state: ScopeReadability,
        operation: ScopeAccessOperation,
        hasPOSIXCode: Bool
    ) -> String {
        let operationName = switch operation {
        case .metadata: "Metadata check"
        case .listDirectory: "Directory listing"
        case .openFile: "Read-only file open"
        }
        switch state {
        case .missing:
            return "\(operationName) reported that the path is missing."
        case .permissionDenied:
            return "\(operationName) failed because permission was denied."
        case .unknown:
            return hasPOSIXCode
                ? "\(operationName) failed with an unclassified POSIX error."
                : "\(operationName) failed without normalized POSIX evidence."
        case .readable:
            return "\(operationName) succeeded."
        }
    }
}
