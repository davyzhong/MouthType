# ASR Modernization Roadmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn Mouthpiece from a strong dictation app with cloud realtime strengths into a measurable, low-latency, stable, publish-quality ASR system with durable local and cloud paths.

**Architecture:** The work should proceed in layers. First, establish measurement, session abstraction, and a formal state model. Second, improve capture/VAD and incremental transcript stability. Third, add local low-latency streaming and stronger personalization/injection semantics. Every later phase should depend on the interfaces, metrics, and regression scaffolding established in the early phases.

**Tech Stack:** Electron, React 19, TypeScript, Zustand, Node `node:test`, whisper.cpp, sherpa-onnx/Parakeet, Deepgram, Soniox, Bailian/Qwen realtime, better-sqlite3

---

## Baseline Status

- Work for this roadmap must be performed in a dedicated Git worktree.
- Baseline verification run on `2026-03-21` in the implementation worktree:
  - Command: `node --test tests/*.test.mjs tests/*.test.cjs`
  - Result: `177` passing, `1` failing
  - Existing failure: [tests/control-panel-layout.test.mjs](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/tests/control-panel-layout.test.mjs)
- The current red baseline should be treated as a known pre-existing issue unless explicitly fixed as part of this roadmap.

## Progress Update 2026-03-21

### Completed in this batch

- Restored the red baseline by fixing the brittle control-panel layout regression test.
- Added a normalized ASR session timeline schema with session IDs, lifecycle events, and derived latency metrics.
- Added ASR feature-flag plumbing for session timeline, replay harness, formal dictation state, unified session contract, multi-state VAD, and incremental stabilizer rollout.
- Added a headless replay harness scaffold plus CLI entry point:
  - `src/tools/asrReplayHarness.mjs`
  - `scripts/run-asr-replay.mjs`
  - `npm run replay:asr`
- Added a formal dictation session state model and wired the overlay visibility helpers and `App.jsx` to consume that state.
- Wired `useAudioRecording.js` and `audioManager.js` so active dictation sessions now carry `sessionId` metadata across recording, transcription completion, and paste delivery.

### Still intentionally pending

- Golden fixture set and real-world transcript corpus.
- Replay execution through a production ASR processor adapter instead of scaffold-only skip behavior.
- Full unified ASR session contract across every provider path.
- Error taxonomy normalization across provider, device, network, and insertion failures.
- Orchestration split-out from `audioManager.js` into smaller phase-1 session modules.

### Verification after this batch

- `node --test tests/*.test.mjs tests/*.test.cjs`
- `npm run typecheck`
- `npm run build:renderer`

### Completed in the Phase 2 and Phase 3 batch

- Replaced the realtime streaming silence gate with a multi-state gate that now models `idle`, `pre_speech`, `speaking`, and `hangover`.
- Added adaptive noise-floor tracking and short hangover logic so low-energy room tone no longer opens the gate as easily, while short pauses do not instantly collapse speech detection.
- Wired `audioManager.js` to hold realtime partials until the gate reports active speech and to discard silent-stop transcripts only when speech was never detected during the session.
- Added `src/utils/liveTranscriptStabilizer.mjs` with frozen, semi-stable, and active rewrite regions plus explicit commit handling for provider-confirmed segments.
- Wired `useAudioRecording.js` so live partial preview text is stabilized before it reaches the overlay and so frozen-prefix growth can promote the session into the formal `first_stable_partial` state.
- Kept the new multi-state VAD and incremental stabilizer behind the existing ASR rollout flags, with the current roadmap batch enabling them by default while preserving an opt-out path for later tuning.

### Still intentionally pending from Phase 2 and Phase 3

- Timestamped ring-buffer pre-roll.
- Device-loss detection and live-session rebuild.
- Clearer low-volume, no-audio, and audio-health feedback.
- Minimal diff-aware renderer updates beyond string-level stabilization.
- Explicit UI presentation for stable-partial and finalizing overlay states.

### Verification after the Phase 2 and Phase 3 batch

