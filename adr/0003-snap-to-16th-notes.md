# ADR-0003: Snap region selection to 16th note grid

**Status:** Accepted
**Date:** 2026-04-12

## Context

When a user selects a loop region, cutting at an arbitrary sample position often lands mid-beat or mid-note, producing an awkward loop. Snapping to musically meaningful boundaries improves loop quality with no additional user effort.

## Decision

Run beat/tempo detection after recording. Build a beat grid subdivided to 16th notes. Snap region selection handles to the nearest 16th note boundary.

If tempo detection confidence is low (arrhythmic input, ambient sound), fall back to freeform selection with no snapping.

## Consequences

- Requires a beat detection library (aubio or Essentia) integrated via bridging header
- Adds a brief processing step after recording completes
- Loops sound musically clean on rhythmic input
- Graceful degradation on non-rhythmic input rather than forcing a grid where none exists
