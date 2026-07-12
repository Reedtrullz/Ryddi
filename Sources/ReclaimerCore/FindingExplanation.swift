import Foundation

public struct FindingExplanationReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let finding: Finding
    public let summary: String
    public let whatThisIs: [String]
    public let whyMatched: [String]
    public let riskSummary: String
    public let cleanupPermission: String
    public let exactAction: String
    public let removalEffect: String
    public let recovery: [String]
    public let conditions: [String]
    public let nextSteps: [String]
    public let nativeToolReceipt: NativeToolReceipt?
    public let guidanceCommands: [String]
    public let nonClaims: [String]
}

public enum FindingExplanationBuilder {
    public static let defaultNonClaims = [
        "This explanation does not execute cleanup or prove that cleanup will succeed.",
        "Cleanup permission still requires the normal plan, dry-run, open-file, permission, Trash, APFS, and final rule revalidation gates.",
        "Size shown here may not equal immediate free-space gain because of APFS snapshots, clones, hard links, compression, purgeable storage, Trash behavior, and concurrent system activity."
    ]

    public static func build(
        for finding: Finding,
        generatedAt: Date = Date()
    ) -> FindingExplanationReport {
        let nativeReceipt = NativeToolGuidance.receipt(for: finding)
        let guidance = nativeReceipt == nil ? CleanupGuidance.commands(for: finding) : []
        return FindingExplanationReport(
            generatedAt: generatedAt,
            finding: finding,
            summary: summary(for: finding),
            whatThisIs: whatThisIs(for: finding),
            whyMatched: whyMatched(for: finding),
            riskSummary: riskSummary(for: finding),
            cleanupPermission: cleanupPermission(for: finding),
            exactAction: exactAction(for: finding),
            removalEffect: removalEffect(for: finding),
            recovery: recovery(for: finding),
            conditions: conditions(for: finding),
            nextSteps: nextSteps(for: finding, nativeReceipt: nativeReceipt, guidance: guidance),
            nativeToolReceipt: nativeReceipt,
            guidanceCommands: guidance,
            nonClaims: defaultNonClaims
        )
    }

    private static func summary(for finding: Finding) -> String {
        "\(finding.displayName) is classified as \(finding.safetyClass.label) with action \(finding.actionKind.label)."
    }

    private static func whatThisIs(for finding: Finding) -> [String] {
        var lines = [
            "Path type: \(finding.isSymbolicLink ? "symbolic link" : (finding.isDirectory ? "directory" : "file")).",
            "Scan scope: \(finding.scopeName).",
            "Owner hint: \(finding.ownerHint ?? "Unknown").",
            "Category: \(finding.primaryCategory).",
            "Size: \(ByteFormat.string(finding.allocatedSize)) allocated; \(ByteFormat.string(finding.logicalSize)) logical.",
            "Accounting: \(finding.storageAccountingNote)"
        ]
        if let modificationDate = finding.modificationDate {
            lines.append("Modified: \(ISO8601DateFormatter().string(from: modificationDate)).")
            if let age = finding.ageInDays(referenceDate: Date()) {
                lines.append("Age: \(age) day(s).")
            }
        }
        if let open = finding.openFileStatus {
            if let failure = open.checkFailed {
                lines.append("Open-file check failed: \(failure).")
            } else if open.isOpen {
                lines.append("Open handles: \(open.processSummary.isEmpty ? "reported open" : open.processSummary.joined(separator: ", ")).")
            } else {
                lines.append("Open handles: none reported at scan time.")
            }
        } else {
            lines.append("Open handles: not checked in this finding.")
        }
        return lines
    }

    private static func whyMatched(for finding: Finding) -> [String] {
        var lines: [String] = []
        if finding.ruleMatches.isEmpty {
            lines.append("No bundled or enabled user rule matched this path; Ryddi keeps it review-only.")
        } else {
            for match in finding.ruleMatches {
                lines.append("\(match.title) (\(match.ruleID)) matched in category \(match.category).")
                for evidence in match.evidence {
                    lines.append(evidence)
                }
            }
        }
        for evidence in finding.evidence where !lines.contains(evidence.message) {
            lines.append(evidence.message)
        }
        return lines
    }

    private static func riskSummary(for finding: Finding) -> String {
        switch finding.safetyClass {
        case .autoSafe:
            "Low-risk only because the current rule classifies this as rebuildable or disposable cache/temp-style data; final checks still apply."
        case .safeAfterCondition:
            "Condition-gated data that may be safe only after the owning app/tool is quit or a native cleanup workflow is reviewed."
        case .reviewRequired:
            "Manual review required; size, age, or path pattern is evidence for inspection, not permission to remove."
        case .preserveByDefault:
            "Valuable or user/app-owned state; preserve unless the user explicitly decides otherwise with a recovery plan."
        case .neverTouch:
            "Blocked by policy; credentials, config, personal assets, app state, or similarly sensitive data must not be cleaned automatically."
        }
    }

