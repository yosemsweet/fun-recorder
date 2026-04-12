import SwiftUI

/// Canvas overlay drawing 16th-note beat grid lines.
struct BeatGridOverlay: View {
    let grid: BeatGrid
    let duration: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            guard duration > 0 else { return }

            for (index, position) in grid.sixteenthPositions.enumerated() {
                let x = CGFloat(position / duration) * size.width
                let isDownbeat = index % 16 == 0
                let isQuarterNote = index % 4 == 0
                let lineHeightFraction: CGFloat = isDownbeat ? 0.7 : isQuarterNote ? 0.5 : 0.25
                let opacity: CGFloat = isDownbeat ? 0.6 : isQuarterNote ? 0.4 : 0.2
                let lineH = size.height * lineHeightFraction
                let rect = CGRect(x: x, y: (size.height - lineH) / 2, width: 1, height: lineH)
                ctx.fill(Path(rect), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}
