import Foundation
import Darwin

public enum ScanWorkError: LocalizedError, Sendable, Equatable {
    case timedOut, outputLimit, entryLimit, hashLimit, terminationFailed

    public var errorDescription: String? {
        switch self {
        case .timedOut: "Scan deadline reached. Results are incomplete; nothing was changed."
        case .outputLimit: "Scan output limit reached. Results are incomplete; nothing was changed."
        case .entryLimit: "Scan entry limit reached. Results are incomplete; nothing was changed."
        case .hashLimit: "Duplicate verification budget reached. Results are incomplete; nothing was changed."
        case .terminationFailed: "The scan process could not be stopped within its deadline. Results were discarded."
        }
    }
}

/// Synchronous filesystem work runs off the caller's actor, but remains owned by its task.
public func runCancellableScan<Value: Sendable>(
    _ operation: @escaping @Sendable () throws -> Value
) async throws -> Value {
    let worker = Task.detached(priority: .utility) {
        try Task.checkCancellation()
        return try operation()
    }
    return try await withTaskCancellationHandler {
        let value = try await worker.value
        try Task.checkCancellation()
        return value
    } onCancel: {
        worker.cancel()
    }
}

/// Cooperative bounds checked between filesystem calls, including non-candidate entries.
public struct ScanBudget: Sendable {
    private let deadline: TimeInterval
    private let maximumEntries: Int
    private let maximumHashBytes: Int64
    private var entries = 0
    private var hashBytes: Int64 = 0

    public init(timeout: TimeInterval = 60, maximumEntries: Int = 500_000,
                maximumHashBytes: Int64 = 256 * 1024 * 1024) {
        deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        self.maximumEntries = max(0, maximumEntries)
        self.maximumHashBytes = max(0, maximumHashBytes)
    }

    public func check() throws {
        try Task.checkCancellation()
        if ProcessInfo.processInfo.systemUptime >= deadline { throw ScanWorkError.timedOut }
    }

    public mutating func visitEntry() throws {
        try check()
        guard entries < maximumEntries else { throw ScanWorkError.entryLimit }
        entries += 1
    }

    public mutating func hash(_ count: Int) throws {
        try check()
        guard count >= 0, Int64(count) <= maximumHashBytes - hashBytes else {
            throw ScanWorkError.hashLimit
        }
        hashBytes += Int64(count)
    }
}

public struct ScanProcessOutput: Sendable {
    public let data: Data
    public let status: Int32
}

/// Only the directly owned process is signalled. No shell or process-tree management is used.
public enum BoundedScanProcess {
    public static func run(_ process: Process, timeout: TimeInterval,
                           maximumOutputBytes: Int? = nil) throws -> ScanProcessOutput {
        try Task.checkCancellation()
        let pipe = maximumOutputBytes.map { _ in Pipe() }
        if let pipe { process.standardOutput = pipe }
        if process.standardError == nil { process.standardError = FileHandle.nullDevice }
        defer {
            try? pipe?.fileHandleForReading.close()
            try? pipe?.fileHandleForWriting.close()
        }
        if let pipe {
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) != -1 else {
                throw CocoaError(.fileReadUnknown)
            }
        }
        try process.run()
        try? pipe?.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var output = Data()
        var eof = pipe == nil
        do {
            while process.isRunning || !eof {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw ScanWorkError.timedOut }
                if let pipe, !eof {
                    var buffer = [UInt8](repeating: 0, count: 65_536)
                    let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                    if count > 0 {
                        guard count <= max(0, maximumOutputBytes ?? 0) - output.count else {
                            throw ScanWorkError.outputLimit
                        }
                        output.append(contentsOf: buffer.prefix(count))
                        continue
                    }
                    if count == 0 { eof = true }
                    else if errno != EAGAIN && errno != EINTR { throw CocoaError(.fileReadUnknown) }
                }
                usleep(10_000)
            }
            try Task.checkCancellation()
        } catch {
            if process.isRunning {
                process.terminate()
                let grace = ProcessInfo.processInfo.systemUptime + 0.25
                while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                let stopDeadline = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline { usleep(10_000) }
                guard !process.isRunning else { throw ScanWorkError.terminationFailed }
            }
            throw error
        }
        return ScanProcessOutput(data: output, status: process.terminationStatus)
    }
}
