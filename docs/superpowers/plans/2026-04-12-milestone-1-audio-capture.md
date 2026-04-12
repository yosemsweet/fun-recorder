# Milestone 1: Audio Capture & Region Selection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift/SwiftUI iPhone app that records audio at 32kHz mono, displays a waveform, detects tempo, snaps a loop region to the 16th-note grid, plays the loop back seamlessly, and persists clips across launches.

**Architecture:** A single-screen SwiftUI app driven by `RecorderViewModel` (@Observable), which coordinates `AudioRecorder` (AVAudioEngine capture) and `AudioPlayer` (AVAudioPlayerNode playback). Beat detection runs as a pure-Swift Accelerate-based algorithm after recording finishes. DSWaveformImage renders the static waveform; SwiftUI Canvas layers the beat grid and region handles on top.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, AVFoundation, Accelerate, SwiftData, DSWaveformImage (SPM)

---

## File Map

```
FunRecorder/
├── FunRecorderApp.swift              # App entry + ModelContainer
├── ContentView.swift                 # Root single-screen view; routes empty/recording/editing states
├── Models/
│   └── Clip.swift                    # SwiftData @Model for persisted clip metadata
├── Audio/
│   ├── AudioRecorder.swift           # AVAudioEngine recording, WAV writing, level metering
│   ├── AudioPlayer.swift             # AVAudioPlayerNode playback, gapless loop scheduling
│   └── BeatDetector.swift            # Pure-Swift Accelerate tempo detection → BeatGrid/BeatDetectionResult
├── ViewModels/
│   └── RecorderViewModel.swift       # @Observable state coordinator; bridges Audio/* to Views
└── Views/
    ├── LiveWaveformView.swift         # Scrolling amplitude bars during recording (Canvas)
    ├── WaveformRegionView.swift       # Static waveform + beat grid + region handles
    ├── BeatGridOverlay.swift          # Canvas view: beat grid vertical lines
    ├── RegionHighlightView.swift      # Canvas view: dims audio outside selected region
    ├── RegionHandleView.swift         # Single draggable handle with 44pt hit target + tooltip
    └── ClipLibraryView.swift          # SwiftData query list; tap to load, swipe to delete

FunRecorderTests/
├── BeatGridTests.swift
├── BeatDetectorTests.swift
└── ClipTests.swift

project.yml                           # xcodegen project spec
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `project.yml`
- Create: `FunRecorder/FunRecorderApp.swift`

- [ ] **Step 1: Install xcodegen if needed**

```bash
which xcodegen || brew install xcodegen
```

- [ ] **Step 2: Create project.yml**

```yaml
name: FunRecorder
options:
  bundleIdPrefix: com.funrecorder
  deploymentTarget:
    iOS: "17.0"
targets:
  FunRecorder:
    type: application
    platform: iOS
    sources: [FunRecorder]
    settings:
      SWIFT_VERSION: "5.9"
      PRODUCT_BUNDLE_IDENTIFIER: com.funrecorder.app
      INFOPLIST_KEY_UILaunchScreen_Generation: YES
    info:
      path: FunRecorder/Info.plist
      properties:
        NSMicrophoneUsageDescription: "fun-recorder uses the microphone to capture your musical ideas."
        UIRequiresFullScreen: true
    dependencies:
      - package: DSWaveformImage
        product: DSWaveformImageViews
  FunRecorderTests:
    type: bundle.unit-test
    platform: iOS
    sources: [FunRecorderTests]
    dependencies:
      - target: FunRecorder
packages:
  DSWaveformImage:
    url: https://github.com/dmrschmidt/DSWaveformImage
    from: "9.0.0"
```

- [ ] **Step 3: Create source directories and placeholder app entry**

```bash
mkdir -p FunRecorder/Models FunRecorder/Audio FunRecorder/ViewModels FunRecorder/Views
mkdir -p FunRecorderTests
```

Create `FunRecorder/FunRecorderApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct FunRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Loading…")
        }
        .modelContainer(for: Clip.self)
    }
}
```

> Note: This won't compile yet — `Clip` is defined in Task 2. Replace `Text("Loading…")` with `ContentView()` in Task 10.

- [ ] **Step 4: Generate and open the Xcode project**

```bash
cd /Users/yosemsweet/workspaces/fun-recorder
xcodegen generate
open FunRecorder.xcodeproj
```

Expected: Xcode opens with FunRecorder and FunRecorderTests targets. DSWaveformImage resolves via SPM.

---

## Task 2: Clip Data Model

**Files:**
- Create: `FunRecorder/Models/Clip.swift`
- Create: `FunRecorderTests/ClipTests.swift`

- [ ] **Step 1: Write failing tests**

`FunRecorderTests/ClipTests.swift`:

```swift
import XCTest
@testable import FunRecorder

