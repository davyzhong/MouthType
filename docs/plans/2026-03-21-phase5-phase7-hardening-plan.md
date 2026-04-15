# Phase 5 to Phase 7 Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn Phase 5, Phase 6, and Phase 7 of the ASR roadmap into an execution-ready plan that improves direct-send quality, cross-app insertion reliability, and release confidence without taking on local realtime ASR.

**Architecture:** This batch should not try to "solve everything in audioManager.js". First, extract policy contracts for post-processing, insertion semantics, and privacy diagnostics. Second, wire those contracts through existing renderer/main-process boundaries behind feature flags and targeted tests. Third, add UI, replay/benchmark gates, and release checklists only after the underlying contracts are stable and measurable.

**Tech Stack:** Electron 36, React 19, TypeScript, Zustand, Node `node:test`, existing replay harness (`src/tools/asrReplayHarness.mjs`), existing clipboard/text monitor pipeline, GitHub Actions release workflow

---

## Scope Decisions

- Phase 4 local realtime ASR is intentionally skipped by product decision on `2026-03-21`.
- This plan assumes the current product shape remains:
  - local ASR stays batch-oriented
  - cloud realtime providers remain the low-latency path
  - the new work focuses on post-processing, insertion, reliability, privacy, and release quality
- Golden ASR fixtures are still unavailable. Phase 7 must therefore start with:
  - replay schema and smoke-run validation
  - soft benchmark gates that explain why they skipped
  - room to tighten KPI thresholds once a real fixture corpus exists
- All implementation work must continue in dedicated Git worktrees.

## Baseline Status

- Planning branch: `codex/phase5-phase7-planning`
- Planning worktree: `/Users/mac/Downloads/Projects/AICode/Mouthpiece/.worktrees/phase5-phase7-planning`
- Starting commit: `88a9f3f`
- Verified on merged `main` before this planning branch was created:
  - `node --test tests/*.test.mjs tests/*.test.cjs` -> `204` passing, `0` failing
  - `npm run typecheck` -> pass
  - `npm run build:renderer` -> pass

## Success Targets For This Batch

### Phase 5

- Make cleanup behavior strategy-driven instead of one-size-fits-all.
- Add user-visible control over terminology and auto-learned corrections.
- Reduce over-polishing risk by keeping "raw-first" and "IDE-safe" paths explicit.

### Phase 6

- Promote insertion from "best-effort paste" to an explicit insertion contract.
- Distinguish `insert`, `replace`, and `append` semantics in both telemetry and code.
- Improve fallback clarity, undo predictability, and compatibility triage for high-value apps.

### Phase 7

- Add redaction-safe diagnostics and sensitive-app boundaries.
- Extend replay/benchmark tooling so releases can be blocked by concrete quality signals.
- Produce a repeatable release checklist tied to ASR and insertion KPIs rather than intuition.

## Delivery Order

1. Phase 5 policy extraction and terminology model.
2. Phase 5 settings surfaces and prompt wiring.
3. Phase 6 insertion contract and telemetry.
4. Phase 6 executor refactor and compatibility matrix.
5. Phase 7 redaction, privacy boundaries, and sensitive-app policy.
6. Phase 7 replay/benchmark gates and release checklist.

## Proposed Contracts

### Post-Processing Policy

```ts
type OutputStrategy = "raw_first" | "light_polish" | "publishable" | "structured_rewrite";
type InputSurfaceMode =
  | "general"
  | "chat"
  | "email"
  | "document"
  | "search"
  | "form"
  | "markdown"
  | "ide";
```

### Insertion Intent

```ts
type InsertionIntent = "insert" | "replace_selection" | "append_after_selection";
type InsertionOutcomeMode = "inserted" | "replaced" | "appended" | "copied" | "failed";
```

### Privacy / Diagnostics Policy

```ts
type SensitiveAppAction =
  | "allow_full_pipeline"
  | "block_auto_learn"
  | "block_cloud_reasoning"
  | "block_paste_monitoring"
  | "block_injection";
```

## Phase 5 Plan: Strategy-Based Post-Processing and Personalization

### Task 1: Extract the post-processing policy resolver

