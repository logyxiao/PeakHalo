import SwiftUI

struct ControlValueSlider: View {
    let value: Double
    let isEnabled: Bool
    let tint: Color
    let primaryColor: Color
    let secondaryColor: Color
    let onChange: (Double) -> Void

    @State private var transientValue: Double?

    private var displayValue: Double {
        transientValue ?? value
    }

    private var progress: CGFloat {
        CGFloat(min(1, max(0, displayValue / 100)))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let knobSize = CGFloat(10)
            let knobOffset = min(max(width * progress - knobSize / 2, 0), max(width - knobSize, 0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(secondaryColor.opacity(isEnabled ? 0.24 : 0.14))
                    .frame(height: 5)

                Capsule()
                    .fill(tint.opacity(isEnabled ? 1 : 0.34))
                    .frame(width: max(width * progress, 0), height: 5)

                Circle()
                    .fill(isEnabled ? tint : secondaryColor.opacity(0.42))
                    .overlay {
                        Circle()
                            .stroke(primaryColor.opacity(isEnabled ? 0.18 : 0), lineWidth: 0.5)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: tint.opacity(isEnabled ? 0.32 : 0), radius: 4, y: 1)
                    .offset(x: knobOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let nextValue = min(100, max(0, Double(gesture.location.x / width) * 100))
                        transientValue = nextValue
                        onChange(nextValue)
                    }
                    .onEnded { _ in
                        transientValue = nil
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(displayValue.rounded()))%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }

            let step = 5.0
            switch direction {
            case .increment:
                onChange(min(100, value + step))
            case .decrement:
                onChange(max(0, value - step))
            @unknown default:
                break
            }
        }
    }
}