- `node --test tests/streaming-silence-gate.test.mjs tests/live-transcript-stabilizer.test.mjs tests/live-transcript-stabilizer-wiring.test.mjs`
- `node --test tests/*.test.mjs tests/*.test.cjs`
- `npm run typecheck`
- `npm run build:renderer`

## Guiding Principles

- Measure before optimizing.
- Do not add a new ASR provider path without capability metadata and regression coverage.
- Prefer thin orchestration layers over duplicating provider logic.
- Avoid UI-driven test harnesses when a headless runner can exercise the same pipeline more deterministically.
- Add feature flags for all risky behavior changes.
- Keep local and cloud behavior aligned wherever the UX contract should match.

## Replay Harness Decision

### Recommendation

Implement a **thin replay harness** that reuses the current ASR/provider/post-processing code paths, rather than building a totally separate benchmarking engine and rather than driving the overlay/hotkey/UI flow end-to-end.

### Why

- Directly driving the current UI flow is possible, but it is brittle because the current app flow depends on `getUserMedia`, overlay focus behavior, hotkeys, Electron window state, and renderer/browser APIs.
- A thin replay runner can still execute the real ASR pipeline by invoking the same provider/session adapters, post-processing, and normalization code in a controlled environment.
- This keeps benchmark logic close to production logic without forcing CI and regression work to simulate microphones and windows.

### Short-Term Plan Without a Golden Dataset

- Build the replay harness scaffold first.
- Define the fixture format and output schema first.
- Allow the dataset directory to be empty initially.
- Start by validating the runner on a few manually curated local audio samples later.

### Non-Recommended Option

- Do not depend on “manually replaying the current app flow” as the primary regression mechanism.
- It is acceptable for occasional debugging, but it is not a stable foundation for KPI tracking or automated comparison.

## Phased Roadmap

## Phase 0: Measurement, KPI Plumbing, and Replay Scaffolding

**Objective:** Establish a trustworthy measurement layer so every later ASR change can be evaluated against the same contract.

**Exit Criteria:**

- Every dictation session emits a normalized lifecycle timeline.
- A replay harness exists and can run against an empty or minimal fixture directory.
- Benchmark output has a stable machine-readable format.
- Risky ASR changes can be gated behind feature flags.

**Primary Files/Areas:**

- [src/helpers/audioManager.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/helpers/audioManager.js)
- [src/hooks/useAudioRecording.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/hooks/useAudioRecording.js)
- [src/helpers/ipcHandlers.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/helpers/ipcHandlers.js)
- [src/helpers/debugLogger.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/helpers/debugLogger.js)
- [package.json](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/package.json)
- New benchmark/replay files under `scripts/` or `src/tools/`

**Work Items:**

1. Define a normalized ASR session event schema.
What it does:
Create a shared event model for `session_started`, `capture_ready`, `first_partial`, `first_stable_partial`, `final_ready`, `paste_started`, `paste_finished`, `fallback_used`, `cancelled`, and `error`.
Benefits:
Makes latency and failure KPIs measurable across local and cloud paths.
Risks:
If event semantics are vague, later metrics will be misleading.

2. Add per-session IDs and timestamp capture to dictation flows.
What it does:
Attach one `sessionId` to each dictation lifecycle and propagate it across recording, transcription, post-processing, and insertion.
Benefits:
Allows correlation of failures and timings across subsystems.
Risks:
If propagation is partial, logs and metrics will become fragmented.

3. Build a headless replay harness that reuses production provider/post-process code.
What it does:
Add a CLI or Node entry point that can load audio fixtures, run them through selected ASR paths, and save structured results.
Benefits:
Enables regression comparison without driving the overlay UI.
Risks:
If the runner bypasses too much production logic, it loses benchmark value.

4. Define a fixture manifest and benchmark result schema.
What it does:
Standardize fixture metadata such as language, noise level, expected transcript, proper nouns, and scenario tags.
Benefits:
Lets the team add a real golden set incrementally.
Risks:
Overdesigning the schema before using it can slow down delivery.

