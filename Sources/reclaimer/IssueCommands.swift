import Foundation
import ReclaimerCore

extension ReclaimerCLI {
    static func issue(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("issue requires package")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        switch subcommand {
        case "package":
            try issuePackage(options: options)
        default:
            throw CLIError.message("issue supports only: package")
        }
    }

    private static func issuePackage(options: ParsedOptions) throws {
        guard let outputPath = options.outputPath else {
            throw CLIError.message("issue package requires --output DIR")
        }
        let manifest = try IssuePackageExporter.export(
            to: URL(fileURLWithPath: outputPath),
            store: AuditStore(),
            options: IssuePackageExportOptions(
                pathStyle: try issuePackagePathStyle(options.value(after: "--path-style") ?? "redacted"),
                includeLatestRemoteReport: options.args.contains("--include-remote"),
                replaceExisting: options.args.contains("--replace"),
                appVersion: "reclaimer-cli"
            )
        )
        if options.json {
            try printJSON(manifest)
        } else {
            print("Ryddi issue package")
            print("Output: \(URL(fileURLWithPath: outputPath).standardizedFileURL.path)")
            print("Path style: \(manifest.pathStyle.rawValue)")
            print("Files:")
            for file in manifest.includedFiles {
                print("- \(file)")
            }
            print("\nNon-claims")
            for note in manifest.nonClaims {
                print("- \(note)")
            }
        }
    }

    private static func issuePackagePathStyle(_ raw: String) throws -> IssuePackagePathStyle {
        switch raw {
        case IssuePackagePathStyle.redacted.rawValue:
            return .redacted
        case IssuePackagePathStyle.homeRelative.rawValue, "homeRelative":
            return .homeRelative
        default:
            throw CLIError.message("issue package --path-style must be redacted or home-relative")
        }
    }
}
