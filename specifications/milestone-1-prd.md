# PRD: Audio Capture & Region Selection (Milestone 1)

**Product:** fun-recorder
**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-04-12

---

## 1. Problem Statement

Musical ideas are fleeting. A melody that occurs to you while walking, a rhythm you tap on a table, a hummed phrase — these disappear within seconds if not captured. Existing tools (Voice Memos, GarageBand) optimize for recording fidelity or full production, not for the speed and simplicity of capturing a raw musical seed and isolating the interesting part.

fun-recorder's first milestone solves the capture-and-isolate step: record a musical idea, see it, select the part that matters, loop it, save it. This lays the foundation for AI-powered variation generation in Milestone 2.

---

## 2. Target User

Musicians, producers, and songwriters who generate ideas faster than they can develop them. They need a tool that gets out of the way — something closer to jotting on a napkin than opening a DAW.

---

## 3. User Stories

### 3.1 Record a musical idea

**As a** musician with an idea in my head,
**I want to** tap one button and start recording immediately,
**so that** I capture the idea before it fades.

**Acceptance criteria:**
- App opens to the main screen with a visible record button — no navigation required
- Tap record → recording starts (tap, not hold — hands may be holding an instrument)
- Tap again → recording stops
- Live waveform scrolls during recording so user has visual confirmation audio is being captured
- Recording auto-stops at 30 seconds with haptic feedback
- Microphone permission is requested on first use with a clear, non-technical explanation

### 3.2 View and play back a recording

**As a** user who just recorded something,
**I want to** see the full waveform and play it back,
**so that** I can hear what I captured and decide what's interesting.

**Acceptance criteria:**
- After recording stops, full waveform is displayed in a scrollable, zoomable view
- Play/pause button starts playback; a playhead cursor tracks position on the waveform
- Tapping anywhere on the waveform repositions the playhead

### 3.3 Select a loop region on the beat grid

**As a** user looking at my recording,
**I want to** drag handles to select just the interesting part, snapped to musical boundaries,
**so that** my loop starts and ends cleanly on the beat.

**Acceptance criteria:**
- Two draggable handles (start and end) appear on the waveform
- Beat grid (16th note resolution) is displayed as subtle vertical lines over the waveform
- Handles snap to the nearest 16th note boundary
- Selected region is visually highlighted (bright); audio outside the region is dimmed
- Minimum selection size: 1 beat (four 16th notes)
- Default selection: full recording
- If tempo detection fails (arrhythmic input), handles move freely with no grid and a "no tempo detected" indicator is shown

### 3.4 Loop the selected region

**As a** user who has selected a region,
**I want to** loop it continuously,
**so that** I can evaluate whether the loop works musically.

**Acceptance criteria:**
- Loop toggle button; when active, playback repeats the selected region
- Looping is seamless — no audible gap or click at the loop boundary
- Changing the region handles while looping updates the loop boundaries on the next cycle

### 3.5 Save and manage clips

**As a** user who has captured a good idea,
**I want to** save it with a name and come back to it later,
**so that** I build a library of ideas to explore.

**Acceptance criteria:**
- Save button stores the recording and its region selection as a named clip
- Default name is a timestamp; user can rename inline
- Clip library is visible below the waveform area, sorted by most recent
- Tapping a saved clip loads its waveform and restores its region selection
- Swipe to delete a clip (with confirmation)
- Clips persist across app launches

---

## 4. Technical Requirements

### 4.1 Audio specification

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Sample rate | 32kHz | Matches MusicGen input; no resampling needed in M2 |
| Channels | Mono | MusicGen expects mono |
| Bit depth | 16-bit | Sufficient for idea capture |
| Format | WAV | Lossless, simple to slice, no codec overhead |
| Max duration | 30 seconds | ~1.9 MB per clip |

### 4.2 Audio pipeline

- AVAudioEngine with input node tap for simultaneous recording and waveform visualization
- Write directly to WAV file during recording (no post-conversion)
- Playback via AVAudioPlayerNode for precise loop control

### 4.3 Beat detection

- Run tempo estimation and onset detection after recording completes
- Build a beat grid at quarter-note resolution, subdivided to 16th notes
- Confidence threshold: if the detection algorithm's confidence is below threshold, disable grid snap and fall back to freeform selection
- Target processing time: under 1 second for a 30-second clip

### 4.4 Persistence

- **Metadata:** SwiftData model (`Clip`) storing id, name, timestamps, tempo, region boundaries, sample rate
- **Audio files:** `Documents/clips/{id}.wav`
- Deleting a clip removes both the SwiftData record and the audio file

