# Milestone 1 — Audio Capture & Region Selection

## Goal

Validate the core input UX before writing any AI code. A musician can hum an idea, see it on screen, select a loop region snapped to the beat grid, and play it back — in under 10 seconds from opening the app.

---

## Platform & Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Audio engine:** AVFoundation (AVAudioEngine for capture and playback)
- **Persistence:** SwiftData for clip metadata, audio files stored in app's Documents directory
- **Waveform rendering:** Use an existing library (DSWaveformImage or similar). Fall back to custom Core Graphics rendering only if the library can't support the overlay UX for region selection handles.
- **Beat detection:** aubio (C library with iOS support) or Essentia via Swift bridging header. Use onset/tempo detection to build a beat grid; snap region handles to nearest 16th note.

**General principle:** Use existing libraries wherever possible. Focus development effort on the interactions and behaviors unique to this app.

---

## Audio Format

- **Sample rate:** 32kHz
- **Channels:** Mono
- **Bit depth:** 16-bit
- **Container:** WAV (lossless, simple, easy to slice)
- **Max recording duration:** 30 seconds

32kHz mono matches MusicGen's expected input format, avoiding unnecessary resampling in Milestone 2.

---

## Features

### 1. Recording

- Single prominent record button on the main screen
- Tap to start, tap to stop (no hold-to-record — hands may be on an instrument)
- Live waveform visualization while recording (scrolling amplitude view)
- Microphone permission request on first launch with clear explanation of why
- Recording stops automatically at 30 seconds with a visual/haptic indication
- Audio routed through AVAudioEngine so we can tap the input node for both visualization and writing to file simultaneously

### 2. Waveform Display & Playback

- After recording, show the full waveform in a horizontally scrollable/zoomable view
- Playback with a moving playhead cursor
- Tap anywhere on the waveform to set playhead position
- Play/pause button

### 3. Beat Detection & Grid

- After recording completes, run tempo/onset detection on the captured audio
- Compute a beat grid (quarter notes) and subdivide to 16th notes
- Display the beat grid as subtle vertical lines overlaid on the waveform
- If tempo detection confidence is low (e.g., arrhythmic humming, ambient sound), fall back to freeform selection with no grid snap and indicate to the user that no tempo was detected

### 4. Region Selection

- Two draggable handles (start/end) overlaid on the waveform
- Handles snap to nearest 16th note on the detected beat grid
- Selected region highlighted visually (dimmed outside, bright inside)
- Minimum region size: 1 beat (4 sixteenth notes)
- Default selection: full recording
- Loop toggle: when enabled, playback loops the selected region continuously
- The region selection is the primary output of this milestone — it defines what gets sent to variation generation in M2

### 5. Clip Library

- Save the current recording as a named clip (default name: timestamp, user can rename)
- Library view: list of saved clips sorted by recency, showing name, duration, date
- Tap a clip to load it into the waveform view with its saved region selection
- Swipe to delete
- Clips persist across app launches via SwiftData (metadata) + file system (audio)

---

## Data Model

```
Clip
├── id: UUID
├── name: String
├── createdAt: Date
├── duration: TimeInterval
├── audioFileName: String          // relative path in Documents/clips/
├── detectedTempoBPM: Double?      // nil if detection failed
├── regionStartSamples: Int        // start of selected region in samples
├── regionEndSamples: Int          // end of selected region in samples
└── sampleRate: Int                // 32000
```

Audio files stored at `Documents/clips/{id}.wav`.

---

## Screen Flow

```
┌─────────────────────┐
│     Main Screen      │
│                      │
│  ┌────────────────┐  │
│  │   Waveform /   │  │
│  │   Record View  │  │
│  │                │  │
│  │  [beat grid]   │  │
│  │  |--region--|  │  │
│  └────────────────┘  │
│                      │
│  [Record]  [Play/⏸]  │
│  [Loop 🔁]  [Save]   │
│                      │
│  ┌────────────────┐  │
│  │  Clip Library  │  │
│  │  (scrollable)  │  │
│  └────────────────┘  │
└─────────────────────┘
```

Single-screen layout. The waveform area doubles as the recording visualization (live amplitude while recording) and the editing view (static waveform + region handles after recording). Clip library is a collapsible section below.

---

## Success Criteria

1. Record a hummed melody, select a 4-bar loop, and hear it play back seamlessly — under 10 seconds from app launch
2. Beat grid is detected accurately enough that snapped loop boundaries don't cut mid-note on rhythmically clear input (clapping, tapping, sung melody with clear rhythm)
3. Saved clips survive app restart and load with their region selection intact
4. Recording at 32kHz mono produces clean audio with no artifacts from the AVAudioEngine pipeline

---

## Open Questions / Risks

- **Waveform library fit:** If DSWaveformImage (or whichever library we pick) doesn't support custom overlay views for the drag handles and beat grid lines, we'll need to render them in a separate transparent overlay view on top. Evaluate this early — if the library fights us on the interaction layer, drop it and draw custom.
- **Beat detection on humming:** Tempo detection algorithms work best on percussive or rhythmically clear audio. A breathy hum with rubato may produce unreliable results. The fallback (freeform selection, no grid) handles this, but we should test with real hummed input early.
- **30-second cap:** May be too short for some use cases (recording a full verse idea). Easy to increase later since nothing in the architecture assumes a fixed length.

---

## Out of Scope for M1

- File import (M4)
- Variation generation (M2)
- Any network calls
- Audio effects or processing beyond beat detection
- Editing / trimming the raw recording (the region selection serves this purpose)