**Files:**
- Create: `src/utils/postProcessingPolicy.ts`
- Modify: `src/utils/contextClassifier.ts`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/config/prompts.ts`
- Test: `tests/post-processing-policy.test.mjs`
- Test: `tests/context-classifier.test.mjs`

**What this task does:**

- Replace ad hoc cleanup decisions with an explicit policy resolver that chooses:
  - output strategy
  - input surface mode
  - strictness guardrails
  - whether reasoning is allowed to rewrite structure
- Expand context classification beyond the current coarse set so policy resolution can distinguish:
  - `search`
  - `form`
  - `markdown`
  - `ide`
- Keep `raw_first` and `ide` modes conservative by design.

**Benefits:**

- Creates a stable contract for all later cleanup work.
- Prevents "publishable" behavior from leaking into search bars and code editors.
- Makes Phase 5 measurable instead of prompt-only.

**Risks:**

- Misclassification can still send the wrong policy.
- Too many policy knobs can make the system hard to reason about.

**Implementation Steps:**

1. Write `tests/post-processing-policy.test.mjs` covering default policy resolution, strict IDE behavior, and app-driven mode overrides.
2. Run `node --test tests/post-processing-policy.test.mjs` and confirm it fails because the resolver does not exist yet.
3. Create `src/utils/postProcessingPolicy.ts` with pure helpers:
   - `resolvePostProcessingPolicy()`
   - `normalizeOutputStrategy()`
   - `normalizeInputSurfaceMode()`
4. Extend `src/utils/contextClassifier.ts` so classification exposes enough signals to feed the resolver without coupling prompt text directly to UI strings.
5. Wire `src/helpers/audioManager.js` and `src/config/prompts.ts` to consume the resolved policy instead of inferring behavior inline.
6. Run:
   - `node --test tests/post-processing-policy.test.mjs tests/context-classifier.test.mjs`
7. Commit this slice.

**Validation:**

- `node --test tests/post-processing-policy.test.mjs tests/context-classifier.test.mjs`

**Commit Checkpoint:**

- Suggested scope: Phase 5 policy contract only.

### Task 2: Split terminology and personalization into managed profiles

**Files:**
- Create: `src/utils/terminologyProfile.ts`
- Create: `src/utils/terminologyMigration.ts`
- Modify: `src/stores/settingsStore.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/config/prompts.ts`
- Modify: `src/services/ReasoningService.ts`
- Modify: `src/utils/correctionLearner.js`
- Test: `tests/terminology-profile.test.mjs`
- Test: `tests/correction-learner.test.mjs`
- Test: `tests/reasoning-prompts-personalization.test.mjs`

**What this task does:**

- Evolve `customDictionary` from a flat string array into a managed terminology profile containing:
  - hotwords
  - blacklisted terms
  - homophone mappings
  - organization glossary
  - learned suggestions pending review
- Add migration helpers so existing users keep their current dictionary as hotwords instead of losing data.
- Change auto-learn from "silently mutates dictionary" to "creates reviewable suggestions with provenance".

**Benefits:**

- Improves proper-noun accuracy and organization vocabulary handling.
- Makes auto-learn reversible and auditable.
- Creates a clean handoff between transcription hints and reasoning cleanup.

**Risks:**

- Storage migration bugs could lose user data if done carelessly.
- Over-aggressive homophone mappings could introduce bad rewrites.

**Implementation Steps:**

1. Write `tests/terminology-profile.test.mjs` for migration and normalization rules.
2. Write `tests/correction-learner.test.mjs` cases that assert auto-learn produces suggestions instead of mutating the final glossary directly.
3. Run the targeted tests and confirm they fail.
4. Create `src/utils/terminologyProfile.ts` with profile parsers, migration helpers, and serialization logic.
5. Update `src/stores/settingsStore.ts` and `src/hooks/useSettings.ts` to expose the richer terminology profile while preserving backward compatibility with old localStorage data.
6. Update `src/config/prompts.ts` and `src/services/ReasoningService.ts` so prompt shaping can distinguish between:
   - must-prefer terms
   - must-avoid terms
   - safe homophone normalization candidates
7. Update `src/utils/correctionLearner.js` so edits become pending suggestions with source metadata instead of immediate dictionary writes.
8. Run:
   - `node --test tests/terminology-profile.test.mjs tests/correction-learner.test.mjs tests/reasoning-prompts-personalization.test.mjs`
9. Commit this slice.

**Validation:**

- `node --test tests/terminology-profile.test.mjs tests/correction-learner.test.mjs tests/reasoning-prompts-personalization.test.mjs`

**Commit Checkpoint:**

- Suggested scope: terminology model, migration, and prompt wiring.

### Task 3: Wire post-processing policy into the dictation pipeline

**Files:**
- Modify: `src/helpers/audioManager.js`
- Modify: `src/services/ReasoningService.ts`
- Modify: `src/services/BaseReasoningService.ts`
- Modify: `src/utils/contextClassifier.ts`
- Test: `tests/audio-manager-post-processing.test.mjs`
- Test: `tests/reasoning-policy-wiring.test.mjs`

**What this task does:**

- Move cleanup/reasoning decisions out of the deepest `audioManager.js` branches and into a compact pipeline:
  - classify context
  - resolve post-processing policy
  - apply dictionary and terminology normalization
  - call reasoning only when policy allows it
- Enforce conservative guards:
  - no structured rewrite in search mode
  - no identifier rewriting in IDE-safe mode
  - minimal cleanup when the user wants raw output

**Benefits:**

- Shrinks one of the most overloaded parts of the current ASR path.
- Makes behavior easier to regression-test.
- Reduces the chance that prompt changes accidentally alter core product behavior.

**Risks:**

- Refactoring `audioManager.js` can cause regression if the call order changes subtly.
- Prompt and local normalization can fight each other if responsibilities are unclear.

**Implementation Steps:**

1. Write `tests/audio-manager-post-processing.test.mjs` to assert resolver order and no-reasoning bypass rules.
2. Run the targeted tests and confirm failure.
3. Add a small orchestration helper inside `audioManager.js` or a companion module that makes the post-processing steps explicit.
4. Update reasoning-service call sites so `ReasoningService` receives policy metadata instead of only loose context strings.
5. Add logging fields for selected strategy and surface mode.
6. Run:
   - `node --test tests/audio-manager-post-processing.test.mjs tests/reasoning-policy-wiring.test.mjs`
7. Commit this slice.

**Validation:**

- `node --test tests/audio-manager-post-processing.test.mjs tests/reasoning-policy-wiring.test.mjs`

**Commit Checkpoint:**

- Suggested scope: pipeline wiring only, no UI yet.

### Task 4: Add settings UI, i18n, and user controls for terminology and style

**Files:**
- Create: `src/components/TerminologySettingsCard.tsx`
- Create: `src/components/PostProcessingStrategyCard.tsx`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/components/DictionaryView.tsx`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/locales/en/translation.json`
- Modify: `src/locales/es/translation.json`
- Modify: `src/locales/fr/translation.json`
- Modify: `src/locales/de/translation.json`
- Modify: `src/locales/pt/translation.json`
- Modify: `src/locales/it/translation.json`
- Modify: `src/locales/ru/translation.json`
- Modify: `src/locales/ja/translation.json`
- Modify: `src/locales/zh-CN/translation.json`
- Modify: `src/locales/zh-TW/translation.json`
- Test: `tests/settings-terminology-ui.test.mjs`
- Test: `tests/settings-strategy-ui.test.mjs`

**What this task does:**

- Give users explicit control over:
  - default output strategy
  - per-surface preferences
  - hotwords / blacklists / glossary terms
  - pending auto-learn suggestions
  - the ability to review, approve, reject, and roll back personalization changes
- Keep the UI honest about what the system will do instead of hiding behavior behind prompts.

**Benefits:**

- Reduces surprise and distrust.
- Makes terminology and tone control product-grade.
- Improves supportability because users can explain what is configured.

**Risks:**

- Settings sprawl can overwhelm users if the defaults are not opinionated.
- i18n churn is high because every new control needs translation coverage.

**Implementation Steps:**

1. Write tests that assert the new settings sections render and read/write the new store fields.
2. Run the targeted tests and confirm failure.
3. Create the new settings cards and reuse `DictionaryView.tsx` where practical instead of duplicating list logic.
4. Add i18n keys for every new string in all locale files already present in `src/locales/`.
5. Ensure auto-learn pending suggestions can be reviewed without leaving Settings.
6. Run:
   - `node --test tests/settings-terminology-ui.test.mjs tests/settings-strategy-ui.test.mjs`
   - `npm run typecheck`
7. Commit this slice.

**Validation:**

- `node --test tests/settings-terminology-ui.test.mjs tests/settings-strategy-ui.test.mjs`
- `npm run typecheck`

**Commit Checkpoint:**

- Suggested scope: UI and translations only.

## Phase 6 Plan: Cross-App Insertion Semantics Hardening

### Task 5: Introduce an insertion contract across renderer and main process

**Files:**
- Create: `src/utils/insertionIntent.ts`
- Modify: `src/types/electron.ts`
- Modify: `src/hooks/useAudioRecording.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/utils/asrSessionTimeline.mjs`
- Test: `tests/insertion-intent-contract.test.mjs`
- Test: `tests/dictation-clipboard.test.mjs`

**What this task does:**

- Upgrade the existing paste IPC from a thin text pipe into a structured insertion contract that carries:
  - intent
  - target app info
  - whether selection replacement is expected
  - whether clipboard preservation is required
  - whether fallback copy is acceptable
- Extend session telemetry so insertion outcomes are no longer only `pasted/copied/failed`.

**Benefits:**

- Creates the foundation for native-feeling insertion semantics.
- Makes debugging much easier because the app can say what it intended to do, not just what happened.

**Risks:**

- Widening the IPC contract can ripple through many call sites.
- Incorrect defaults could change existing paste behavior unexpectedly.

**Implementation Steps:**

1. Write `tests/insertion-intent-contract.test.mjs` for renderer/main-process serialization and default intent selection.
2. Extend `tests/dictation-clipboard.test.mjs` so it checks structured options, not only `preserveClipboard`.
3. Run the targeted tests and confirm failure.
4. Add shared intent helpers and update `src/types/electron.ts` so new modes are typed end-to-end.
5. Update `useAudioRecording.js` and `ipcHandlers.js` to pass and log the structured intent metadata.
6. Extend `src/utils/asrSessionTimeline.mjs` with intent and outcome fields.
7. Run:
   - `node --test tests/insertion-intent-contract.test.mjs tests/dictation-clipboard.test.mjs tests/asr-session-timeline.test.mjs`
8. Commit this slice.

**Validation:**

- `node --test tests/insertion-intent-contract.test.mjs tests/dictation-clipboard.test.mjs tests/asr-session-timeline.test.mjs`

**Commit Checkpoint:**

- Suggested scope: types, IPC contract, and telemetry only.

### Task 6: Refactor the paste executor into explicit insertion plans

**Files:**
- Create: `src/helpers/insertionPlan.js`
- Modify: `src/helpers/clipboard.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/helpers/textEditMonitor.js`
- Test: `tests/insertion-plan.test.mjs`
- Test: `tests/permission-probe-paste.test.mjs`
- Test: `tests/text-edit-monitor.test.mjs`

**What this task does:**

- Replace the current mostly monolithic clipboard path with a step-by-step plan executor:
  - focus handoff
  - probe capabilities
  - choose insert / replace / append path
  - execute platform-specific method
  - decide retry or fallback copy
  - record outcome and recovery hints
- Make `TextEditMonitor` optional and intent-aware so it does not assume every successful action was a simple paste.

**Benefits:**

- Makes insertion behavior predictable and testable.
- Creates a clear home for future per-app adapters without growing `clipboard.js` into a larger blob.

**Risks:**

- Platform-specific timing bugs may appear during the refactor.
- A plan executor that is too abstract can hide practical platform quirks.

**Implementation Steps:**

1. Write `tests/insertion-plan.test.mjs` for plan selection and fallback order.
2. Add or update tests around `TextEditMonitor` so selection-replace behavior is distinct from append behavior.
3. Run the targeted tests and confirm failure.
4. Create `src/helpers/insertionPlan.js` as a pure planner that returns executable steps and fallback branches.
5. Refactor `src/helpers/clipboard.js` to execute that plan rather than hard-coding every branch inline.
6. Update `src/helpers/textEditMonitor.js` so monitoring can be disabled or downgraded per plan.
7. Run:
   - `node --test tests/insertion-plan.test.mjs tests/permission-probe-paste.test.mjs tests/text-edit-monitor.test.mjs`
8. Commit this slice.

**Validation:**

- `node --test tests/insertion-plan.test.mjs tests/permission-probe-paste.test.mjs tests/text-edit-monitor.test.mjs`

**Commit Checkpoint:**

- Suggested scope: executor refactor only.

### Task 7: Add compatibility profiles, retries, and user-facing fallback semantics

**Files:**
- Create: `src/config/insertionCompatibilityProfiles.ts`
- Create: `docs/qa/cross-app-insertion-matrix.md`
- Modify: `src/helpers/clipboard.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/hooks/useAudioRecording.js`
- Modify: `src/locales/en/translation.json`
- Modify: `src/locales/es/translation.json`
- Modify: `src/locales/fr/translation.json`
- Modify: `src/locales/de/translation.json`
- Modify: `src/locales/pt/translation.json`
- Modify: `src/locales/it/translation.json`
- Modify: `src/locales/ru/translation.json`
- Modify: `src/locales/ja/translation.json`
- Modify: `src/locales/zh-CN/translation.json`
- Modify: `src/locales/zh-TW/translation.json`
- Test: `tests/insertion-compatibility-profiles.test.mjs`
- Test: `tests/use-audio-recording-paste-feedback.test.mjs`

**What this task does:**

- Create a small compatibility-profile system for high-value app families:
  - browser textareas/contenteditable
  - Electron editors
  - chat apps
  - document editors
  - terminals / IDEs
- Define which retries and which degraded modes are allowed for each profile.
- Improve user-facing messages so fallback copy, manual paste, and retry hints are honest and context-specific.

**Benefits:**

- Lowers insertion failure rate where users feel it most.
- Turns app-specific weirdness into a documented matrix instead of tribal knowledge.

**Risks:**

- App profiles can become expensive to maintain if they grow without KPI evidence.
- Over-targeting specific apps too early can hide broader contract problems.

**Implementation Steps:**

1. Write `tests/insertion-compatibility-profiles.test.mjs` for profile selection and retry policy.
2. Write or extend UI feedback tests for paste-result messaging in `useAudioRecording.js`.
3. Run the targeted tests and confirm failure.
4. Add the compatibility profile config and keep it data-driven.
5. Update `clipboard.js` and `ipcHandlers.js` to consult the profile config for retry and fallback decisions.
6. Create `docs/qa/cross-app-insertion-matrix.md` listing:
   - target app family
   - expected insertion mode
   - retry policy
   - known gaps
7. Add i18n for any new fallback or recovery text.
8. Run:
   - `node --test tests/insertion-compatibility-profiles.test.mjs tests/use-audio-recording-paste-feedback.test.mjs`
   - `npm run typecheck`
9. Commit this slice.

**Validation:**

- `node --test tests/insertion-compatibility-profiles.test.mjs tests/use-audio-recording-paste-feedback.test.mjs`
- `npm run typecheck`

**Commit Checkpoint:**

- Suggested scope: compatibility data, retry policy, and UX copy.

## Phase 7 Plan: Reliability, Privacy, and Release Hardening

### Task 8: Add redaction-safe diagnostics and sensitive-app policy

**Files:**
- Create: `src/utils/logRedaction.ts`
- Create: `src/config/sensitiveAppPolicy.ts`
- Modify: `src/helpers/debugLogger.js`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/utils/contextClassifier.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/stores/settingsStore.ts`
- Test: `tests/log-redaction.test.mjs`
- Test: `tests/sensitive-app-policy.test.mjs`