final class ClipTests: XCTestCase {
    func test_regionStartTime_convertsFromSamples() {
        let clip = Clip(
            name: "Test", duration: 10,
            audioFileName: "test.wav",
            regionStartSamples: 32000,
            regionEndSamples: 64000
        )
        XCTAssertEqual(clip.regionStartTime, 1.0, accuracy: 0.001)
    }

    func test_regionEndTime_convertsFromSamples() {
        let clip = Clip(
            name: "Test", duration: 10,
            audioFileName: "test.wav",
            regionStartSamples: 32000,
            regionEndSamples: 64000
        )
        XCTAssertEqual(clip.regionEndTime, 2.0, accuracy: 0.001)
    }

    func test_defaultSampleRate_is32000() {
        let clip = Clip(
            name: "Test", duration: 5,
            audioFileName: "test.wav",
            regionStartSamples: 0,
            regionEndSamples: 160000
        )
        XCTAssertEqual(clip.sampleRate, 32000)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FunRecorderTests/ClipTests 2>&1 | tail -20
```

Expected: Build error — `Clip` not found.

- [ ] **Step 3: Implement Clip.swift**

`FunRecorder/Models/Clip.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Clip {
    var id: UUID
    var name: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var detectedTempoBPM: Double?
    var regionStartSamples: Int
    var regionEndSamples: Int
    var sampleRate: Int

    init(
        id: UUID = UUID(),
        name: String,
        duration: TimeInterval,
        audioFileName: String,
        detectedTempoBPM: Double? = nil,
        regionStartSamples: Int,
        regionEndSamples: Int,
        sampleRate: Int = 32000
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.duration = duration
        self.audioFileName = audioFileName
        self.detectedTempoBPM = detectedTempoBPM
        self.regionStartSamples = regionStartSamples
        self.regionEndSamples = regionEndSamples
        self.sampleRate = sampleRate
    }

    var regionStartTime: TimeInterval {
        TimeInterval(regionStartSamples) / TimeInterval(sampleRate)
    }

    var regionEndTime: TimeInterval {
        TimeInterval(regionEndSamples) / TimeInterval(sampleRate)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FunRecorderTests/ClipTests 2>&1 | tail -10
```

Expected: `ClipTests` — 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add FunRecorder/Models/Clip.swift FunRecorderTests/ClipTests.swift
git commit -m "feat: add Clip SwiftData model with region time accessors"
```

---

## Task 3: BeatGrid and BeatDetector

**Files:**
- Create: `FunRecorder/Audio/BeatDetector.swift`
- Create: `FunRecorderTests/BeatGridTests.swift`
- Create: `FunRecorderTests/BeatDetectorTests.swift`

- [ ] **Step 1: Write failing tests for BeatGrid**

`FunRecorderTests/BeatGridTests.swift`:

```swift
import XCTest
@testable import FunRecorder

final class BeatGridTests: XCTestCase {
    // 120 BPM: quarter note = 0.5s, 16th note = 0.125s
    let grid120 = BeatGrid.build(bpm: 120, startOffset: 0, duration: 4.0)

    func test_build_generatesCorrectNumberOf16ths() {
        // 4 seconds at 120 BPM = 8 quarter notes = 32 sixteenths
        // +1 for position at t=0
        XCTAssertEqual(grid120.sixteenthPositions.count, 33)
    }

    func test_build_firstPositionIsAtStartOffset() {
        XCTAssertEqual(grid120.sixteenthPositions.first!, 0.0, accuracy: 0.001)
    }

    func test_build_16thSpacingIsCorrect() {
        let spacing = grid120.sixteenthPositions[1] - grid120.sixteenthPositions[0]
        XCTAssertEqual(spacing, 0.125, accuracy: 0.001)  // 60/120/4
    }

    func test_nearestSixteenth_snapsToClosestPosition() {
        // 0.13 is closer to 0.125 than to 0.25
        XCTAssertEqual(grid120.nearestSixteenth(to: 0.13), 0.125, accuracy: 0.001)
    }

    func test_nearestSixteenth_exactMatchReturnsExact() {
        XCTAssertEqual(grid120.nearestSixteenth(to: 0.5), 0.5, accuracy: 0.001)
    }

    func test_nearestSixteenth_emptyGridReturnsSameTime() {
        let empty = BeatGrid(bpm: 120, sixteenthPositions: [])
        XCTAssertEqual(empty.nearestSixteenth(to: 1.23), 1.23, accuracy: 0.001)
    }

    func test_label_quarterBeatShowsBarAndBeat() {
        // 120 BPM, 4/4: bar 1 beat 1 = 0.0s, bar 1 beat 2 = 0.5s
        XCTAssertEqual(grid120.label(at: 0.0), "Bar 1, beat 1")
        XCTAssertEqual(grid120.label(at: 0.5), "Bar 1, beat 2")
    }

    func test_label_nonQuarterShowsSixteenth() {
        // 0.125s = bar 1, beat 1, 16th 2
        XCTAssertEqual(grid120.label(at: 0.125), "Bar 1, beat 1.2")
    }
}
```

- [ ] **Step 2: Write failing tests for BeatDetector internal functions**

`FunRecorderTests/BeatDetectorTests.swift`:

```swift
import XCTest
@testable import FunRecorder

final class BeatDetectorTests: XCTestCase {
    // Synthetic: 32000 samples/sec, energy spike every 8000 samples = 4 Hz = 240 BPM
    // Use quarter note = 2 Hz = 120 BPM by using 16000 sample spacing
    private func makePulsedSamples(sampleRate: Int = 32000, pulsePeriodSamples: Int, totalSamples: Int) -> [Float] {
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
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
xcodebuild test -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FunRecorderTests/BeatGridTests \
  -only-testing:FunRecorderTests/BeatDetectorTests 2>&1 | tail -10
```

Expected: Build error — `BeatGrid`, `BeatDetector` not found.

- [ ] **Step 4: Implement BeatDetector.swift**

`FunRecorder/Audio/BeatDetector.swift`:

```swift
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

    // MARK: Internal (internal for testing)

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
        var sortedOdf = odf.sorted()
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
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
xcodebuild test -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FunRecorderTests/BeatGridTests \
  -only-testing:FunRecorderTests/BeatDetectorTests 2>&1 | tail -15
```

Expected: All `BeatGridTests` and `BeatDetectorTests` pass.

- [ ] **Step 6: Commit**

```bash
git add FunRecorder/Audio/BeatDetector.swift \
        FunRecorderTests/BeatGridTests.swift \
        FunRecorderTests/BeatDetectorTests.swift
git commit -m "feat: add BeatGrid and BeatDetector with Accelerate-based tempo detection"
```

---

## Task 4: AudioRecorder

**Files:**
- Create: `FunRecorder/Audio/AudioRecorder.swift`

No unit tests here — AVAudioEngine requires hardware. Test manually in Task 10.

- [ ] **Step 1: Implement AudioRecorder.swift**

`FunRecorder/Audio/AudioRecorder.swift`:

```swift
import AVFoundation
import Accelerate

enum AudioRecorderError: Error {
    case permissionDenied
    case fileCreationFailed
}

@Observable
final class AudioRecorder {
    enum State { case idle, recording, finished }

    private(set) var state: State = .idle
    private(set) var levels: [Float] = []         // Amplitude values for live waveform (max 300)
    private(set) var recordedURL: URL?
    private(set) var recordedDuration: TimeInterval = 0

    static let sampleRate: Double = 32000
    static let maxDuration: TimeInterval = 30
    private static let maxFrames = AVAudioFrameCount(sampleRate * maxDuration)

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordedFrameCount: AVAudioFrameCount = 0
    private var autoStopTimer: Timer?

    // AVAudioEngine tap requires float32; we write 16-bit PCM to disk
    private static let tapFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    /// Returns the URL of the file being written to.
    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = clipsDirectory().appendingPathComponent("\(UUID().uuidString).wav")
        let writeSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: writeSettings)
        recordedFrameCount = 0
        levels = []
        recordedURL = url

        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: Self.tapFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
        try engine.start()
        state = .recording

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        return url
    }

    func stop() {
        guard state == .recording else { return }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recordedDuration = TimeInterval(recordedFrameCount) / Self.sampleRate
        audioFile = nil
        state = .finished
    }

    func reset() {
        if state == .recording { stop() }
        recordedURL = nil
        recordedDuration = 0
        recordedFrameCount = 0
        levels = []
        state = .idle
    }

    // MARK: - Private

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard recordedFrameCount < Self.maxFrames, let audioFile else { return }

        let remaining = Self.maxFrames - recordedFrameCount
        let framesToWrite = min(buffer.frameLength, remaining)

        if framesToWrite > 0 {
            // Write a trimmed copy to the WAV file
            if let trimmed = buffer.trimmedCopy(frameCount: framesToWrite) {
                // AVAudioFile converts float32 → int16 automatically based on write settings
                try? audioFile.write(from: trimmed)
                recordedFrameCount += framesToWrite
            }
        }

        // Compute RMS amplitude for live waveform visualization
        if let channelData = buffer.floatChannelData {
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(buffer.frameLength))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.levels.append(rms)
                if self.levels.count > 300 { self.levels.removeFirst() }
            }
        }

        if recordedFrameCount >= Self.maxFrames {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    private func clipsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - AVAudioPCMBuffer helper

private extension AVAudioPCMBuffer {
    func trimmedCopy(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frameCount <= self.frameLength,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        copy.frameLength = frameCount
        guard let src = floatChannelData, let dst = copy.floatChannelData else { return nil }
        for ch in 0..<Int(format.channelCount) {
            memcpy(dst[ch], src[ch], Int(frameCount) * MemoryLayout<Float>.size)
        }
        return copy
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 3: Commit**

```bash
git add FunRecorder/Audio/AudioRecorder.swift
git commit -m "feat: add AudioRecorder with AVAudioEngine tap and WAV writing at 32kHz mono"
```

---

## Task 5: AudioPlayer

**Files:**
- Create: `FunRecorder/Audio/AudioPlayer.swift`

- [ ] **Step 1: Implement AudioPlayer.swift**

`FunRecorder/Audio/AudioPlayer.swift`:

```swift
import AVFoundation

@Observable
final class AudioPlayer {
    private(set) var isPlaying: Bool = false
    private(set) var playheadTime: Double = 0   // Seconds from start of full recording
    var isLooping: Bool = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var regionStart: AVAudioFramePosition = 0
    private var regionEnd: AVAudioFramePosition = 0
    private var playheadTimer: Timer?

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    func load(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        regionStart = 0
        regionEnd = file.length
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
    }

    func play() {
        guard let file = audioFile, !isPlaying else { return }
        scheduleAndPlay(file: file, from: AVAudioFramePosition(playheadTime * file.processingFormat.sampleRate))
        isPlaying = true
        startPlayheadTimer()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopPlayheadTimer()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        playheadTime = 0
        stopPlayheadTimer()
    }

    func seek(to time: Double) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()
        isPlaying = false
        stopPlayheadTimer()
        playheadTime = max(Double(regionStart) / file.processingFormat.sampleRate,
                           min(Double(regionEnd) / file.processingFormat.sampleRate, time))
        if wasPlaying {
            scheduleAndPlay(file: file, from: AVAudioFramePosition(playheadTime * file.processingFormat.sampleRate))
            isPlaying = true
            startPlayheadTimer()
        }
    }

    func updateRegion(startSamples: Int, endSamples: Int) {
        regionStart = AVAudioFramePosition(startSamples)
        regionEnd = AVAudioFramePosition(endSamples)
        // If currently playing, update takes effect at next loop boundary (don't interrupt)
    }

    // MARK: - Private

    private func scheduleAndPlay(file: AVAudioFile, from startFrame: AVAudioFramePosition) {
        playerNode.stop()
        let clampedStart = max(regionStart, min(regionEnd - 1, startFrame))
        scheduleSegment(file: file, startFrame: clampedStart)
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
    }

    /// Schedules one segment; if looping, the completion handler re-schedules from regionStart.
    private func scheduleSegment(file: AVAudioFile, startFrame: AVAudioFramePosition) {
        let frameCount = AVAudioFrameCount(max(0, regionEnd - startFrame))
        guard frameCount > 0 else { return }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataConsumed   // Fires while buffer is in hardware queue
        ) { [weak self] _ in
            guard let self, self.isLooping else {
                Task { @MainActor [weak self] in self?.handleNonLoopEnd() }
                return
            }
            // Pre-schedule next loop iteration without stopping
            let loopFrameCount = AVAudioFrameCount(max(0, self.regionEnd - self.regionStart))
            if loopFrameCount > 0 {
                self.playerNode.scheduleSegment(
                    file, startingFrame: self.regionStart, frameCount: loopFrameCount, at: nil,
                    completionCallbackType: .dataConsumed
                ) { [weak self] _ in self?.scheduleSegment(file: file, startFrame: self?.regionStart ?? 0) }
            }
        }
    }

    private func handleNonLoopEnd() {
        isPlaying = false
        playheadTime = Double(regionStart) / (audioFile?.processingFormat.sampleRate ?? 32000)
        stopPlayheadTimer()
    }

    private func startPlayheadTimer() {
        playheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePlayhead()
        }
    }

    private func stopPlayheadTimer() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func updatePlayhead() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let file = audioFile else { return }

        let sampleRate = file.processingFormat.sampleRate
        let currentFrame = regionStart + playerTime.sampleTime
        let loopLength = regionEnd - regionStart

        if isLooping && loopLength > 0 {
            let positionInLoop = (currentFrame - regionStart) % loopLength
            playheadTime = Double(regionStart + positionInLoop) / sampleRate
        } else {
            playheadTime = Double(min(currentFrame, regionEnd)) / sampleRate
        }
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add FunRecorder/Audio/AudioPlayer.swift
git commit -m "feat: add AudioPlayer with gapless loop scheduling via completion-handler chaining"
```

---

## Task 6: RecorderViewModel

**Files:**
- Create: `FunRecorder/ViewModels/RecorderViewModel.swift`

- [ ] **Step 1: Implement RecorderViewModel.swift**

`FunRecorder/ViewModels/RecorderViewModel.swift`:

```swift
import Foundation
import SwiftData

@Observable
final class RecorderViewModel {
    enum AppState { case empty, recording, editing }

    private(set) var appState: AppState = .empty
    private(set) var beatGrid: BeatGrid?
    private(set) var currentDuration: TimeInterval = 0
    private(set) var currentURL: URL?
    private(set) var pendingSaveName: String? = nil  // Non-nil while rename field is shown

    var regionStartSamples: Int = 0
    var regionEndSamples: Int = 0

    let recorder = AudioRecorder()
    let player = AudioPlayer()

    // MARK: - Convenience accessors (forward to sub-objects)

    var levels: [Float] { recorder.levels }
    var isPlaying: Bool { player.isPlaying }
    var playheadTime: Double { player.playheadTime }
    var isLooping: Bool {
        get { player.isLooping }
        set { player.isLooping = newValue }
    }

    // MARK: - Recording

    func startRecording() async throws {
        guard await recorder.requestMicrophonePermission() else {
            throw AudioRecorderError.permissionDenied
        }
        let url = try recorder.start()
        currentURL = url
        appState = .recording
    }

    func stopRecording() async {
        recorder.stop()
        guard let url = recorder.recordedURL, recorder.recordedDuration > 0 else {
            appState = .empty
            return
        }
        currentDuration = recorder.recordedDuration
        currentURL = url
        regionStartSamples = 0
        regionEndSamples = Int(recorder.recordedDuration * AudioRecorder.sampleRate)
        player.updateRegion(startSamples: regionStartSamples, endSamples: regionEndSamples)
        try? player.load(url: url)
        appState = .editing

        // Beat detection runs in background after UI has transitioned to editing
        if let result = await BeatDetector.detect(audioFileURL: url, duration: currentDuration) {
            beatGrid = result.grid
        } else {
            beatGrid = nil
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to time: Double) {
        player.seek(to: time)
    }

    // MARK: - Region selection

    /// Updates region, enforcing minimum size of 1 second (32000 samples).
    func updateRegion(startSamples: Int, endSamples: Int) {
        let minSamples = Int(AudioRecorder.sampleRate)  // 1 second
        let totalSamples = Int(currentDuration * AudioRecorder.sampleRate)
        let clampedStart = max(0, min(startSamples, totalSamples - minSamples))
        let clampedEnd = max(clampedStart + minSamples, min(endSamples, totalSamples))
        regionStartSamples = clampedStart
        regionEndSamples = clampedEnd
        player.updateRegion(startSamples: clampedStart, endSamples: clampedEnd)
    }

    /// Returns the nearest 16th-note-snapped time, or the original time if no grid.
    func snappedTime(for time: Double) -> Double {
        beatGrid?.nearestSixteenth(to: time) ?? time
    }

    /// Returns beat position label for a given time (e.g. "Bar 2, beat 3").
    func beatLabel(for time: Double) -> String? {
        beatGrid?.label(at: time)
    }

    // MARK: - Save / Load

    func beginSave() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        pendingSaveName = formatter.string(from: Date())
    }

    func cancelSave() {
        pendingSaveName = nil
    }

    func confirmSave(name: String, context: ModelContext) throws {
        guard let url = currentURL else { return }
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (pendingSaveName ?? "Untitled")
            : name
        let clip = Clip(
            name: finalName,
            duration: currentDuration,
            audioFileName: url.lastPathComponent,
            detectedTempoBPM: beatGrid?.bpm,
            regionStartSamples: regionStartSamples,
            regionEndSamples: regionEndSamples
        )
        context.insert(clip)
        try context.save()
        pendingSaveName = nil
    }

    func load(clip: Clip) throws {
        player.stop()
        let url = clipsDirectory().appendingPathComponent(clip.audioFileName)
        try player.load(url: url)
        currentURL = url
        currentDuration = clip.duration
        regionStartSamples = clip.regionStartSamples
        regionEndSamples = clip.regionEndSamples
        player.updateRegion(startSamples: clip.regionStartSamples, endSamples: clip.regionEndSamples)
        if let bpm = clip.detectedTempoBPM {
            beatGrid = BeatGrid.build(bpm: bpm, startOffset: 0, duration: clip.duration)
        } else {
            beatGrid = nil
        }
        appState = .editing
    }

    func delete(clip: Clip, context: ModelContext) throws {
        let url = clipsDirectory().appendingPathComponent(clip.audioFileName)
        try? FileManager.default.removeItem(at: url)
        context.delete(clip)
        try context.save()
    }

    func newRecording() {
        player.stop()
        recorder.reset()
        beatGrid = nil
        currentURL = nil
        currentDuration = 0
        regionStartSamples = 0
        regionEndSamples = 0
        pendingSaveName = nil
        appState = .empty
    }

    // MARK: - Private

    private func clipsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add FunRecorder/ViewModels/RecorderViewModel.swift
git commit -m "feat: add RecorderViewModel coordinating recorder, player, and beat detection"
```

---

## Task 7: LiveWaveformView

**Files:**
- Create: `FunRecorder/Views/LiveWaveformView.swift`

- [ ] **Step 1: Implement LiveWaveformView.swift**

`FunRecorder/Views/LiveWaveformView.swift`:

```swift
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
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add FunRecorder/Views/LiveWaveformView.swift
git commit -m "feat: add LiveWaveformView with scrolling amplitude bars for recording state"
```

---

## Task 8: Waveform Region Views

**Files:**
- Create: `FunRecorder/Views/BeatGridOverlay.swift`
- Create: `FunRecorder/Views/RegionHighlightView.swift`
- Create: `FunRecorder/Views/RegionHandleView.swift`
- Create: `FunRecorder/Views/WaveformRegionView.swift`

- [ ] **Step 1: Implement BeatGridOverlay.swift**

`FunRecorder/Views/BeatGridOverlay.swift`:

```swift
import SwiftUI

/// Canvas overlay drawing 16th-note beat grid lines.
struct BeatGridOverlay: View {
    let grid: BeatGrid
    let duration: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            guard duration > 0 else { return }
            let sixteenthDuration = 60.0 / grid.bpm / 4.0

            for (index, position) in grid.sixteenthPositions.enumerated() {
                let x = CGFloat(position / duration) * size.width
                let isQuarterNote = index % 4 == 0
                let isDownbeat = index % 16 == 0
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
```

- [ ] **Step 2: Implement RegionHighlightView.swift**

`FunRecorder/Views/RegionHighlightView.swift`:

```swift
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
```

- [ ] **Step 3: Implement RegionHandleView.swift**

`FunRecorder/Views/RegionHandleView.swift`:

```swift
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
                    let newX = xPos + value.translation.width
                    let fraction = max(0, min(1, Double(newX / containerWidth)))
                    onDrag(fraction)
                }
        )
    }
}
```

- [ ] **Step 4: Implement WaveformRegionView.swift**

`FunRecorder/Views/WaveformRegionView.swift`:

```swift
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
                        let newSamples = Int(snapped * Self.sampleRate)
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
                        let newSamples = Int(snapped * Self.sampleRate)
                        onRegionChanged(regionStartSamples, newSamples)
                    }
                }
                .coordinateSpace(name: "waveform")
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in zoomScale = max(1, min(8, zoomScale * value)) }
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
```

- [ ] **Step 5: Build**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add FunRecorder/Views/BeatGridOverlay.swift \
        FunRecorder/Views/RegionHighlightView.swift \
        FunRecorder/Views/RegionHandleView.swift \
        FunRecorder/Views/WaveformRegionView.swift
git commit -m "feat: add waveform region views — beat grid, region highlight, drag handles"
```

