import SwiftUI
import ReclaimerCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct PackageCacheReviewView: View {
    let model: DashboardModel
    let navigate: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Package Cache Review")
                            .font(.largeTitle.bold())
                        Text("Review Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots separately from config and auth state.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewPackageCaches() }
                    } label: {
                        Label("Review Package Caches", systemImage: "shippingbox")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.packageCacheReview {
                    let lane = PackageReclaimLaneBuilder.build(from: report)

                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: ByteFormat.string(report.candidateBytes))
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Cache roots", value: "\(report.rootSummaries.count)")
                        MetricTile(title: "Protected config", value: "\(report.protectedConfigRoots.count)")
                    }

                    PackageReclaimLaneView(report: lane) {
                        model.recordReviewSelection(.useNativeTool)
                        navigate("Queues")
                    }

                    SectionBox(title: "By Package Manager") {
                        if report.managerSummaries.isEmpty {
                            Text("No package cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.managerSummaries) { summary in
                                    HStack {
                                        Text(summary.name)
                                        Spacer()
                                        Text("\(summary.itemCount)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        Text(ByteFormat.string(summary.allocatedSize))
                                            .frame(width: 90, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Cache Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.manager.label)
                                            .font(.caption.weight(.semibold))
                                        Text(root.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(ByteFormat.string(root.allocatedSize))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Text(root.rootPath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(root.nativeCleanupHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(root.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Cache Items") {
                        if report.largestItems.isEmpty {
                            Text("No package cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Manager").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 122, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(40)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.manager.label)
                                                .frame(width: 92, alignment: .leading)
                                            Text(item.kind.label)
                                                .frame(width: 122, alignment: .leading)
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(item.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Protected Config And Auth Paths") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.protectedConfigRoots) { protectedRoot in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(protectedRoot.manager.label)
                                            .font(.caption.weight(.semibold))
                                        Text(protectedRoot.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(protectedRoot.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(protectedRoot.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No package cache review yet", systemImage: "shippingbox", description: Text("Run Package Cache Review to inspect package-manager cache roots without measuring or modifying protected config/auth state."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct PackageReclaimLaneView: View {
    let report: PackageReclaimLaneReport
    let onOpenNativeReview: () -> Void

    var body: some View {
        SectionBox(title: "Native Preview Lane") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                    MetricTile(title: "Preview scope", value: ByteFormat.string(report.totalPreviewBytes))
                    MetricTile(title: "Managers", value: "\(report.managerReports.count)")
                }

                if report.managerReports.isEmpty {
                    Text("No package manager cache summaries were found.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.managerReports) { manager in
                            packageManagerRow(manager)
                            if manager.id != report.managerReports.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    onOpenNativeReview()
                } label: {
                    Label("Open Use Native Tool Review", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .help("Open the review queue where native dry-run receipts can be created from individual findings.")
            }
        }
    }

    private func packageManagerRow(_ manager: PackageReclaimManagerReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(manager.managerName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(ByteFormat.string(manager.cacheBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(manager.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            commandLine(label: "Preview", command: manager.previewCommand, fallback: "Manual review")
            commandLine(label: "Cleanup", command: manager.cleanupCommand, fallback: "No allowlisted cleanup command")
            ForEach(manager.commandCards) { card in
                packageCommandCard(card)
            }
        }
    }

    private func packageCommandCard(_ card: PackageReclaimCommandCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(card.title)
                    .font(.caption2.weight(.semibold))
                Text(card.review == .manualReview ? "Manual review" : "Safe action")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(card.review == .manualReview ? .orange : .green)
                Text(card.role.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(card.argv.joined(separator: " "))
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(card.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private func commandLine(label: String, command: [String], fallback: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(command.isEmpty ? fallback : command.joined(separator: " "))
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct ProjectDependencyReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Dependencies")
                            .font(.largeTitle.bold())
                        Text("Review project-local dependencies and build artifacts such as node_modules, .venv, .build, target, Pods, .dart_tool, framework caches, and mobile build output.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewProjectDependencies() }
                    } label: {
                        Label("Review Projects", systemImage: "folder")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.projectDependencyReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: ByteFormat.string(report.candidateBytes))
                        MetricTile(title: "Rebuildable", value: ByteFormat.string(report.rebuildableBytes))
                        MetricTile(title: "Needs review", value: ByteFormat.string(report.reviewRequiredBytes))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Project roots", value: "\(report.rootSummaries.count)")
                        MetricTile(title: "Workspaces", value: "\(report.workspaceRootCount)")
                        MetricTile(title: "VCS changes", value: "\(report.projectsWithDirtyVCSCount)")
                        MetricTile(title: "Skipped policy", value: "\(report.policySkippedProjects.count)")
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Ecosystem") {
                            if report.ecosystemSummaries.isEmpty {
                                Text("No project dependency candidates found in readable roots.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.ecosystemSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "By Kind") {
                            if report.kindSummaries.isEmpty {
                                Text("No project dependency kinds found.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.kindSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "By VCS") {
                            if report.vcsSummaries.isEmpty {
                                Text("No VCS state was reported.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.vcsSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "By Policy") {
                            if report.policySummaries.isEmpty {
                                Text("No saved project policies matched measured items.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.policySummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Tool") {
                            if report.toolSummaries.isEmpty {
                                Text("No project tool evidence was detected.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.toolSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "Package Scripts") {
                            if report.scriptSummaries.isEmpty {
                                Text("No package.json scripts were accepted for review.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.scriptSummaries.prefix(12)) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "Script Risk") {
                            if report.scriptRiskSummaries.isEmpty {
                                Text("No package.json script command previews were classified.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.scriptRiskSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "By Workspace") {
                            if report.workspaceSummaries.isEmpty {
                                Text("No workspace or monorepo evidence was detected.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.workspaceSummaries.prefix(12)) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.itemCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Project Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.permissionState.rawValue)
                                            .font(.caption.weight(.semibold))
                                        Text("\(root.candidateCount) candidate(s)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(ByteFormat.string(root.allocatedSize))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Text(root.rootPath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(root.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Project Dependency Items") {
                        if report.largestItems.isEmpty {
                            Text("No project dependency candidates found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Ecosystem").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 142, alignment: .leading)
                                    Text("VCS").frame(width: 112, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(40)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.ecosystem.label)
                                                .frame(width: 92, alignment: .leading)
                                            Text(item.kind.label)
                                                .frame(width: 142, alignment: .leading)
                                            Text(item.vcsInfo.state.label)
                                                .frame(width: 112, alignment: .leading)
                                            Text(item.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(item.projectName)
                                            .font(.caption2.weight(.semibold))
                                        if item.toolingInfo.toolName != nil {
                                            Text("\(item.toolingInfo.toolLabel)\(item.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if !item.toolingInfo.packageScripts.isEmpty {
                                            Text("Scripts: \(item.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        ForEach(item.toolingInfo.scriptReviews.prefix(4)) { review in
                                            Text("Script review: \(review.name) [\(review.risk.label)] \(review.commandPreview)")
                                                .font(.caption2)
                                                .foregroundStyle(review.isCommandHintEligible ? Color.secondary : Color.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if item.workspaceInfo.isWorkspace {
                                            Text("Workspace: \(item.workspaceInfo.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let workspaceRoot = item.workspaceInfo.rootPath {
                                                Text(workspaceRoot)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                    .textSelection(.enabled)
                                            }
                                            if !item.workspaceInfo.packagePatterns.isEmpty {
                                                Text("Workspace packages: \(item.workspaceInfo.packagePatterns.prefix(12).joined(separator: ", "))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        Text(item.vcsInfo.summary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        ForEach(item.commandHints.prefix(3), id: \.id) { command in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(command.command) - \(command.purpose)")
                                                if let workingDirectory = command.workingDirectory {
                                                    Text("cwd: \(workingDirectory)")
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                }
                                                if let context = command.context {
                                                    Text(context)
                                                }
                                            }
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if let decision = item.projectPolicyDecision {
                                            Text("\(decision.label)\(item.projectPolicyReason.map { ": \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text(item.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Protected Project Roots") {
                        if report.protectedProjectRoots.isEmpty {
                            Text("No protected project roots were inferred from candidates.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.protectedProjectRoots) { protectedRoot in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(protectedRoot.projectName)
                                            .font(.caption.weight(.semibold))
                                        Text(protectedRoot.projectRootPath)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        if !protectedRoot.manifestHints.isEmpty {
                                            Text(protectedRoot.manifestHints.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if protectedRoot.toolingInfo.toolName != nil {
                                            Text("\(protectedRoot.toolingInfo.toolLabel)\(protectedRoot.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if !protectedRoot.toolingInfo.packageScripts.isEmpty {
                                            Text("Scripts: \(protectedRoot.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        ForEach(protectedRoot.toolingInfo.scriptReviews.prefix(4)) { review in
                                            Text("Script review: \(review.name) [\(review.risk.label)] \(review.commandPreview)")
                                                .font(.caption2)
                                                .foregroundStyle(review.isCommandHintEligible ? Color.secondary : Color.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if protectedRoot.workspaceInfo.isWorkspace {
                                            Text("Workspace: \(protectedRoot.workspaceInfo.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let workspaceRoot = protectedRoot.workspaceInfo.rootPath {
                                                Text(workspaceRoot)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        Text("\(protectedRoot.vcsInfo.state.label): \(protectedRoot.vcsInfo.summary)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let decision = protectedRoot.projectPolicyDecision {
                                            Text("\(decision.label)\(protectedRoot.projectPolicyReason.map { ": \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text(protectedRoot.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionBox(title: "Skipped By Policy") {
                        if report.policySkippedProjects.isEmpty {
                            Text("No projects were skipped by saved Project Dependencies policy.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.policySkippedProjects) { skipped in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(skipped.projectName) - \(skipped.decision.label)")
                                            .font(.caption.weight(.semibold))
                                        Text(skipped.projectRootPath)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        if let reason = skipped.reason {
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let workspace = skipped.workspaceInfo, workspace.isWorkspace {
                                            Text("Workspace: \(workspace.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text(skipped.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No project dependency review yet", systemImage: "folder", description: Text("Run Project Dependencies to inspect project-local dependency and build folders without modifying project files."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct DeviceBackupReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device Backups Review")
                            .font(.largeTitle.bold())
                        Text("Review local iPhone and iPad MobileSync backups as valuable restore points, with size, age, encryption, and metadata evidence.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewDeviceBackups() }
                    } label: {
                        Label("Review Device Backups", systemImage: "iphone")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.deviceBackupReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Backups", value: "\(report.backupCount)")
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Old review", value: ByteFormat.string(report.staleBackupBytes))
                        MetricTile(title: "Encrypted", value: ByteFormat.string(report.encryptedBackupBytes))
                        MetricTile(title: "Metadata gaps", value: "\(report.missingMetadataCount)")
                    }

                    SectionBox(title: "Backup Root") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(report.permissionState.rawValue)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(ByteFormat.string(report.totalAllocatedSize))
                                    .font(.caption.monospacedDigit())
                            }
                            Text(report.rootPath)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            ForEach(report.notes, id: \.self) { note in
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Encryption") {
                            if report.encryptionSummaries.isEmpty {
                                Text("No backup encryption evidence yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.encryptionSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.backupCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }

                        SectionBox(title: "By Metadata") {
                            if report.metadataSummaries.isEmpty {
                                Text("No backup metadata evidence yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.metadataSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.backupCount)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(summary.allocatedSize))
                                                .frame(width: 90, alignment: .trailing)
                                                .monospacedDigit()
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Largest Device Backups") {
                        if report.largestBackups.isEmpty {
                            Text("No device backups found at the configured root.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Encryption").frame(width: 96, alignment: .leading)
                                    Text("Metadata").frame(width: 86, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
                                    Text("Backup")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestBackups.prefix(40)) { backup in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(backup.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(backup.encryptionState.label)
                                                .frame(width: 96, alignment: .leading)
                                            Text(backup.metadataState.label)
                                                .frame(width: 86, alignment: .leading)
                                            Text(backup.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
                                            Text(backup.displayName)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(backup.path)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        Text(backup.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No device backup review yet", systemImage: "iphone", description: Text("Run Device Backups Review to inspect MobileSync backup size, age, encryption, and metadata without modifying backups."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct XcodeReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Xcode Review")
                            .font(.largeTitle.bold())
                        Text("Review Xcode build caches, archives, device support, simulator state, runtimes, logs, and protected developer settings separately.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewXcode() }
                    } label: {
                        Label("Review Xcode", systemImage: "hammer")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.xcodeReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Rebuildable", value: ByteFormat.string(report.rebuildableCacheBytes))
                        MetricTile(title: "Needs review", value: ByteFormat.string(report.reviewRequiredBytes))
                        MetricTile(title: "Simulator state", value: ByteFormat.string(report.simulatorStateBytes))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Xcode roots", value: "\(report.rootSummaries.count)")
                    }

                    SectionBox(title: "By Xcode Kind") {
                        if report.kindSummaries.isEmpty {
                            Text("No Xcode items found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.kindSummaries) { summary in
                                    HStack {
                                        Text(summary.name)
                                        Spacer()
                                        Text("\(summary.itemCount)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        Text(ByteFormat.string(summary.allocatedSize))
                                            .frame(width: 90, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Xcode Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.kind.label)
                                            .font(.caption.weight(.semibold))
                                        Text(root.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(ByteFormat.string(root.allocatedSize))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Text(root.rootPath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(root.nativeCleanupHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(root.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Xcode Items") {
                        if report.largestItems.isEmpty {
                            Text("No Xcode items found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 142, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(40)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.kind.label)
                                                .frame(width: 142, alignment: .leading)
                                            Text(item.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(item.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Protected Xcode Developer State") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.protectedStateRoots) { protectedRoot in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(protectedRoot.permissionState.rawValue)
                                        .font(.caption.weight(.semibold))
                                    Text(protectedRoot.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(protectedRoot.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No Xcode review yet", systemImage: "hammer", description: Text("Run Xcode Review to inspect developer caches, archives, device support, simulator state, and protected Xcode settings without modifying files."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}