**What this task does:**

- Add a central redaction layer so logs and diagnostics stop depending on call sites to "remember to be careful".
- Add a sensitive-app policy that can:
  - disable cloud reasoning
  - disable paste monitoring / auto-learn
  - disable insertion entirely for blocked apps if needed
- Make the target-app metadata already captured by `TextEditMonitor` useful for privacy boundaries, not only context classification.

**Benefits:**

- Improves privacy trust.
- Reduces the risk of leaking dictated text into logs or diagnostics.
- Gives the product a concrete answer when users ask what happens in password or finance-related apps.

**Risks:**

- Over-blocking could frustrate users if app matching is too broad.
- Redaction that is too aggressive can make debugging impossible.

**Implementation Steps:**

1. Write `tests/log-redaction.test.mjs` covering transcript text, API keys, and clipboard payload redaction.
2. Write `tests/sensitive-app-policy.test.mjs` for blocklist/profile matching and policy actions.
3. Run the targeted tests and confirm failure.
4. Add `src/utils/logRedaction.ts` and route `debugLogger.js` metadata writes through it.
5. Add `src/config/sensitiveAppPolicy.ts` with a minimal initial ruleset and obvious extension points.
6. Update `audioManager.js`, `ipcHandlers.js`, and `contextClassifier.ts` so sensitive-app actions are enforced before cloud routing, paste monitoring, or auto-learn.
7. Expose the relevant privacy switches through settings state.
8. Run:
   - `node --test tests/log-redaction.test.mjs tests/sensitive-app-policy.test.mjs`
