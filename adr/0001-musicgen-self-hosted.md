# ADR-0001: Self-host MusicGen (AudioCraft) for variation generation

**Status:** Accepted  
**Date:** 2026-04-12

## Context

The app's variation generation requires an audio-conditioned music generation model. MusicGen (Meta's AudioCraft) supports melody conditioning from audio input, which matches the use case exactly. It has open weights and runs on Apple Silicon via the MPS backend.

The alternative was using Replicate's managed MusicGen API, which has a per-call cost that becomes significant during iterative development on generation parameters.

## Decision

Self-host MusicGen via AudioCraft. During development, run a local FastAPI server on the dev Mac (MPS backend). The iOS app calls this server.

The generation backend is implemented as a swappable adapter — the app code has no direct dependency on AudioCraft's API shape, only on the adapter interface. This allows switching to Replicate, Suno, or another backend without changing app code.

## Consequences

- Zero per-call cost during development
- Full control over model version, sampling temperature, and prompt structure
- Requires AudioCraft Python environment to be running on dev Mac during development
- Production hosting decision deferred: self-host on a GPU instance or migrate to managed API based on usage and cost at that point