---

## Task 9: ClipLibraryView

**Files:**
- Create: `FunRecorder/Views/ClipLibraryView.swift`

- [ ] **Step 1: Implement ClipLibraryView.swift**

`FunRecorder/Views/ClipLibraryView.swift`:

```swift
import SwiftUI
import SwiftData

struct ClipLibraryView: View {
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @Environment(\.modelContext) private var context
    let viewModel: RecorderViewModel

    @State private var clipToDelete: Clip? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved Clips")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if clips.isEmpty {
                Text("No saved clips")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(clips) { clip in
                        ClipRowView(clip: clip)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                try? viewModel.load(clip: clip)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    clipToDelete = clip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 260)
            }
        }
        .confirmationDialog(
            "Delete \"\(clipToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { clipToDelete != nil },
                set: { if !$0 { clipToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    try? viewModel.delete(clip: clip, context: context)
                }
                clipToDelete = nil
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        }
    }
}

// MARK: - ClipRowView

private struct ClipRowView: View {
    let clip: Clip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name).font(.body)
                if let bpm = clip.detectedTempoBPM {
                    Text(String(format: "%.0f BPM", bpm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(durationString(clip.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(dateString(clip.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func durationString(_ d: TimeInterval) -> String {
        let total = Int(d)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add FunRecorder/Views/ClipLibraryView.swift
git commit -m "feat: add ClipLibraryView with SwiftData query, tap-to-load, swipe-to-delete"
```

