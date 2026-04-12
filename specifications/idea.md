# fun-recorder: Product Idea & Milestone Plan

## Core Vision

An iPhone app for capturing and exploring musical ideas. You provide a short audio seed — hummed, recorded, or imported — and the app generates musically coherent variations. You pick, refine, and eventually sequence variations into a complete piece.

---

## Sound Inputs

- **Hum / sing into the mic** — lowest friction, captures ideas before they're gone
- **Record a sample** — in-app recording of instruments, voice, ambient sound
- **Import a file** — MP3s, AAC, via Files app or Share Sheet
- **From another app** — via iOS system audio (see note below)

> **Note on streaming sources (SoundCloud, YouTube, Spotify):** Direct API integration for audio capture is prohibited by all three platforms' ToS and blocked by DRM. The musical intent — being inspired by something you're hearing — is better served by:
> - iOS inter-app audio / system audio capture (records whatever is playing on-device)
> - Humming or singing the idea you want to explore
> 
> Defer streaming integration unless a licensing deal or platform API explicitly supports it.

---

## Input Processing

- User selects a sub-region of the sample (waveform scrubber with drag handles) to use as the variation seed
- **Stretch:** Stem separation (isolate vocals, drums, melody, bass) so stems can be used as individual seeds. Demucs can run via Core ML on-device; realistic as a post-v1 feature.

---

## Variation Generation

Two complementary modes, not alternatives:

### Mode 1: Exploratory (Guided Divergence)
Generate a small set of variations that explore meaningfully different directions from the seed. The variations should differ in feel, texture, or style — not just be randomly permuted. User selects one; next round generates variations that converge toward the selected direction.

**On "random" variation:** Pseudo-random generation sounds bad musically. The target is *diverse-but-coherent* variation, which requires steering the generation model with structured parameters (tempo, key, style, density) even if those are inferred from the input rather than specified by the user.

**Recommended approach:** 3 variations per round, each seeded with different style descriptors inferred from the audio + a divergence parameter. As the user picks favorites, update a preference vector to guide future rounds toward their taste.

**Fallback for latency / cost:** Generate DSP-based variations immediately (pitch shift ±semitone, time-stretch, granular scatter, spectral thinning) as placeholders while cloud AI variations load async. This keeps the user in flow state.

### Mode 2: Directed (Natural Language)
User describes what they want in plain English ("make it feel more melancholy", "add a driving rhythm", "something that sounds like it's underwater"). An agent pipeline translates that into a structured transformation prompt sent to the generation API.

This mode is higher-value for experienced users and lower-value for exploration. Implement after Mode 1 is working well.

---

## Generation API Strategy

The variation quality is the product. API choice matters.

**Chosen approach:** Self-hosted MusicGen (via Meta's AudioCraft) to keep development costs at zero. AudioCraft runs on Apple Silicon (MPS backend) — during development the app hits a local FastAPI server on the dev Mac. The generation layer is a swappable adapter so the backend can be changed without touching app code.

For production, options are:
- Continue self-hosting on a small GPU instance (Hetzner, Lambda Labs, etc.)
- Switch to Replicate or a managed API once usage warrants the cost
- Add Suno when/if a public API ships — its output quality is higher

**Why not Replicate during development:** Per-call costs add up fast during iteration on generation params. Self-hosting also gives full control over model version, sampling parameters, and prompt format.

---

## Milestones

### Milestone 1 — Audio Capture & Region Selection

Goal: Validate the core input UX before writing any AI code.

- Microphone recording with live waveform visualization
- Playback with scrubber
- Region selection: tap-drag handles on waveform to isolate a clip
- Loop playback of selected region
- Save/name clips

**Success criteria:** A musician can hum an idea, see it on screen, select the interesting 4 bars, and loop them — in under 10 seconds from opening the app.

---

### Milestone 2 — Exploratory Variation (Cloud AI)

Goal: The core loop working end-to-end, even if rough.

- Integrate MusicGen via self-hosted AudioCraft server (FastAPI, MPS backend on dev Mac)
- Selected region → API → 3 variations returned and playable
- "More like this" selects a variation and generates a new round centered on it
- Basic preference tracking (which variation was selected each round)
- Async loading with DSP placeholder variations while AI loads

**Key design question:** How do you present 3 variations for A/B comparison on a phone screen? Likely swipeable cards with inline playback. Avoid a list — the comparison needs to be immediate and tactile.

**Success criteria:** Starting from a 4-bar hum, reach a variation that feels genuinely different and musically interesting within 3 rounds of iteration.

---

### Milestone 3 — Directed Variation (Natural Language)

Goal: Users who know what they want can get there faster.

- Text input field: "make it more aggressive", "something cinematic"
- Claude (or similar) parses intent → structured generation parameters
- Parameters passed alongside audio seed to generation API
- Show the inferred parameters to the user so they can correct/learn

**Alternative if LLM-to-music-param mapping is unreliable:** Offer a curated set of direction buttons ("darker", "brighter", "sparse", "dense", "faster", "slower") that map to known-good parameter adjustments. Less expressive but more predictable.

---

### Milestone 4 — Extended Input Sources

Goal: Import from more places without building risky integrations.

- Files app / Share Sheet import (MP3, AAC, WAV, M4A)
- iOS system audio capture (record whatever is playing on-device — covers the streaming use case without ToS violations)
- Share from AirDrop

---

### Milestone 5 — Stem Separation

Goal: Use specific elements (just the melody, just the rhythm) as seeds.

- Integrate Demucs for 4-stem separation (vocals, bass, drums, other)
- Let user pick a stem before entering the variation loop
- On-device via Core ML if model size allows; otherwise API

**Note:** Stem separation on 4-8 bar clips is much faster than full songs. This is more tractable on-device than it sounds.

---

### Milestone 6 — Sequencing

Goal: Arrange the best variations into a complete piece.

- Timeline view: place variation clips in order
- Basic loop/section structure (intro, A, B, outro)
- Per-clip volume and basic crossfade
- Export to Files / share as audio

**Alternative if AI sequencing is in scope:** User describes the structure ("verse-chorus-verse, then build to a big ending") and an agent arranges the saved variations to match. This extends the directed variation concept into arrangement.

**Export target:** At minimum, a stereo mixdown. Stretch: export as stems or as an Ableton/GarageBand project.

---

## What We're Not Building (Yet)

- Real-time audio effects chain
- MIDI output
- Collaborative features
- Direct streaming platform integration
- Beat matching / tempo sync between variations (needed eventually for sequencing to feel cohesive)