5. Add feature flags for new ASR/VAD/stabilizer behavior.
What it does:
Create runtime switches for experimental VAD, stabilizer, and replay instrumentation.
Benefits:
Reduces rollout risk and supports controlled A/B-style testing later.
Risks:
Too many flags can make reasoning about behavior harder.

## Phase 1: Unified Session Abstraction and Formal State Machine

**Objective:** Replace the current scattered booleans and provider-specific branching with a unified ASR session contract and a single state source of truth.

**Exit Criteria:**

- Business/UI code uses one session abstraction for local/cloud and batch/streaming.
- Dictation UI states come from a formal state model rather than ad hoc booleans.
- Core responsibilities are split so `audioManager.js` is no longer the sole orchestrator for everything.

**Primary Files/Areas:**

- [src/helpers/audioManager.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/helpers/audioManager.js)
- [src/hooks/useAudioRecording.js](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/hooks/useAudioRecording.js)
- [src/App.jsx](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/App.jsx)
- [src/utils/dictationOverlayState.mjs](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/utils/dictationOverlayState.mjs)
- [src/stores/](/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase0-phase1-foundation/src/stores)
- New session/state modules under `src/`

**Work Items:**

1. Define the ASR session contract.
What it does:
Standardize the interface around `startSession`, `appendAudio`, `flush`, `finalize`, `cancel`, `updateContext`, and `getCapabilities`.
Benefits:
Makes provider replacement and local/cloud parity much easier.
Risks:
If the interface is too batch-oriented or too streaming-oriented, one side will be awkward.

2. Introduce a formal dictation state model.
What it does:
Represent `Idle`, `Arming`, `Listening`, `SpeechDetected`, `Processing`, `PartialStable`, `Finalizing`, `Inserted`, `PermissionRequired`, `OfflineFallback`, and `Error` explicitly.
Benefits:
Improves correctness, UI clarity, and recovery logic.
Risks:
State migration will touch multiple layers and may create temporary regressions.

3. Split orchestration responsibilities out of `audioManager.js`.
What it does:
Extract capture/session routing/post-processing/insertion coordination into smaller modules.
Benefits:
Reduces long-term change risk and makes testing more targeted.
Risks:
Poor module boundaries can create more indirection without reducing complexity.

4. Normalize error classes and recovery actions.
What it does:
Map provider, permission, network, device, and insertion failures into a stable error taxonomy.
Benefits:
Allows predictable user messaging and automated recovery.
Risks:
If the taxonomy is too coarse, it will hide useful distinctions.

## Phase 2: Capture Resilience and Multi-State VAD

**Objective:** Reduce swallowed first words, false starts, bad endpointing, and device fragility.

**Key Work:**

- Add timestamped ring buffer pre-roll.
- Introduce multi-state VAD with hangover.
- Add adaptive noise floor estimation.
- Detect device loss and rebuild live sessions.
- Add clearer low-volume/no-audio/audio health feedback.

**Benefits:**

- Better first-word capture.
- Lower false segmentation.
- Better real-world stability.

**Risks:**

- Tuning across languages and environments will take iteration.

## Phase 3: Incremental Transcript Stabilizer

**Objective:** Turn realtime output into stable, readable, low-jitter text growth.

**Key Work:**

- Add frozen/semi-stable/active rewrite regions.
- Add stable-prefix detection.
- Add minimal diff merge logic.
- Add explicit UI feedback for stable partial/finalizing states.

**Benefits:**

- Lower partial jitter rate.
- Better perceived quality.

**Risks:**

- Freezing too early can preserve errors; freezing too late preserves jitter.

## Phase 4: Local Low-Latency Streaming ASR

**Objective:** Add true local low-latency dictation instead of local batch-only transcription.

**Key Work:**

- Implement local session adapters for Whisper/Parakeet.
- Add sliding windows and overlap stitching.
- Add local endpoint-aware flush behavior.
- Add local resource budgeting and prewarm controls.

**Benefits:**

- Offline low-latency dictation.
- Better privacy and network independence.

**Risks:**

