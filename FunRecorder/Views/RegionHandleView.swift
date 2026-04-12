import SwiftUI

/// A single draggable handle positioned at `xFraction` across the parent width.
struct RegionHandleView: View {
    let xFraction: Double
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let tooltip: String?
    let onDrag: (Double) -> Void  // Called with new fraction 0...1

    var body: some View {
        let xPos = CGFloat(xFraction) * containerWidth

        ZStack(alignment: .top) {
            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: containerHeight)

            // Grip indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: 14, height: 36)
                .overlay(
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 8, height: 1.5)
                        }
                    }
                )
                .offset(y: containerHeight / 2 - 18)

            if let tip = tooltip {
                Text(tip)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .offset(y: -28)
            }
        }
        // 44pt wide hit target per Apple HIG
        .frame(width: 44, height: containerHeight)
        .offset(x: xPos - 22)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("waveform"))
                .onChanged { value in
                    // value.location is absolute position in "waveform" coordinate space
                    let fraction = max(0, min(1, Double(value.location.x / containerWidth)))
                    onDrag(fraction)
                }
        )
    }
}