    private static func cleanupPermission(for finding: Finding) -> String {
        if finding.isSymbolicLink {
            return "Blocked: symbolic links require manual review and are not reclaimed automatically."
        }
        if let open = finding.openFileStatus {
            if let failure = open.checkFailed {
                return "Blocked: open-file check failed (\(failure))."
            }
            if open.isOpen {
                return "Blocked until active open handles are gone."
            }
        }
        switch (finding.safetyClass, finding.actionKind) {
        case (.autoSafe, .deleteCache), (.autoSafe, .trash), (.autoSafe, .quarantineHold):
            return "Eligible for dry-run planning after final open-file, permission, policy, and rule revalidation checks."
        case (_, .nativeToolCommand):
            return "Not executed by Ryddi; use the owning native tool after review."
        case (_, .reportOnly):
            return "Report-only; no cleanup action is proposed."
        case (_, .openGuidance):
            return "Guidance-only; inspect manually before any Finder or tool action."
        case (.preserveByDefault, _):
            return "Not selected automatically because this is preserve-by-default data."
        case (.neverTouch, _):
            return "Never-touch data; Ryddi must not select it for cleanup."
        case (.reviewRequired, _):
            return "Review-required data; not selected by auto-safe plans."
        case (.safeAfterCondition, _):
            return "Condition-gated data; not selected until required conditions are verified."
        case (.autoSafe, .compress):
            return "Compression still requires an explicit dry-run plan and final revalidation."
        }
    }

    private static func exactAction(for finding: Finding) -> String {
        switch finding.actionKind {
        case .reportOnly:
            return "Report only: leave the path untouched and record evidence."
        case .trash:
            return "Trash candidate: review this user-visible path in Finder; Ryddi does not move it automatically."
        case .deleteCache:
            return "Cache candidate: review the rebuildable cache path in Finder or with its owning tool; Ryddi does not delete it automatically."
        case .compress:
            return "Compression candidate: review this cold file or history in Finder; Ryddi does not compress it automatically."
        case .quarantineHold:
            return "Holding candidate: review the item in Finder; Ryddi does not move it into the holding area automatically."
        case .nativeToolCommand:
            return "Use native tool: inspect and run the owning tool's cleanup command yourself; Ryddi only records guidance."
        case .openGuidance:
            return "Open guidance: inspect with Finder, Quick Look, Terminal, app UI, or the owning tool before acting."
        }
    }

    private static func removalEffect(for finding: Finding) -> String {
        switch finding.actionKind {
        case .reportOnly:
            return "No removal effect; this row exists for evidence and safety review."
        case .trash:
            return "No Ryddi filesystem mutation; use Finder Trash manually after review if appropriate."
        case .deleteCache:
            return "No Ryddi filesystem mutation; the owning app/tool may rebuild this cache if you remove it manually."
        case .compress:
            return "No Ryddi filesystem mutation; compression remains a manual archive decision."
        case .quarantineHold:
            return "No Ryddi filesystem mutation; holding records are retained for manual Finder recovery only."
        case .nativeToolCommand:
            return "No Ryddi filesystem mutation; effect depends on the native command the user chooses to run."
        case .openGuidance:
            return "No Ryddi filesystem mutation; any change must happen through an explicit manual action."
        }
    }

    private static func recovery(for finding: Finding) -> [String] {
        let recoveries = finding.ruleMatches.compactMap(\.recovery).filter { !$0.isEmpty }
        if !recoveries.isEmpty {
            return Array(Set(recoveries)).sorted()
        }
        switch finding.actionKind {
        case .trash:
            return ["Review Finder Trash or restore from backup if removed."]
        case .deleteCache:
            return ["Rebuild or re-download cache data through the owning app/tool when available."]
        case .compress:
            return ["Keep the compressed copy and restore from backup if the original is later removed."]
        case .quarantineHold:
            return ["Reveal any existing holding record in Finder and move it manually after review."]
        case .nativeToolCommand:
            return ["Use the native tool's rebuild, pull, install, or backup restore path as appropriate."]
        case .reportOnly, .openGuidance:
            return ["No Ryddi recovery action is needed because this explanation does not mutate files."]
        }
    }

    private static func conditions(for finding: Finding) -> [String] {
        var conditions = finding.ruleMatches.flatMap(\.conditions)
        if finding.isSymbolicLink {
            conditions.append("Review symbolic link target manually.")
        }
        if let open = finding.openFileStatus {
            if let failure = open.checkFailed {
                conditions.append("Resolve open-file check failure: \(failure).")
            } else if open.isOpen {
                conditions.append("Quit or stop processes using this path: \(open.processSummary.joined(separator: ", ")).")
            } else {
                conditions.append("No active open file handle was reported at scan time.")
            }
        } else {
            conditions.append("Run a plan or active-handle review to check open files before cleanup.")
        }
        return conditions
    }

    private static func nextSteps(
        for finding: Finding,
        nativeReceipt: NativeToolReceipt?,
        guidance: [String]
    ) -> [String] {
        if let nativeReceipt {
            return ["Review native-tool commands before acting."] + nativeReceipt.commands.map { "\($0.command) - \($0.purpose)" }
        }
        if !guidance.isEmpty {
            return guidance
        }
        switch finding.safetyClass {
        case .autoSafe:
            return ["Build a dry-run plan, review the receipt, then confirm only if the current plan still matches your intent."]
        case .safeAfterCondition:
            return ["Satisfy the listed conditions first, then rerun scan/plan so Ryddi can re-check current state."]
        case .reviewRequired:
            return ["Open the item in Finder or Quick Look and decide manually whether to keep, archive, Trash, or exclude it."]
        case .preserveByDefault:
            return ["Keep it unless you have a specific backup/recovery plan and understand the owning app's state."]
        case .neverTouch:
            return ["Leave it alone or restore from backup if it was changed outside Ryddi."]
        }
    }
}