- High engineering cost and higher CPU/thermal pressure.

## Phase 5: Strategy-Based Post-Processing and Personalization

**Objective:** Improve direct-send quality by making cleanup and personalization scenario-aware.

**Key Work:**

- Add output strategies: raw-first, light polish, publishable, structured rewrite.
- Add app/input mode strategies: chat, email, document, search, form, markdown, IDE-safe.
- Add managed terminology: hotwords, blacklists, homophone mappings, org glossary.
- Add reviewable and reversible auto-learn behavior.

**Benefits:**

- Better one-shot send rate.
- Better proper noun performance.

**Risks:**

- Over-processing can make output feel unlike the speaker.

## Phase 6: Cross-App Insertion Semantics Hardening

**Objective:** Make insertion feel more like native typing and less like a best-effort paste.

**Key Work:**

- Add insert vs replace vs append semantics.
- Improve caret and selection handling.
- Improve undo consistency.
- Build a compatibility matrix and targeted adapters for high-value apps.
- Add structured retry and fallback behavior.

**Benefits:**

- Lower insertion failure rate.
- Better trust in cross-app behavior.

**Risks:**

- Platform-specific adapter maintenance cost.

## Phase 7: Reliability, Privacy, and Release Hardening

**Objective:** Make the product durable for daily use and safer to ship repeatedly.

**Key Work:**

- Add crash/perf collection and redaction-safe diagnostics.
- Add sensitive-app handling and clearer context/privacy boundaries.
- Add benchmark gating to CI/release checks.
- Add a release checklist tied to real ASR and insertion quality metrics.

**Benefits:**

- Better crash-free rate and release confidence.
- Better privacy trust.

**Risks:**

- Observability work can sprawl if not tied to concrete KPIs.

## Immediate Execution Scope

The immediate implementation scope for the current worktree is:

- Phase 0 scaffolding except for a real golden dataset.
- Phase 1 foundational abstractions and state-model groundwork.

The immediate implementation scope explicitly excludes:

- Full local realtime ASR delivery.
- Full VAD rewrite.
- Full incremental stabilizer rollout.
- Full per-app insertion adapter matrix.

## Immediate Task Batch A: Phase 0 Foundation

**Planned Files:**

- Create: `src/types/asrSession.ts`
- Create: `src/utils/asrSessionMetrics.ts`
- Create: `scripts/replay-asr-session.mjs`
- Create: `tests/asr-session-metrics.test.mjs`
- Create: `tests/replay-harness-smoke.test.mjs`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/hooks/useAudioRecording.js`
- Modify: `package.json`

**Intent:**

- Introduce normalized session metrics/events.
- Add a replay harness scaffold that can run without a complete golden set.
- Add tests for the schema and smoke behavior.

## Immediate Task Batch B: Phase 1 Foundation

**Planned Files:**

- Create: `src/types/dictationState.ts`
- Create: `src/utils/dictationStateMachine.ts`
- Create: `tests/dictation-state-machine.test.mjs`
- Modify: `src/hooks/useAudioRecording.js`
- Modify: `src/App.jsx`
- Modify: `src/utils/dictationOverlayState.mjs`
- Modify: `src/helpers/audioManager.js`

**Intent:**

- Make dictation state transitions explicit.
- Reduce dependence on loosely coupled booleans.
- Prepare later VAD/stabilizer work to hook into a stable state model.

## Validation Rules For Future Changes

- Every roadmap task should reference the relevant phase in this file.
- Every risky behavior change should add or update a test.
- Every latency-related change should either emit metrics or consume existing metrics.
- New ASR paths should prefer reusing the session contract instead of creating parallel orchestration.
- If a phase requires a dataset that does not yet exist, implement the scaffold first and mark the dataset-dependent parts as pending.

## Open Items

- Whether to repair the current pre-existing failing control-panel layout test before Phase 0/1 implementation begins.
- Which benchmark result format to standardize on first: JSON only, or JSON plus markdown summary.
- Whether feature flags should live in runtime config, local settings, or both.
