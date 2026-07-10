import Darwin
import Foundation

public enum SafeFileOutputError: Error, LocalizedError, Equatable {
    case invalidOutputPath(String, String)
    case outputAlreadyExists(String)
    case writeFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutputPath(let path, let reason):
            "Output path rejected at \(path): \(reason)"
        case .outputAlreadyExists(let path):
            "Output file already exists and will not be replaced: \(path)"
        case .writeFailed(let path, let reason):
            "Could not write output file \(path): \(reason)"
        }
    }
}

/// Writes a user-requested export through a bound parent directory descriptor.
/// Existing files are never replaced, and all new files are opened with O_EXCL.
public enum SafeFileOutput {
    @discardableResult
    public static func write(_ text: String, to output: URL) throws -> URL {
        try write(Data(text.utf8), to: output)
    }

    @discardableResult
    public static func write(_ data: Data, to output: URL) throws -> URL {
        try write(data, to: output, beforeWrite: nil)
    }

    @discardableResult
    static func write(
        _ data: Data,
        to requestedOutput: URL,
        beforeWrite: (() throws -> Void)?
    ) throws -> URL {
        let output = requestedOutput.standardizedFileURL
        guard output.isFileURL else {
            throw SafeFileOutputError.invalidOutputPath(output.path, "a local file URL is required")
        }
        let name = output.lastPathComponent
        guard isSimpleFileName(name) else {
            throw SafeFileOutputError.invalidOutputPath(output.path, "the output must name a file inside an existing directory")
        }
        try rejectFinalSymbolicLink(at: output)

        let rawParent = output.deletingLastPathComponent().standardizedFileURL
        var expectedParent = Darwin.stat()
        guard rawParent.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &expectedParent, 0) }) == 0,
              isDirectory(expectedParent) else {
            throw SafeFileOutputError.invalidOutputPath(output.path, "the output parent must already be an ordinary directory")
        }

        let parentPath = try canonicalParentPath(for: output)
        let parentDescriptor = try openBoundDirectory(path: parentPath, expectedIdentity: expectedParent, requestedOutput: output.path)
        defer { Darwin.close(parentDescriptor) }

        try beforeWrite?()
        try writeNew(data, named: name, to: parentDescriptor, outputPath: output.path)
        return output
    }

    private static func rejectFinalSymbolicLink(at output: URL) throws {
        var status = Darwin.stat()
        let result = output.path.withCString { Darwin.lstat($0, &status) }
        guard result != 0 || !isSymbolicLink(status) else {
            throw SafeFileOutputError.invalidOutputPath(output.path, "the output file itself must not be a symbolic link")
        }
    }

    private static func canonicalParentPath(for output: URL) throws -> String {
        let parent = output.deletingLastPathComponent().standardizedFileURL
        guard let resolvedParent = parent.path.withCString({ Darwin.realpath($0, nil) }) else {
            throw SafeFileOutputError.invalidOutputPath(output.path, "the output parent must already exist: \(errnoDescription())")
        }
        defer { Darwin.free(resolvedParent) }
        return String(cString: resolvedParent)
    }

    private static func openBoundDirectory(
        path: String,
        expectedIdentity: Darwin.stat,
        requestedOutput: String
    ) throws -> Int32 {
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw SafeFileOutputError.invalidOutputPath(requestedOutput, errnoDescription())
        }

        do {
            for component in path.split(separator: "/") {
                let nextDescriptor = String(component).withCString {
                    Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                }
                guard nextDescriptor >= 0 else {
                    throw SafeFileOutputError.invalidOutputPath(requestedOutput, "\(errnoDescription()) while opening \(component)")
                }
                Darwin.close(descriptor)
                descriptor = nextDescriptor
            }

            var boundIdentity = Darwin.stat()
            guard Darwin.fstat(descriptor, &boundIdentity) == 0,
                  sameIdentity(expectedIdentity, boundIdentity) else {
                throw SafeFileOutputError.invalidOutputPath(
                    requestedOutput,
                    "the output parent changed while it was being opened"
                )
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func writeNew(
        _ data: Data,
        named name: String,
        to parentDescriptor: Int32,
        outputPath: String
    ) throws {
        let descriptor = name.withCString {
            Darwin.openat(parentDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else {
            let writeErrno = errno
            if writeErrno == EEXIST {
                throw SafeFileOutputError.outputAlreadyExists(outputPath)
            }
            throw SafeFileOutputError.writeFailed(outputPath, errnoDescription(writeErrno))
        }
        defer { Darwin.close(descriptor) }

        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) throws in
            var offset = 0
            while offset < buffer.count {
                guard let baseAddress = buffer.baseAddress else { break }
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += Int(count)
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                throw SafeFileOutputError.writeFailed(outputPath, errnoDescription())
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw SafeFileOutputError.writeFailed(outputPath, errnoDescription())
        }
    }

    private static func isSimpleFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    private static func isDirectory(_ status: Darwin.stat) -> Bool {
        (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func isSymbolicLink(_ status: Darwin.stat) -> Bool {
        (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func sameIdentity(_ left: Darwin.stat, _ right: Darwin.stat) -> Bool {
        left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    private static func errnoDescription(_ code: Int32 = errno) -> String {
        String(cString: Darwin.strerror(code))
    }
}
