# ADR-0002: Record audio at 32kHz mono

**Status:** Accepted
**Date:** 2026-04-12

## Context

The app records audio that will be sent to MusicGen for variation generation. MusicGen's internal processing expects 32kHz mono. Recording at a higher sample rate (44.1kHz, 48kHz) or in stereo would require resampling before generation, adding complexity with no benefit — the downstream model discards the extra information.

## Decision

Record all audio at 32kHz, mono, 16-bit WAV.

## Consequences

- No resampling needed before sending to MusicGen
- Smaller file sizes (~1.9 MB for 30 seconds vs ~5 MB at 44.1kHz stereo)
- Audio quality is lower than CD quality, but sufficient for musical idea capture and AI processing
- If a future milestone requires higher-fidelity export (e.g., sequencing into a final mix), we may need to re-record or upsample. This is acceptable — M1 is about idea capture, not production audio.
