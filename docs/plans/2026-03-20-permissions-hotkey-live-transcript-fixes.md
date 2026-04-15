# Permissions, Hotkey Restore, and Live Transcript Motion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three regressions: macOS accessibility recovery after app replacement, hotkey restore after install/update, and live transcript capsule oscillation once preview text starts sliding.

**Architecture:** Keep each fix narrow and evidence-driven. For hotkeys, unify startup restore so every path resolves the saved key the same way and avoid onboarding overwriting hydrated state. For accessibility, add an explicit macOS repair flow and live permission re-sync instead of relying on stale localStorage. For live transcript motion, preserve the existing measured rail and reveal animation, but bypass reveal resets when the preview window is front-trimmed and slides forward.

**Tech Stack:** Electron 36, React 19, TypeScript, CommonJS main-process helpers, react-i18next, node:test

---

### Task 1: Lock the regressions in tests before touching behavior

**Files:**
- Create: `tests/hotkey-startup-restore.test.mjs`
- Create: `tests/accessibility-repair-flow.test.mjs`
- Modify: `tests/live-transcript-reveal.test.mjs`

**Step 1: Write the failing test**

Add tests that require:
- a shared hotkey restore resolver prefers `DICTATION_KEY`, then renderer `dictationKey`, then legacy renderer `hotkey`, then the platform default
- GNOME startup restore uses the same resolver instead of reading renderer storage directly
- onboarding keeps its local hotkey state in sync with a late-hydrated store value until the user explicitly changes it
- the macOS troubleshooting action exposes a real reset path instead of only opening settings
- live transcript reveal does not collapse to the first character when a capped preview window slides forward

**Step 2: Run test to verify it fails**

Run: `node --test tests/hotkey-startup-restore.test.mjs tests/accessibility-repair-flow.test.mjs tests/live-transcript-reveal.test.mjs`
Expected: FAIL because the restore helper, repair flow, and sliding-window reveal behavior do not exist yet

**Step 3: Write minimal implementation**

No implementation in this task.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `node --test tests/hotkey-startup-restore.test.mjs tests/accessibility-repair-flow.test.mjs tests/live-transcript-reveal.test.mjs`
Expected: FAIL on missing behavior, not on broken test wiring

### Task 2: Unify hotkey startup restore and guard onboarding hydration

**Files:**
- Create: `src/helpers/hotkeyPersistence.js`
- Modify: `src/helpers/hotkeyManager.js`
- Modify: `src/components/OnboardingFlow.tsx`

**Step 1: Write the failing test**

Use the new hotkey restore tests to prove:
- restore precedence is env first
- GNOME startup path no longer bypasses the shared restore logic
- onboarding does not keep a stale default hotkey after the store hydrates from env

**Step 2: Run test to verify it fails**

Run: `node --test tests/hotkey-startup-restore.test.mjs`
Expected: FAIL because the shared restore path and onboarding sync do not exist yet

**Step 3: Write minimal implementation**

Implement a small main-process hotkey persistence helper that:
- normalizes candidate values from env, renderer `dictationKey`, and legacy renderer `hotkey`
- returns both the chosen hotkey and whether env / renderer migration is needed

Update `HotkeyManager` so:
- GNOME startup and the normal startup path both call the same resolver
- renderer fallback values get migrated forward into env
- legacy renderer keys, if present, get normalized into `dictationKey`

Update onboarding so:
- local activation-step hotkey state follows hydrated store state until the user actually changes the hotkey
- finishing onboarding does not overwrite a restored saved hotkey with a stale default

**Step 4: Run test to verify it passes**

Run: `node --test tests/hotkey-startup-restore.test.mjs`
Expected: PASS

### Task 3: Add a real macOS accessibility repair flow and live state sync

**Files:**
- Modify: `src/helpers/clipboard.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`
- Modify: `src/hooks/usePermissions.ts`
- Modify: `src/components/SettingsPage.tsx`

**Step 1: Write the failing test**

Use the accessibility repair tests to require:
- a main-process repair entry point exists for macOS accessibility troubleshooting
- the renderer can invoke it through preload/types
- `usePermissions` re-syncs live accessibility state on mount and on focus/visibility return
- the settings troubleshooting action calls the reset flow instead of only opening System Settings

**Step 2: Run test to verify it fails**

Run: `node --test tests/accessibility-repair-flow.test.mjs`
Expected: FAIL because the reset flow and focus-based re-sync do not exist yet

**Step 3: Write minimal implementation**

Implement a user-initiated macOS repair method that:
- runs `tccutil reset Accessibility com.mouthpiece.app`
- clears any cached accessibility result
- opens the Accessibility pane after reset

Update renderer permission handling so:
- accessibility state is synchronized from the live macOS check both ways
- returning from System Settings can immediately refresh the UI without requiring a restart
- the existing troubleshooting copy is reused so no locale churn is required

**Step 4: Run test to verify it passes**

Run: `node --test tests/accessibility-repair-flow.test.mjs`
Expected: PASS

### Task 4: Stop live transcript oscillation when the preview window slides

**Files:**
- Modify: `src/utils/liveTranscriptReveal.mjs`
- Modify: `src/components/DictationCapsule.tsx`
- Modify: `tests/live-transcript-reveal.test.mjs`

**Step 1: Write the failing test**

Add a sliding-window reveal test with two capped preview strings, for example:
- previous rendered preview: `abcdefghij`
- new target preview: `bcdefghijk`

Assert the reveal seed / next rendered value does not collapse back to `""` or `"b"` once the preview is already active.

**Step 2: Run test to verify it fails**

Run: `node --test tests/live-transcript-reveal.test.mjs`
Expected: FAIL because the reveal helper currently treats a front-trimmed sliding window as a full reset

**Step 3: Write minimal implementation**

Adjust the reveal helper so a same-length front-trimmed sliding window snaps directly to the new target instead of replaying character-by-character from an empty prefix. Keep the existing progressive reveal behavior for normal append and correction cases.

**Step 4: Run test to verify it passes**

Run: `node --test tests/live-transcript-reveal.test.mjs`
Expected: PASS

### Task 5: Run full verification on the repaired paths

**Files:**
- Modify: `docs/plans/2026-03-20-permissions-hotkey-live-transcript-fixes.md`

**Step 1: Run targeted verification**

Run:
- `node --test tests/hotkey-startup-restore.test.mjs tests/accessibility-repair-flow.test.mjs tests/live-transcript-reveal.test.mjs`
- `node --test tests/hotkey-runtime-sync.test.mjs tests/hotkey-capture-exit.test.mjs tests/automatic-activation-mode.test.mjs`

Expected:
- new targeted regression tests PASS
- existing hotkey tests still PASS

**Step 2: Run repository quality checks**

Run:
- `npm run typecheck`
- `npm run lint`
- `npm run build:renderer`

Expected:
- TypeScript check passes
- lint passes
- renderer build passes

**Step 3: Record any remaining risks**

Document any residual manual validation still needed for:
- signed macOS replacement builds versus unsigned/dev replacements
- GNOME Wayland real-device startup restore
- live realtime transcription on an actual streaming provider
