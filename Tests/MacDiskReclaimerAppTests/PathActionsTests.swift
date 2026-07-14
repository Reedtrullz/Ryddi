import Foundation
import XCTest
@testable import MacDiskReclaimerApp

@MainActor
final class PathActionsTests: XCTestCase {
    func testRelaunchWaitsForSuccessfulCommandBeforeTerminating() async {
        let runner = ControlledRelaunchCommandRunner()
        let terminator = RecordingApplicationTerminator()
        let task = Task { @MainActor in
            await PathActions.relaunchApplication(
                commandRunner: runner,
                applicationTerminator: terminator,
                applicationURL: URL(fileURLWithPath: "/Applications/Ryddi.app")
            )
        }

        await runner.waitUntilStarted()
        XCTAssertEqual(terminator.callCount, 0)

        await runner.finish(exitStatus: 0)
        let result = await task.value

        guard case .success = result else {
            return XCTFail("Expected a successful relaunch result")
        }
        XCTAssertEqual(terminator.callCount, 1)
    }

    func testRelaunchLaunchFailureKeepsApplicationRunning() async {
        let terminator = RecordingApplicationTerminator()

        let result = await PathActions.relaunchApplication(
            commandRunner: FixedRelaunchCommandRunner(outcome: .launchFailure),
            applicationTerminator: terminator,
            applicationURL: URL(fileURLWithPath: "/Applications/Ryddi.app")
        )

        XCTAssertEqual(result.failure, .launchFailed)
        XCTAssertEqual(terminator.callCount, 0)
    }

    func testRelaunchNonzeroExitKeepsApplicationRunning() async {
        let terminator = RecordingApplicationTerminator()

        let result = await PathActions.relaunchApplication(
            commandRunner: FixedRelaunchCommandRunner(outcome: .exitStatus(17)),
            applicationTerminator: terminator,
            applicationURL: URL(fileURLWithPath: "/Applications/Ryddi.app")
        )

        XCTAssertEqual(result.failure, .commandFailed(exitStatus: 17))
        XCTAssertEqual(terminator.callCount, 0)
    }
}

private extension Result where Success == Void, Failure == RelaunchApplicationFailure {
    var failure: Failure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

private actor ControlledRelaunchCommandRunner: RelaunchCommandRunning {
    private var started = false
    private var continuation: CheckedContinuation<Int32, Never>?

    func runOpenCommand(for applicationURL: URL) async throws -> Int32 {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func finish(exitStatus: Int32) {
        continuation?.resume(returning: exitStatus)
        continuation = nil
    }
}

private struct FixedRelaunchCommandRunner: RelaunchCommandRunning {
    enum Outcome {
        case launchFailure
        case exitStatus(Int32)
    }

    let outcome: Outcome

    func runOpenCommand(for applicationURL: URL) async throws -> Int32 {
        switch outcome {
        case .launchFailure:
            throw TestLaunchError()
        case .exitStatus(let status):
            return status
        }
    }
}

private struct TestLaunchError: Error {}

@MainActor
private final class RecordingApplicationTerminator: ApplicationTerminating {
    private(set) var callCount = 0

    func terminate() {
        callCount += 1
    }
}