9. Commit this slice.

**Validation:**

- `node --test tests/log-redaction.test.mjs tests/sensitive-app-policy.test.mjs`

**Commit Checkpoint:**

- Suggested scope: privacy boundaries and logging only.

### Task 9: Extend replay outputs into benchmarkable ASR and insertion reports

**Files:**
- Create: `scripts/verify-asr-benchmarks.mjs`
- Create: `src/tools/asrBenchmarkReport.mjs`
- Modify: `src/tools/asrReplayHarness.mjs`
- Modify: `scripts/run-asr-replay.mjs`
- Modify: `src/utils/asrSessionTimeline.mjs`
- Test: `tests/asr-benchmark-report.test.mjs`
- Test: `tests/asr-session-timeline.test.mjs`
- Test: `tests/asr-foundation-wiring.test.mjs`

**What this task does:**

- Extend the replay harness so it can emit a benchmark-friendly summary, not just raw per-case results.
- Add KPI fields for the parts we can measure before a golden dataset exists:
  - replay completion/skips/failures
  - insertion outcome distribution
  - first partial / final / inserted latency percentiles when replay data exists
  - explicit skip reasons when no fixtures are available
- Keep the first version tolerant of an empty fixture directory while still producing machine-readable output.

**Benefits:**

- Makes Phase 7 automation possible now, before the full corpus exists.
- Creates a straight path from manual smoke fixtures to hard release gates later.

