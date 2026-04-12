import XCTest
@testable import FunRecorder

final class BeatDetectorTests: XCTestCase {
    // Synthetic: pulses (short bursts of 1.0) separated by silence
    private func makePulsedSamples(pulsePeriodSamples: Int, totalSamples: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: totalSamples)
        var i = 0
        while i < totalSamples {
            let end = min(i + 100, totalSamples)
            for j in i..<end { samples[j] = 1.0 }
            i += pulsePeriodSamples
        }
        return samples
    }

    func test_frameEnergies_returnsNonZeroForNonSilence() {
        let samples = [Float](repeating: 0.5, count: 32000)
        let energies = BeatDetector.frameEnergies(samples: samples, frameSize: 1600, hopSize: 320)
        XCTAssertFalse(energies.isEmpty)
        XCTAssertTrue(energies.allSatisfy { $0 > 0 })
    }

    func test_frameEnergies_returnsZeroForSilence() {
        let samples = [Float](repeating: 0, count: 32000)
        let energies = BeatDetector.frameEnergies(samples: samples, frameSize: 1600, hopSize: 320)
        XCTAssertTrue(energies.allSatisfy { $0 == 0 })
    }

    func test_detectOnsets_findsOnsetsInPulsedSignal() {
        // Pulses every 16000 samples = 0.5s apart = 120 BPM quarter notes
        let samples = makePulsedSamples(pulsePeriodSamples: 16000, totalSamples: 96000)
        let energies = BeatDetector.frameEnergies(samples: samples, frameSize: 1600, hopSize: 320)
        let hopDuration = 320.0 / 32000.0
        let onsets = BeatDetector.detectOnsets(energies: energies, hopDuration: hopDuration)
        // Should find at least 4 onsets in 3 seconds
        XCTAssertGreaterThanOrEqual(onsets.count, 4)
    }

    func test_estimateBPM_returns120ForHalfSecondIOIs() {
        // IOIs of 0.5s → 120 BPM
        let onsets = stride(from: 0.0, through: 4.0, by: 0.5).map { $0 }
        guard let (bpm, confidence) = BeatDetector.estimateBPM(onsetTimes: onsets) else {
            XCTFail("Expected BPM result"); return
        }
        XCTAssertEqual(bpm, 120, accuracy: 5)
        XCTAssertGreaterThan(confidence, 0.3)
    }

    func test_estimateBPM_returnsNilForTooFewOnsets() {
        let result = BeatDetector.estimateBPM(onsetTimes: [0.0, 0.5])
        XCTAssertNil(result)
    }

    func test_estimateBPM_returnsNilForOutOfRangeIOIs() {
        // IOI of 5.0s = 12 BPM — outside 60-200 BPM range
        let onsets = stride(from: 0.0, through: 20.0, by: 5.0).map { $0 }
        let result = BeatDetector.estimateBPM(onsetTimes: onsets)
        XCTAssertNil(result)
    }
}
