import Foundation
import Accelerate
import AVFoundation

// MARK: - BeatGrid

struct BeatGrid {
    let bpm: Double
    let sixteenthPositions: [Double]  // seconds from start of audio

    func nearestSixteenth(to time: Double) -> Double {
        guard !sixteenthPositions.isEmpty else { return time }
        return sixteenthPositions.min(by: { abs($0 - time) < abs($1 - time) })!
    }

    /// "Bar N, beat N" for quarter note positions; "Bar N, beat N.M" for other 16ths.
    func label(at time: Double) -> String {
        let sixteenthDuration = 60.0 / bpm / 4.0
        let index = Int((time / sixteenthDuration).rounded())
        let bar = index / 16 + 1
        let beat = (index % 16) / 4 + 1
        let sixteenth = index % 4 + 1
        if sixteenth == 1 {
            return "Bar \(bar), beat \(beat)"
        }
        return "Bar \(bar), beat \(beat).\(sixteenth)"
    }

    static func build(bpm: Double, startOffset: Double, duration: Double) -> BeatGrid {
        let sixteenthDuration = 60.0 / bpm / 4.0
        var positions: [Double] = []
        // Align grid to startOffset, then iterate forward through duration
        let phase = startOffset.truncatingRemainder(dividingBy: sixteenthDuration)
        var t = phase
        while t <= duration {
            positions.append(t)
            t += sixteenthDuration
        }
        return BeatGrid(bpm: bpm, sixteenthPositions: positions)
    }
}

// MARK: - BeatDetectionResult

struct BeatDetectionResult {
    let grid: BeatGrid
    let confidence: Double
}

// MARK: - BeatDetector

enum BeatDetector {
    static let confidenceThreshold = 0.35
    private static let targetSampleRate: Double = 32000

    static func detect(audioFileURL: URL, duration: TimeInterval) async -> BeatDetectionResult? {
        guard let samples = loadSamples(from: audioFileURL) else { return nil }

        let frameSize = Int(0.05 * targetSampleRate)   // 50ms = 1600 samples
        let hopSize   = Int(0.01 * targetSampleRate)   // 10ms = 320 samples
        let hopDuration = Double(hopSize) / targetSampleRate

        let energies = frameEnergies(samples: samples, frameSize: frameSize, hopSize: hopSize)
        let onsets = detectOnsets(energies: energies, hopDuration: hopDuration)

        guard onsets.count >= 4 else { return nil }
        guard let (bpm, confidence) = estimateBPM(onsetTimes: onsets) else { return nil }
        guard confidence >= confidenceThreshold else { return nil }

        let startOffset = onsets.first ?? 0
        let grid = BeatGrid.build(bpm: bpm, startOffset: startOffset, duration: duration)
        return BeatDetectionResult(grid: grid, confidence: confidence)
    }

    // MARK: Internal (internal access for testing)

    static func loadSamples(from url: URL) -> [Float]? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? audioFile.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }

    static func frameEnergies(samples: [Float], frameSize: Int, hopSize: Int) -> [Float] {
        let frameCount = (samples.count - frameSize) / hopSize
        guard frameCount > 0 else { return [] }
        var energies = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { ptr in
            for i in 0..<frameCount {
                let start = i * hopSize
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress! + start, 1, &rms, vDSP_Length(frameSize))
                energies[i] = rms
            }
        }
        return energies
    }

    static func detectOnsets(energies: [Float], hopDuration: Double) -> [Double] {
        guard energies.count > 2 else { return [] }

        // Half-wave rectified first difference (onset strength function)
        var odf = [Float](repeating: 0, count: energies.count - 1)
        for i in 0..<odf.count {
            odf[i] = max(0, energies[i + 1] - energies[i])
        }

        // Threshold: local median × 1.5 + small floor
        let sortedOdf = odf.sorted()
        let median = sortedOdf[sortedOdf.count / 2]
        let threshold = median * 1.5 + 0.001

        // Peak picking with minimum inter-onset gap of 8 frames (~80ms)
        var onsets: [Double] = []
        var lastOnsetFrame = -100
        for i in 1..<(odf.count - 1) {
            if odf[i] > threshold,
               odf[i] > odf[i - 1],
               odf[i] >= odf[i + 1],
               (i - lastOnsetFrame) >= 8 {
                onsets.append(Double(i) * hopDuration)
                lastOnsetFrame = i
            }
        }
        return onsets
    }

    static func estimateBPM(onsetTimes: [Double]) -> (bpm: Double, confidence: Double)? {
        // Collect inter-onset intervals in valid BPM range (60–200 BPM → 0.3–1.0s)
        var iois: [Double] = []
        for i in 1..<onsetTimes.count {
            let ioi = onsetTimes[i] - onsetTimes[i - 1]
            if ioi >= 0.3 && ioi <= 1.0 { iois.append(ioi) }
        }
        guard iois.count >= 3 else { return nil }

        // IOI histogram: 60–200 BPM at 1 BPM resolution
        let binCount = 141
        var histogram = [Double](repeating: 0, count: binCount)
        for ioi in iois {
            let bpm = 60.0 / ioi
            // Weight primary tempo plus half/double octaves
            for (multiplier, weight): (Double, Double) in [(1, 1.0), (0.5, 0.5), (2.0, 0.5)] {
                let idx = Int((bpm * multiplier).rounded()) - 60
                if idx >= 0 && idx < binCount { histogram[idx] += weight }
            }
        }

        guard let maxVal = histogram.max(), maxVal > 0,
              let maxIdx = histogram.firstIndex(of: maxVal) else { return nil }

        let bpm = Double(maxIdx + 60)
        let confidence = maxVal / Double(iois.count)
        return (bpm: bpm, confidence: confidence)
    }
}
