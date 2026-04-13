# Audio Capture System

Milestone 1 of fun-recorder. Handles recording, beat detection, playback, waveform display, region selection, and clip persistence.

## Key Files

| File | Responsibility |
|------|---------------|
| `FunRecorder/Audio/AudioRecorder.swift` | AVAudioEngine recording at 32kHz mono, WAV file writing, live level metering |
| `FunRecorder/Audio/AudioPlayer.swift` | AVAudioPlayerNode playback, gapless loop scheduling, 60fps playhead tracking |
| `FunRecorder/Audio/BeatDetector.swift` | `BeatGrid` struct + pure-Swift Accelerate-based tempo detection |
| `FunRecorder/ViewModels/RecorderViewModel.swift` | `@Observable` state coordinator; AppState machine (empty/recording/editing) |
| `FunRecorder/Views/LiveWaveformView.swift` | Scrolling Canvas amplitude bars during recording |
| `FunRecorder/Views/WaveformRegionView.swift` | Static waveform (custom Canvas + AVAudioFile amplitude loader) + beat grid + draggable region handles |
| `FunRecorder/Views/BeatGridOverlay.swift` | Canvas overlay: 16th-note beat grid lines at variable heights/opacities |
| `FunRecorder/Views/RegionHighlightView.swift` | Canvas overlay: dims audio outside selected region |
| `FunRecorder/Views/RegionHandleView.swift` | Single 44pt draggable handle with tooltip |
| `FunRecorder/Views/ClipLibraryView.swift` | SwiftData `@Query` list, tap-to-load, swipe-to-delete |
| `FunRecorder/Models/Clip.swift` | SwiftData `@Model` for clip metadata |
| `FunRecorder/ContentView.swift` | Root single-screen view; routes all states |

## Audio Pipeline

```
Microphone → AVAudioEngine inputNode tap (Float32, 32kHz mono)
    ├── RMS via vDSP_rmsqv → levels[] → LiveWaveformView
    └── trimmedCopy → AVAudioFile.write (Int16 PCM WAV)

After recording:
WAV file → BeatDetector.detect (Accelerate) → BeatGrid (16th positions)
WAV file → AudioPlayer.load → AVAudioPlayerNode.scheduleSegment (region loop)
WAV file → WaveformRegionView → AVAudioFile amplitude loader (vDSP_rmsqv) → Canvas bar renderer + overlays
```

## Beat Detection Algorithm

1. Compute RMS frame energies (50ms frames, 10ms hop) using `vDSP_rmsqv`
2. Half-wave rectified first difference → onset strength function
3. Peak-pick above local median threshold (min 80ms inter-onset gap)
4. Build inter-onset interval histogram (60–200 BPM range) with half/double octave weighting
5. If confidence ≥ 0.35, build `BeatGrid` with 16th-note positions

Falls back to freeform selection (no grid) if confidence < threshold.

## Gapless Loop Scheduling

`AudioPlayer.scheduleSegment` uses `completionCallbackType: .dataConsumed` — fires while the current buffer is still in the hardware queue. The completion handler pre-schedules the next loop segment before the current one finishes playing, ensuring zero-gap looping. Loop region boundaries captured as locals in the closure to avoid `self` nil-fallback.

## Data Model

```
Clip (@Model, SwiftData)
├── id: UUID (@Attribute(.unique))
├── name: String
├── createdAt: Date
├── duration: TimeInterval
├── audioFileName: String         → Documents/clips/{uuid}.wav
├── detectedTempoBPM: Double?
├── regionStartSamples: Int
├── regionEndSamples: Int
└── sampleRate: Int (32000)
```

## Key Design Decisions

See `adr/` for full rationale:
- ADR-0001: Self-hosted MusicGen (future M2)
- ADR-0002: 32kHz mono WAV — matches MusicGen input, no resampling needed
- ADR-0003: 16th-note grid snapping for clean loop boundaries
