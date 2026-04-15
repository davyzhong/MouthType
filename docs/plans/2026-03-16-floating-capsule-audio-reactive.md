# Floating Capsule Audio Reactive Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the recording capsule about 20% smaller and switch the recording waveform from a decorative idle animation to a visual driven by recent real microphone input levels.

**Architecture:** Keep the current capsule component and single `audioLevel` data flow, but change the waveform renderer so recording mode consumes a rolling history of real mic levels instead of a fake sine wave. Resize constants in the overlay/window state first, then scale the capsule layout to match the tighter footprint while preserving the existing processing and hover behavior.

**Tech Stack:** Electron, React 19, TypeScript, node:test, Tailwind CSS

---

### Task 1: Lock in the new overlay footprint with failing tests

**Files:**

- Modify: `tests/dictation-overlay-ui.test.mjs`
- Modify: `src/utils/dictationOverlayState.mjs`
- Modify: `src/helpers/windowConfig.js`

**Step 1: Write the failing test**

Update the overlay assertions to expect the smaller capsule width and smaller base window size that still centers above the dock.

**Step 2: Run test to verify it fails**

Run: `node --test tests/dictation-overlay-ui.test.mjs`
Expected: FAIL because the current constants still describe the larger capsule.

**Step 3: Write minimal implementation**

Lower the exported capsule width constant and the matching base window sizes so the floating window remains aligned around the new capsule footprint.

**Step 4: Run test to verify it passes**

Run: `node --test tests/dictation-overlay-ui.test.mjs`
Expected: PASS

### Task 2: Add regression tests for real audio-reactive waveform behavior

**Files:**

- Modify: `tests/dictation-waveform.test.mjs`
- Modify: `src/utils/dictationWaveform.mjs`

**Step 1: Write the failing test**

Add assertions that:

- waveform output changes when `samples` change, even if `level` is omitted
- silent sample histories stay visibly flatter than loud sample histories
- the helper still returns bounded dot values in the `[0, 1]` range

**Step 2: Run test to verify it fails**

Run: `node --test tests/dictation-waveform.test.mjs`
Expected: FAIL because the current helper ignores sample history and always synthesizes a ripple.

**Step 3: Write minimal implementation**

Teach `buildWaveformDots()` to use recent normalized sample history for recording mode, while keeping the existing decorative fallback path for non-recording states.

**Step 4: Run test to verify it passes**

Run: `node --test tests/dictation-waveform.test.mjs`
Expected: PASS

### Task 3: Update capsule rendering to consume real level history

**Files:**

- Modify: `src/components/DictationCapsule.tsx`

**Step 1: Keep a rolling buffer of recent `audioLevel` samples**

Track enough samples to fill the waveform bar count and reset or decay the buffer when recording stops.

**Step 2: Use history-driven dots only during recording**

Render recording dots from sample history and keep a gentler processing/hover fallback animation for the other states.

**Step 3: Scale the capsule visuals down**

Reduce padding, icon sizes, typography, gaps, and waveform bar sizing so the whole capsule feels about 20% smaller without crowding the content.

### Task 4: Verify end-to-end renderer safety

**Files:**

- Modify: `src/components/DictationCapsule.tsx`
- Modify: `src/utils/dictationWaveform.mjs`
- Modify: `src/utils/dictationOverlayState.mjs`
- Modify: `src/helpers/windowConfig.js`
- Modify: `tests/dictation-waveform.test.mjs`
- Modify: `tests/dictation-overlay-ui.test.mjs`

**Step 1: Run focused regression tests**

Run:

- `node --test tests/dictation-waveform.test.mjs tests/dictation-overlay-ui.test.mjs`

**Step 2: Run renderer type verification**

Run:

- `npm run typecheck`
- `npm run build:renderer`

Expected:

- Focused regression tests PASS
- TypeScript check passes
- Renderer build passes
