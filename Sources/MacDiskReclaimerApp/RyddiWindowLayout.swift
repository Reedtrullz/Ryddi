import SwiftUI

enum RyddiWindowLayout {
    static let minimumContentWidth: CGFloat = 1260
    static let minimumContentHeight: CGFloat = 760
    static let defaultContentWidth: CGFloat = 1480
    static let defaultContentHeight: CGFloat = 940
    static let topOffenderTableMinimumWidth: CGFloat = 1160
}

enum DashboardResponsiveGrid {
    static var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 320), spacing: 12, alignment: .top)]
    }

    static var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 10, alignment: .leading)]
    }
}