---

## Task 10: ContentView Assembly

**Files:**
- Create: `FunRecorder/ContentView.swift`
- Modify: `FunRecorder/FunRecorderApp.swift`

- [ ] **Step 1: Implement ContentView.swift**

`FunRecorder/ContentView.swift`:

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = RecorderViewModel()
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            waveformArea
                .frame(height: 160)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            controlsArea
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider()

            ClipLibraryView(viewModel: viewModel)
        }
    }

    // MARK: - Waveform area (state-dependent)

    @ViewBuilder
    private var waveformArea: some View {
        switch viewModel.appState {
        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Tap Record to capture an idea")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .recording:
            VStack(spacing: 4) {
                LiveWaveformView(levels: viewModel.levels)
                    .padding(.horizontal, 8)
                Text(String(format: "%.1fs / 30s", viewModel.recorder.recordedDuration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .editing:
            VStack(spacing: 4) {
                if let url = viewModel.currentURL {
                    WaveformRegionView(
                        audioURL: url,
                        duration: viewModel.currentDuration,
                        totalSamples: Int(viewModel.currentDuration * AudioRecorder.sampleRate),
                        beatGrid: viewModel.beatGrid,
                        regionStartSamples: viewModel.regionStartSamples,
                        regionEndSamples: viewModel.regionEndSamples,
                        onRegionChanged: { start, end in
                            viewModel.updateRegion(startSamples: start, endSamples: end)
                        },
                        beatLabel: { time in viewModel.beatLabel(for: time) }
                    )
                }
                if viewModel.beatGrid == nil && viewModel.currentDuration > 0 {
                    Text("No tempo detected — freeform selection")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsArea: some View {
        VStack(spacing: 10) {
            // Save rename field (visible while pendingSaveName is set)
            if let _ = viewModel.pendingSaveName {
                HStack {
                    TextField(
                        "Clip name",
                        text: Binding(
                            get: { viewModel.pendingSaveName ?? "" },
                            set: { viewModel.pendingSaveName = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit {
                        try? viewModel.confirmSave(name: viewModel.pendingSaveName ?? "", context: context)
                    }

                    Button("Save") {
                        try? viewModel.confirmSave(name: viewModel.pendingSaveName ?? "", context: context)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") { viewModel.cancelSave() }
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main control row
            HStack(spacing: 32) {
                // Record / Stop
                Button {
                    Task {
                        if viewModel.appState == .recording {
                            await viewModel.stopRecording()
                        } else {
                            try? await viewModel.startRecording()
                        }
                    }
                } label: {
                    Image(systemName: viewModel.appState == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(viewModel.appState == .recording ? .red : .accentColor)
                        .symbolEffect(.pulse, isActive: viewModel.appState == .recording)
                }

                if viewModel.appState == .editing {
                    // Play / Pause
                    Button { viewModel.togglePlayback() } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }

                    // Loop toggle
                    Button { viewModel.isLooping.toggle() } label: {
                        Image(systemName: "repeat")
                            .font(.title2)
                            .foregroundStyle(viewModel.isLooping ? .accentColor : .secondary)
                    }

                    // Save
                    Button { viewModel.beginSave() } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                    }

                    // New recording
                    Button { viewModel.newRecording() } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.appState)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Clip.self, inMemory: true)
}
```

- [ ] **Step 2: Update FunRecorderApp.swift to use ContentView**

`FunRecorder/FunRecorderApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct FunRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Clip.self)
    }
}
```

- [ ] **Step 3: Build the complete app**

```bash
xcodebuild build -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Run all unit tests**

```bash
xcodebuild test -scheme FunRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: All tests in `ClipTests`, `BeatGridTests`, `BeatDetectorTests` pass.

- [ ] **Step 5: Commit**

```bash
git add FunRecorder/ContentView.swift FunRecorder/FunRecorderApp.swift
git commit -m "feat: assemble ContentView — wires recording, waveform editing, and clip library"
```

---

## Task 11: Manual Acceptance Tests

These cannot be automated — run on device or simulator with a real microphone.

- [ ] **AC1 — Under-10-second capture flow**
  1. Launch app on device
  2. Tap record (stopwatch starts)
  3. Hum a short melody (~5 seconds)
  4. Tap stop
  5. Drag region handles to the interesting 4 bars
  6. Tap play
  7. Confirm elapsed time from launch is under 10 seconds

- [ ] **AC2 — Beat grid snap on rhythmic input**
  1. Record a steady hand-clap pattern at approx 120 BPM for 8 seconds
  2. Confirm beat grid lines appear after recording stops
  3. Drag a handle slowly across a beat boundary and confirm it snaps to the grid
  4. Play the loop — confirm boundaries don't cut mid-clap

- [ ] **AC3 — Freeform fallback on arrhythmic input**
  1. Record ambient room noise for 5 seconds
  2. Confirm "No tempo detected" message appears
  3. Confirm handles drag freely with no snapping

- [ ] **AC4 — Seamless loop**
  1. Record a rhythmic sample and select a clean 2-bar region on the grid
  2. Enable loop toggle
  3. Play — listen through 5+ loop iterations
  4. Confirm no audible gap or click at the loop boundary

- [ ] **AC5 — Clip persistence**
  1. Record, select region, tap Save, set name "Test Clip"
  2. Force-quit the app
  3. Relaunch — confirm "Test Clip" appears in the library
  4. Tap it — confirm waveform loads with the saved region selection intact

- [ ] **AC6 — Delete clip cleans up file**
  1. Save a clip
  2. Note the app's Documents/clips directory size
  3. Swipe-to-delete the clip and confirm
  4. Confirm the WAV file is gone from Documents/clips/

---

## Post-Implementation

- [ ] Create `docs/systems/index.md` with entries for `AudioRecorder`, `AudioPlayer`, `BeatDetector`, `RecorderViewModel`
- [ ] Create `docs/systems/audio-capture/documentation.md` describing the system architecture
- [ ] Update `adr/index.md` if any architectural decisions were made during implementation that differ from the plan
