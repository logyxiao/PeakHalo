import SwiftUI

struct NotchSurfaceShape: Shape {
    var style: NotchAppearanceStyle

    func path(in rect: CGRect) -> Path {
        switch style {
        case .dynamicIsland:
            return Path(roundedRect: rect, cornerRadius: rect.height / 2)
        case .standardNotch:
            return attachedNotchPath(in: rect)
        }
    }

    private func attachedNotchPath(in rect: CGRect) -> Path {
        let bottomRadius = min(rect.height * 0.46, 18)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()

        return path
    }
}
