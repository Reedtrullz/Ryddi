import Foundation
import Observation
import Sparkle

@MainActor
protocol RyddiUpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> NSKeyValueObservation?
}

extension RyddiUpdateChecking {
    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> NSKeyValueObservation? {
        nil
    }
}

@MainActor
final class SparkleUpdateChecker: RyddiUpdateChecking {
    private let controller: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> NSKeyValueObservation? {
        controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in
                handler(canCheck)
            }
        }
    }
}

@MainActor
@Observable
final class RyddiUpdateController {
    @ObservationIgnored private let checker: any RyddiUpdateChecking
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private(set) var canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool {
        didSet {
            checker.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    convenience init() {
        self.init(checker: SparkleUpdateChecker())
    }

    init(checker: any RyddiUpdateChecking) {
        self.checker = checker
        canCheckForUpdates = checker.canCheckForUpdates
        automaticallyChecksForUpdates = checker.automaticallyChecksForUpdates
        canCheckObservation = checker.observeCanCheckForUpdates { [weak self] canCheck in
            self?.canCheckForUpdates = canCheck
        }
    }

    func updateToLatestVersion() {
        guard canCheckForUpdates else { return }
        checker.checkForUpdates()
    }
}
