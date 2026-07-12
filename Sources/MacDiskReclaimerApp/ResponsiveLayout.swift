import CoreGraphics

enum DashboardLayoutClass: String, CaseIterable, Equatable {
    case compact
    case regular
    case wide

    static func resolve(width: CGFloat) -> DashboardLayoutClass {
        if width < 820 { return .compact }
        if width < 1_180 { return .regular }
        return .wide
    }
}
