import SwiftUI

/// Canvas overlay that dims audio outside the selected region.
struct RegionHighlightView: View {
    let startFraction: Double
    let endFraction: Double

    var body: some View {
        Canvas { ctx, size in
            let startX = CGFloat(startFraction) * size.width
            let endX = CGFloat(endFraction) * size.width
            let dimColor = GraphicsContext.Shading.color(.black.opacity(0.5))

            if startX > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: startX, height: size.height)), with: dimColor)
            }
            if endX < size.width {
                ctx.fill(Path(CGRect(x: endX, y: 0, width: size.width - endX, height: size.height)), with: dimColor)
            }
        }
        .allowsHitTesting(false)
    }
}
