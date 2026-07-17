import CoreGraphics
import ReclaimerCore

struct TreemapLayout {
    func rectangles(
        for nodes: [GuidedMapNode],
        in bounds: CGRect
    ) -> [String: CGRect] {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return [:] }
        let ordered = nodes
            .filter { $0.allocatedBytes > 0 }
            .sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.id < $1.id }
                return $0.allocatedBytes > $1.allocatedBytes
            }
        let total = ordered.reduce(Double(0)) { $0 + Double($1.allocatedBytes) }
        guard total > 0, total.isFinite else { return [:] }

        var result: [String: CGRect] = [:]
        partition(ordered, in: bounds, into: &result)
        return result
    }

    private func partition(
        _ nodes: [GuidedMapNode],
        in bounds: CGRect,
        into result: inout [String: CGRect]
    ) {
        guard !nodes.isEmpty else { return }
        guard nodes.count > 1 else {
            result[nodes[0].id] = bounds
            return
        }
        let total = nodes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        var leftTotal: Int64 = 0
        var splitIndex = 1
        for index in 0..<(nodes.count - 1) {
            let next = leftTotal + nodes[index].allocatedBytes
            if abs(Double(total) / 2 - Double(next)) <= abs(Double(total) / 2 - Double(leftTotal)) {
                leftTotal = next
                splitIndex = index + 1
            } else {
                break
            }
        }
        let fraction = total > 0 ? CGFloat(Double(leftTotal) / Double(total)) : 0.5
        let left = Array(nodes[..<splitIndex])
        let right = Array(nodes[splitIndex...])
        if bounds.width >= bounds.height {
            let leftWidth = bounds.width * fraction
            partition(left, in: CGRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: bounds.height), into: &result)
            partition(right, in: CGRect(x: bounds.minX + leftWidth, y: bounds.minY, width: bounds.width - leftWidth, height: bounds.height), into: &result)
        } else {
            let topHeight = bounds.height * fraction
            partition(left, in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: topHeight), into: &result)
            partition(right, in: CGRect(x: bounds.minX, y: bounds.minY + topHeight, width: bounds.width, height: bounds.height - topHeight), into: &result)
        }
    }
}
