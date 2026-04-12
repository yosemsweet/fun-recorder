# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Session Start Checklist

At the start of every session, read:
1. **`adr/index.md`** — index of all architectural decisions; keep these in mind for all changes
2. **`docs/systems/index.md`** — index of all systems; use this to locate relevant code before making changes

Whenever a new architectural decision is made during a session, encode it in a new ADR under `adr/` and add it to `adr/index.md`.

## Documentation Maintenance

**No code change is complete without also updating documentation.**

After any code change:
- If a system's behavior changed: update the relevant `docs/systems/<system>/documentation.md`
- If an architectural decision was made or changed: create or update the relevant `adr/` file
- If a feature request was completed: move it to `specifications/feature-requests/complete/` with the next sequential number (e.g. `0005-my-feature.md`)

Do not create documentation or work files outside `adr/`, `docs/`, or `specifications/`.

## Project Overview

**fun-recorder** is an iPhone app for exploring musical ideas. The core loop:

1. User provides a short audio sample (microphone hum, recorded clip, streaming source, or MP3)
2. App generates variations on the theme from that sample
3. User selects, iterates on, or combines variations
4. Variations are sequenced into a complete song

## Sound Input Sources

- Microphone (hum a theme)
- In-app recording
- Streaming sources: SoundCloud, YouTube, Spotify
- MP3 files

## Input Processing

- Users select a sub-region of a sample to seed new variations
- Stretch goal: stem isolation (separate vocals, drums, etc.) to use individual stems as variation seeds

## Variation Generation — Two Modes

1. **Exploratory**: Generate 3 pseudo-random variations spanning the space of possible interest. User picks one, then new variations are generated that cluster around the chosen one (progressive refinement).
2. **Directed**: User describes what they want in plain English; an agent pipeline translates that description into concrete sound transformations.

## Architecture Notes (pre-implementation)

No code exists yet — only `specifications/idea.md`. When building:

- Target platform: iOS (Swift/SwiftUI expected)
- Audio capture and playback: AVFoundation
- AI/agent pipeline for directed variation mode will likely call an external API (Claude or similar)
- Streaming source integration will require OAuth and platform-specific SDKs (SoundCloud, YouTube Data API, Spotify SDK)
