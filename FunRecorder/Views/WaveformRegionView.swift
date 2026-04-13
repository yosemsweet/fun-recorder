import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Waveform amplitude loader

private func loadAmplitudes(from url: URL, targetCount: Int) async -> [Float] {
    return await Task.detached(priority: .userInitiated) {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let frameCount = AVAudioFrameCount(audioFile.length)
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? audioFile.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData else { return [] }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        guard !samples.isEmpty else { return [] }

        // Downsample: split into targetCount bins, take RMS of each
        let binSize = max(1, samples.count / targetCount)
        var amplitudes = [Float](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let start = i * binSize
            let end = min(start + binSize, samples.count)
            guard start < end else { break }
            var rms: Float = 0
            vDSP_rmsqv(Array(samples[start..<end]), 1, &rms, vDSP_Length(end - start))
            amplitudes[i] = rms
        }

        // Normalize to 0…1
        var maxVal: Float = 0
        vDSP_maxv(amplitudes, 1, &maxVal, vDSP_Length(amplitudes.count))
        if maxVal > 0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(amplitudes, 1, &scale, &amplitudes, 1, vDSP_Length(amplitudes.count))
        }
        return amplitudes
    }.value
}

// MARK: - Canvas waveform view

private struct WaveformCanvas: View {
    let amplitudes: [Float]

    var body: some View {
        Canvas { ctx, size in
            guard !amplitudes.isEmpty else { return }
            let barWidth = size.width / CGFloat(amplitudes.count)
            let midY = size.height / 2

            for (i, amp) in amplitudes.enumerated() {
                let x = CGFloat(i) * barWidth
                let barHeight = max(2, CGFloat(amp) * size.height * 0.92)
                let rect = CGRect(x: x + 0.5, y: midY - barHeight / 2, width: max(1, barWidth - 1), height: barHeight)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.primary.opacity(0.85)))
            }
        }
    }
}

// MARK: - WaveformRegionView

struct WaveformRegionView: View {
    let audioURL: URL
    let duration: TimeInterval
    let totalSamples: Int
    let beatGrid: BeatGrid?
    let regionStartSamples: Int
    let regionEndSamples: Int
    let onRegionChanged: (_ start: Int, _ end: Int) -> Void
    let beatLabel: (Double) -> String?

    @State private var amplitudes: [Float] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var startTooltip: String? = nil
    @State private var endTooltip: String? = nil

    private let waveformHeight: CGFloat = 120
    private static let sampleRate: Double = 32000

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width * zoomScale
            let targetBars = Int(contentWidth)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    // Waveform drawn with Canvas
                    WaveformCanvas(amplitudes: amplitudes)
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
            .task(id: audioURL) {
                amplitudes = await loadAmplitudes(from: audioURL, targetCount: targetBars)
            }
            .onChange(of: zoomScale) {
                Task {
                    amplitudes = await loadAmplitudes(from: audioURL, targetCount: Int(geo.size.width * zoomScale))
                }
            }
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
