import SwiftUI

struct MetricMiniGraph: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard data.count > 1, size.width > 0, size.height > 0 else { return [] }

        let step = size.width / CGFloat(data.count - 1)
        return data.enumerated().map { index, value in
            let clamped = min(max(value, 0), 100)
            let x = CGFloat(index) * step
            let y = size.height * (1 - CGFloat(clamped / 100))
            return CGPoint(x: x, y: y)
        }
    }
}
