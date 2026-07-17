import XCTest
import ReclaimerCore
@testable import MacDiskReclaimerApp

final class TreemapLayoutTests: XCTestCase {
    func testRectanglesAreDeterministicBoundedAndNonOverlapping() {
        let nodes = [
            node("a", bytes: 60),
            node("b", bytes: 30),
            node("c", bytes: 10)
        ]
        let bounds = CGRect(x: 10, y: 20, width: 500, height: 240)
        let first = TreemapLayout().rectangles(for: nodes, in: bounds)
        let second = TreemapLayout().rectangles(for: nodes, in: bounds)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 3)
        for frame in first.values {
            XCTAssertTrue(bounds.contains(frame))
            XCTAssertGreaterThanOrEqual(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.height, 0)
        }
        let frames = Array(first.values)
        for lhs in frames.indices {
            for rhs in frames.indices where lhs < rhs {
                let intersection = frames[lhs].intersection(frames[rhs])
                XCTAssertTrue(intersection.isNull || intersection.width == 0 || intersection.height == 0)
            }
        }
        let aArea = (first["a"]?.width ?? 0) * (first["a"]?.height ?? 0)
        XCTAssertEqual(aArea / (bounds.width * bounds.height), 0.6, accuracy: 0.001)
    }

    func testInvalidAndZeroInputsReturnNoRectangles() {
        XCTAssertTrue(TreemapLayout().rectangles(for: [], in: .zero).isEmpty)
        XCTAssertTrue(TreemapLayout().rectangles(for: [node("zero", bytes: 0)], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    private func node(_ id: String, bytes: Int64) -> GuidedMapNode {
        GuidedMapNode(
            id: id,
            parentID: "root",
            path: "/\(id)",
            displayName: id,
            allocatedBytes: bytes,
            category: .otherMeasured,
            measurementState: .complete,
            kind: .item,
            childIDs: []
        )
    }
}
