import SwiftUI

/// Scrolling amplitude bar visualization shown while recording.
struct LiveWaveformView: View {
    let levels: [Float]

    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let maxBars = Int(size.width / (barWidth + barGap))
                let visible = Array(levels.suffix(maxBars))
                let midY = size.height / 2

                for (i, level) in visible.enumerated() {
                    let x = CGFloat(i) * (barWidth + barGap)
                    let barHeight = max(2, CGFloat(level) * size.height * 0.9)
                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor))
                }
            }
        }
    }
}

#Preview {
    LiveWaveformView(levels: (0..<100).map { _ in Float.random(in: 0.05...0.8) })
        .frame(height: 120)
        .background(.black)
}