**Risks:**

- Weak benchmark gates can create a false sense of safety if they are treated as enough.
- Too many placeholder metrics can become noise.

**Implementation Steps:**

1. Write `tests/asr-benchmark-report.test.mjs` for summary generation and empty-fixture behavior.
2. Extend existing replay/timeline tests to cover the new report fields.
3. Run the targeted tests and confirm failure.
4. Create the benchmark report module and add `scripts/verify-asr-benchmarks.mjs` to enforce threshold or skip semantics.
5. Update the replay harness and CLI so they can output both case detail and summary detail.
6. Run:
   - `node --test tests/asr-benchmark-report.test.mjs tests/asr-session-timeline.test.mjs tests/asr-foundation-wiring.test.mjs`
   - `npm run replay:asr -- --output tmp/asr-replay.json`
7. Commit this slice.

**Validation:**

- `node --test tests/asr-benchmark-report.test.mjs tests/asr-session-timeline.test.mjs tests/asr-foundation-wiring.test.mjs`
- `npm run replay:asr -- --output tmp/asr-replay.json`

**Commit Checkpoint:**

- Suggested scope: replay metrics and benchmark verifier only.

### Task 10: Gate releases on benchmark and privacy checks, then write the operational checklist

**Files:**
- Create: `docs/release/asr-quality-checklist.md`
- Modify: `.github/workflows/release.yml`
- Modify: `package.json`
- Modify: `tests/update-release-assets.test.mjs`
- Modify: `tests/whisper-download-release-source.test.mjs`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/locales/en/translation.json`
- Modify: `src/locales/es/translation.json`
- Modify: `src/locales/fr/translation.json`
- Modify: `src/locales/de/translation.json`
- Modify: `src/locales/pt/translation.json`
- Modify: `src/locales/it/translation.json`
- Modify: `src/locales/ru/translation.json`
- Modify: `src/locales/ja/translation.json`
- Modify: `src/locales/zh-CN/translation.json`
- Modify: `src/locales/zh-TW/translation.json`
- Test: `tests/release-benchmark-gate.test.mjs`
- Test: `tests/update-release-assets.test.mjs`
- Test: `tests/whisper-download-release-source.test.mjs`

**What this task does:**

- Add release workflow steps that fail a release when:
  - replay/benchmark verification fails
  - privacy-sensitive checks fail
  - required artifacts or summaries are missing
- Create a human-readable release checklist for ASR quality, insertion quality, and privacy validation.
- Optionally expose a small Settings or developer UI section that shows benchmark/report status and log redaction state for local verification.

**Benefits:**

- Converts Phase 7 from "we should be careful" into a repeatable shipping process.
- Gives future roadmap phases a safer landing path.

**Risks:**

- CI friction will increase if the gates are noisy or under-specified.
- The checklist can rot if it is not tied to automated outputs.

**Implementation Steps:**

1. Write `tests/release-benchmark-gate.test.mjs` or extend existing workflow tests to assert the release workflow now runs benchmark verification.
2. Run the targeted tests and confirm failure.
3. Add a package script for benchmark verification if it improves local and CI parity.
4. Update `.github/workflows/release.yml` to run the verifier before packaging and release upload.
5. Create `docs/release/asr-quality-checklist.md` with:
   - minimum replay expectations
   - insertion smoke matrix
   - sensitive-app/privacy review items
   - rollback criteria
6. Add any necessary i18n or developer-surface strings if the status is exposed in-app.
7. Run:
   - `node --test tests/release-benchmark-gate.test.mjs tests/update-release-assets.test.mjs tests/whisper-download-release-source.test.mjs`
   - `node --test tests/*.test.mjs tests/*.test.cjs`
   - `npm run typecheck`
   - `npm run build:renderer`
8. Commit this slice.

**Validation:**

- `node --test tests/release-benchmark-gate.test.mjs tests/update-release-assets.test.mjs tests/whisper-download-release-source.test.mjs`
- `node --test tests/*.test.mjs tests/*.test.cjs`
- `npm run typecheck`
- `npm run build:renderer`

**Commit Checkpoint:**

- Suggested scope: release workflow and operational checklist.

## Cross-Phase Guardrails

- Do not let Phase 5 introduce large prompt-only behavior changes without a matching policy test.
- Do not let Phase 6 add app-specific adapters before the insertion contract and planner exist.
- Do not let Phase 7 add logging or telemetry without redaction coverage.
- Keep risky behavior behind feature flags where rollout risk is non-trivial.
- Prefer pure helper modules and contract tests over pushing more conditional logic into `audioManager.js` and `clipboard.js`.

## Suggested Commit Sequence

1. Phase 5 policy contract
2. Phase 5 terminology model
3. Phase 5 pipeline wiring
4. Phase 5 UI and i18n
5. Phase 6 insertion contract
6. Phase 6 executor refactor
7. Phase 6 compatibility matrix and UX copy
8. Phase 7 redaction and sensitive-app policy
9. Phase 7 replay benchmark report
10. Phase 7 release workflow and checklist

## Final Verification For The Whole Plan

Run these after the final implementation batch for Phase 5 through Phase 7:

```bash
node --test tests/*.test.mjs tests/*.test.cjs
npm run typecheck
npm run build:renderer
npm run replay:asr -- --output tmp/asr-replay.json
node scripts/verify-asr-benchmarks.mjs --input tmp/asr-replay.json
```

## Review Questions Before Implementation

- Should `raw_first` remain the global default, with app-specific opt-in to stronger cleanup, or should some surfaces default to `light_polish` immediately?
- For sensitive apps, should the first rollout block only cloud reasoning and auto-learn, or should it also block insertion for a stricter privacy posture?
- Should the first Phase 6 compatibility matrix target only a few app families, or should it include every currently supported fallback path from day one?

Plan complete and saved to `docs/plans/2026-03-21-phase5-phase7-hardening-plan.md`.
