import SwiftUI
import DSWaveformImageViews
import DSWaveformImage

struct WaveformRegionView: View {
    let audioURL: URL
    let duration: TimeInterval
    let totalSamples: Int
    let beatGrid: BeatGrid?
    let regionStartSamples: Int
    let regionEndSamples: Int
    let onRegionChanged: (_ start: Int, _ end: Int) -> Void
    let beatLabel: (Double) -> String?

    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var startTooltip: String? = nil
    @State private var endTooltip: String? = nil

    private let waveformHeight: CGFloat = 120
    private static let sampleRate: Double = 32000

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width * zoomScale

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    // Waveform rendered by DSWaveformImage
                    WaveformView(
                        audioURL: audioURL,
                        configuration: Waveform.Configuration(
                            size: CGSize(width: contentWidth, height: waveformHeight),
                            backgroundColor: .clear,
                            style: .striped(
                                .init(color: UIColor.label, width: 2, spacing: 1, lineCap: .round)
                            ),
                            dampening: .init(percentage: 0.08, sides: .both),
                            scale: UIScreen.main.scale
                        )
                    )
                    .frame(width: contentWidth, height: waveformHeight)

                    // Dim outside region
                    RegionHighlightView(
                        startFraction: startFraction,
                        endFraction: endFraction
                    )
                    .frame(width: contentWidth, height: waveformHeight)

                    // Beat grid lines
                    if let grid = beatGrid {
                        BeatGridOverlay(grid: grid, duration: duration)
                            .frame(width: contentWidth, height: waveformHeight)
                    }

                    // Start handle
                    RegionHandleView(
                        xFraction: startFraction,
                        containerWidth: contentWidth,
                        containerHeight: waveformHeight,
                        tooltip: startTooltip
                    ) { newFraction in
                        let time = newFraction * duration
                        let snapped = beatGrid?.nearestSixteenth(to: time) ?? time
                        startTooltip = beatLabel(snapped)
                        let newSamples = min(Int(snapped * Self.sampleRate), regionEndSamples - Int(Self.sampleRate))
                        onRegionChanged(newSamples, regionEndSamples)
                    }

                    // End handle
                    RegionHandleView(
                        xFraction: endFraction,
                        containerWidth: contentWidth,
                        containerHeight: waveformHeight,
                        tooltip: endTooltip
                    ) { newFraction in
                        let time = newFraction * duration
                        let snapped = beatGrid?.nearestSixteenth(to: time) ?? time
                        endTooltip = beatLabel(snapped)
                        let newSamples = max(Int(snapped * Self.sampleRate), regionStartSamples + Int(Self.sampleRate))
                        onRegionChanged(regionStartSamples, newSamples)
                    }
                }
                .coordinateSpace(name: "waveform")
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoomScale = max(1, min(8, baseZoomScale * value))
                    }
                    .onEnded { value in
                        zoomScale = max(1, min(8, baseZoomScale * value))
                        baseZoomScale = zoomScale
                    }
            )
        }
        .frame(height: waveformHeight)
    }

    private var startFraction: Double {
        totalSamples > 0 ? Double(regionStartSamples) / Double(totalSamples) : 0
    }
    private var endFraction: Double {
        totalSamples > 0 ? Double(regionEndSamples) / Double(totalSamples) : 1
    }
}
