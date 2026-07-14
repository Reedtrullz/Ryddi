import Foundation
import ReclaimerCore

extension DashboardModel {
    func refreshRemoteTargets() {
        remoteTargets = RemoteTargetResolver().targets()
        if remoteTargetInput.isEmpty, let first = remoteTargets.first {
            remoteTargetInput = first.input
        }
    }

    func probeRemoteTarget() async {
        let targetInput = remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetInput.isEmpty else {
            error = "Enter an SSH alias or host before probing."
            return
        }
        let activityID = activities.begin(.remote, message: "Probing remote target")
        defer { activities.finish(.remote, id: activityID) }
        do {
            let report = try await Task.detached {
                let target = try RemoteTargetResolver().resolve(targetInput)
                return RemoteProbeBuilder(target: target).probe()
            }.value
            remoteProbeReport = report
            _ = try AuditStore().save(remoteProbeReport: report)
            await loadAudit()
            error = report.commands.contains { $0.exitCode == 0 } ? nil : "Remote probe did not reach the target with read-only SSH commands."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scanRemoteTarget() async {
        let targetInput = remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetInput.isEmpty else {
            error = "Enter an SSH alias or host before scanning."
            return
        }
        let activityID = activities.begin(.remote, message: "Scanning remote target")
        defer { activities.finish(.remote, id: activityID) }
        do {
            let report = try await Task.detached {
                let target = try RemoteTargetResolver().resolve(targetInput)
                return RemoteScanBuilder(target: target).scan(preset: .vpsGeneral)
            }.value
            remoteScanReport = report
            _ = try AuditStore().save(remoteScanReport: report)
            await loadAudit()
            error = report.commands.contains { $0.exitCode == 0 } ? nil : "Remote scan did not reach the target with read-only SSH commands."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteRedactedReport() async {
        guard let report = remoteScanReport else {
            error = "Run a remote scan before exporting a remote report."
            return
        }
        let activityID = activities.begin(.remote, message: "Exporting remote report")
        defer { activities.finish(.remote, id: activityID) }
        do {
            let url = try await Task.detached {
                let privacy = ReportPrivacyOptions(pathStyle: .redacted)
                let markdown = RemoteReportBuilder.build(report: report, privacy: privacy).markdown
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-report-\(report.id).md")
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            lastRemoteReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteRedactedGrowthReport() async {
        let store = AuditStore()
        guard
            let current = recentRemoteScanReports.first,
            let previous = store.latestPreviousRemoteScanReport(forConcreteTarget: current.target, excludingReportID: current.id),
            remoteGrowthReport != nil
        else {
            error = "Remote growth export needs at least two saved remote scans."
            return
        }
        let activityID = activities.begin(.remote, message: "Exporting remote growth report")
        defer { activities.finish(.remote, id: activityID) }
        do {
            let url = try await Task.detached {
                let privacy = ReportPrivacyOptions(pathStyle: .redacted)
                let redacted = RemoteGrowthReportBuilder.build(
                    previous: previous,
                    current: current,
                    limit: 25,
                    privacy: privacy
                )
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-growth-\(current.id).md")
                try redacted.markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            lastRemoteGrowthReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteDogfoodReportFromAudit() async {
        guard let scan = recentRemoteScanReports.first else {
            error = "Remote dogfood export needs at least one saved remote scan."
            return
        }
        let store = AuditStore()
        let probe = store.latestRemoteProbeReport(forConcreteTarget: scan.target)
        let previous = store.latestPreviousRemoteScanReport(forConcreteTarget: scan.target, excludingReportID: scan.id)
        let activityID = activities.begin(.remote, message: "Exporting remote dogfood report")
        defer { activities.finish(.remote, id: activityID) }
        do {
            let report = RemoteDogfoodReportBuilder.build(
                probe: probe,
                scan: scan,
                growth: previous.map {
                    RemoteGrowthReportBuilder.build(
                        previous: $0,
                        current: scan,
                        privacy: ReportPrivacyOptions(pathStyle: .redacted)
                    )
                },
                privacy: ReportPrivacyOptions(pathStyle: .redacted)
            )
            let url = try await Task.detached {
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-dogfood-\(report.id).md")
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            remoteDogfoodReport = report
            lastRemoteDogfoodReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func syncRemoteDogfoodReport() {
        guard let scan = remoteScanReport else {
            if remoteDogfoodReport == nil {
                remoteDogfoodReport = recentRemoteDogfoodReports.first
            }
            return
        }
        remoteDogfoodReport = AuditStore().latestRemoteDogfoodReport(forConcreteTarget: scan.target)
    }

}
