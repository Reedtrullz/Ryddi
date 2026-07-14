import Darwin
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

protocol DirectoryAccessOperating: Sendable {
    func accessDirectory(atPath path: String, maximumEntryCount: Int) -> Int32?
}

private struct POSIXDirectoryAccessOperation: DirectoryAccessOperating {
    func accessDirectory(atPath path: String, maximumEntryCount: Int) -> Int32? {
        path.withCString { pathPointer in
            guard let directory = opendir(pathPointer) else { return errno }

            errno = 0
            if maximumEntryCount > 0 {
                _ = readdir(directory)
            }
            let readError = errno
            let closeResult = closedir(directory)
            if readError != 0 {
                return readError
            }
            return closeResult == 0 ? nil : errno
        }
    }
}

public struct FileManagerScopeAccessProbe: ScopeAccessProbing, @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryAccessOperation: any DirectoryAccessOperating

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryAccessOperation = POSIXDirectoryAccessOperation()
    }

    init(
        fileManager: FileManager,
        directoryAccessOperation: any DirectoryAccessOperating
    ) {
        self.fileManager = fileManager
        self.directoryAccessOperation = directoryAccessOperation
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
            return .failure(error, operation: .metadata)
        }

        switch fileType {
        case .typeDirectory:
            if let errorCode = directoryAccessOperation.accessDirectory(
                atPath: url.path,
                maximumEntryCount: 1
            ) {
                return .failure(
                    NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode)),
                    operation: .listDirectory
                )
            }
            return ScopeAccessProbeResult(
                state: .readable,
                operation: .listDirectory,
                detail: "Directory access succeeded after reading at most one entry; its name was discarded."
            )
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
                return .failure(error, operation: .openFile)
            }
        default:
            return ScopeAccessProbeResult(
                state: .unknown,
                operation: .metadata,
                detail: "Metadata identified a non-regular special file; no open was attempted."
            )
        }
    }

}

extension ScopeAccessProbeResult {
    static func failure(_ error: Error, operation: ScopeAccessOperation) -> ScopeAccessProbeResult {
        let code = ScopeReadability.normalizedPOSIXCode(in: error)
        let state = ScopeReadability.classify(error: error)

        return ScopeAccessProbeResult(
            state: state,
            operation: operation,
            errorCode: code,
            detail: failureDetail(for: state, operation: operation, hasPOSIXCode: code != nil)
        )
    }

    private static func failureDetail(
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