### 4.5 Data model

```swift
@Model
class Clip {
    var id: UUID
    var name: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var detectedTempoBPM: Double?
    var regionStartSamples: Int
    var regionEndSamples: Int
    var sampleRate: Int  // 32000
}
```

---

## 5. UI Layout

Single-screen design. No tab bar, no navigation stack for M1.

```
┌──────────────────────────────┐
│                              │
│  ┌──────────────────────┐    │
│  │    Waveform View     │    │
│  │                      │    │
│  │  ┊   ┊   ┊   ┊   ┊  │    │  ← beat grid (subtle vertical lines)
│  │  ├───████████───┤    │    │  ← region handles + highlight
│  │  ▼ playhead          │    │
│  └──────────────────────┘    │
│                              │
│  [ ● Record ]  [ ▶ Play ]   │
│  [ ↻ Loop   ]  [ Save   ]   │
│                              │
│  ─── Saved Clips ──────────  │
│  │ Morning hum    0:12  4/12│ │
│  │ Tap rhythm     0:08  4/11│ │
│  │ Bass line      0:22  4/10│ │
│  └───────────────────────── │
└──────────────────────────────┘
```

**States of the waveform area:**
1. **Empty** — app just launched, no recording yet. Show record prompt.
2. **Recording** — live scrolling amplitude visualization, record button pulsing/red.
3. **Editing** — static waveform with beat grid overlay and region selection handles.

---

## 6. Interaction Details

### Recording
- Record button: large, center-prominent, red when active
- During recording: waveform scrolls left-to-right showing live amplitude
- Auto-stop at 30s: haptic tap + visual flash + transition to editing state

### Waveform & region
- Pinch to zoom horizontally on the waveform
- Pan to scroll when zoomed in
- Drag handles have a generous hit target (44pt minimum per Apple HIG)
- Handle drag shows a tooltip with the current beat position (e.g., "Bar 2, beat 3")

### Loop playback
- Loop toggle is visually distinct when active (highlighted/filled)
- When looping, playhead wraps from region end to region start with no interruption
- Region handle changes during playback take effect at next loop boundary (not mid-playback)

### Clip library
- Collapsible section; expanded by default
- Saving a new clip: brief inline rename field appears, pre-filled with timestamp
- Loading a clip replaces the current waveform view; unsaved changes prompt a save dialog

---

## 7. Success Criteria

| # | Criterion | How to verify |
|---|-----------|---------------|
| 1 | Hum → select 4-bar loop → play back, under 10 seconds from launch | Stopwatch test with a real user |
| 2 | Beat grid snaps produce clean loops on rhythmic input | Test with clapping, tapping, sung melody with clear rhythm; loop boundaries should not cut mid-note |
| 3 | Freeform fallback works on arrhythmic input | Record ambient noise / rubato humming; verify selection is freeform and "no tempo detected" is shown |
| 4 | Clips survive app restart | Save a clip, force-quit app, relaunch, verify clip loads with correct region |
| 5 | Clean audio at 32kHz mono | Record and play back; no aliasing, clipping, or pipeline artifacts |
| 6 | Seamless loop playback | No audible gap or click at loop boundary |

---

## 8. Dependencies & Libraries

| Dependency | Purpose | Fallback |
|------------|---------|----------|
| DSWaveformImage (or similar) | Waveform rendering | Custom Core Graphics drawing |
| aubio or Essentia | Beat/tempo detection | Freeform-only selection (no grid) |
| AVFoundation | Audio capture & playback | None (platform framework) |
| SwiftData | Clip metadata persistence | None (platform framework) |

Evaluate waveform library early: if it doesn't support overlay views for drag handles and beat grid, use a transparent overlay on top. If it actively fights the interaction layer, drop it and draw custom.

---

## 9. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Beat detection unreliable on hummed input | Snapping is useless or misleading | Confidence threshold + freeform fallback; test with real humming early |
| Waveform library doesn't support interaction overlays | Delays region selection UX work | Evaluate in first implementation spike; fall back to custom rendering |
| 30-second cap too short | Users can't capture full verse ideas | Architecture is duration-agnostic; increase cap with a one-line change |
| Loop boundary clicks | Audible artifacts break the experience | Use sample-accurate loop points; apply micro-crossfade (1-2ms) at loop boundary if needed |

---

## 10. Out of Scope

- File import (Milestone 4)
- AI variation generation (Milestone 2)
- Network calls of any kind
- Audio effects or DSP beyond beat detection
- Destructive editing / trimming of the raw recording
- iPad or Mac targets
