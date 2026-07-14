import XCTest
@testable import ReclaimerCore

final class ExecutionReconciliationTests: XCTestCase {
    func testDoneParentRemovesParentAndDescendantsButKeepsSkippedSibling() {
        let parent = finding("/root/cache", id: "parent")
        let child = finding("/root/cache/child", id: "child")
        let sibling = finding("/root/keep", id: "sibling")
        let receipt = receipt(actions: [
            action("/root/cache", status: "done"),
            action("/root/keep", status: "skipped")
        ])

        let result = ExecutionReconciler.reconcile(
            findings: [parent, child, sibling],
            receipt: receipt
        )

        XCTAssertEqual(result.remainingFindings.map(\.path), ["/root/keep"])
        XCTAssertEqual(result.completedFindingIDs, [parent.id, child.id])
        XCTAssertEqual(result.completedPaths, ["/root/cache"])
        XCTAssertEqual(result.skippedPaths, ["/root/keep"])
        XCTAssertTrue(result.requiresVerificationScan)
    }

    func testSimilarPrefixIsNotTreatedAsDescendant() {
        let result = ExecutionReconciler.reconcile(
            findings: [finding("/root/cache"), finding("/root/cache-two")],
            receipt: receipt(actions: [action("/root/cache", status: "done")])
        )

        XCTAssertEqual(result.remainingFindings.map(\.path), ["/root/cache-two"])
    }

    func testOnlyExactDoneStatusRemovesFindingsAndErrorsRemainVisible() {
        let result = ExecutionReconciler.reconcile(
            findings: [
                finding("/root/lowercase-done"),
                finding("/root/titlecase-done"),
                finding("/root/error")
            ],
            receipt: receipt(actions: [
                action("/root/lowercase-done", status: "done"),
                action("/root/titlecase-done", status: "Done"),
                action("/root/error", status: "error")
            ])
        )

        XCTAssertEqual(
            result.remainingFindings.map(\.path),
            ["/root/titlecase-done", "/root/error"]
        )
        XCTAssertEqual(
            result.skippedPaths,
            ["/root/titlecase-done", "/root/error"]
        )
    }

    func testStandardizedReceiptPathMatchesFindingByComponents() {
        let result = ExecutionReconciler.reconcile(
            findings: [finding("/root/cache/child")],
            receipt: receipt(actions: [action("/root/other/../cache", status: "done")])
        )

        XCTAssertTrue(result.remainingFindings.isEmpty)
        XCTAssertEqual(result.completedPaths, ["/root/cache"])
    }

    func testPrivateVarAndVarAliasesReconcileAsTheSameFilesystemPath() {
        let result = ExecutionReconciler.reconcile(
            findings: [finding("/private/var/tmp/ryddi-task-3/cache/child")],
            receipt: receipt(actions: [
                action("/var/tmp/ryddi-task-3/cache", status: "done")
            ])
        )

        XCTAssertTrue(result.remainingFindings.isEmpty)
    }

    private func finding(_ path: String, id: String = UUID().uuidString) -> Finding {
        Finding(
            id: id,
            scopeName: "Fixture",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: 1,
            allocatedSize: 1,
            isDirectory: true,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [],
            evidence: []
        )
    }

    private func action(_ path: String, status: String) -> ExecutionActionReceipt {
        ExecutionActionReceipt(
            path: path,
            action: .trash,
            status: status,
            message: "Fixture"
        )
    }

    private func receipt(actions: [ExecutionActionReceipt]) -> ExecutionReceipt {
        ExecutionReceipt(
            ruleVersion: "rules-v1",
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: actions,
            userConfirmed: true
        )
    }
}
