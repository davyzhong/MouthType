# Soniox Transcription Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose Soniox as a first-class cloud transcription provider with a provider-level realtime toggle that switches between async batch transcription and realtime streaming transcription.

**Architecture:** Reuse the existing cloud transcription picker and BYOK settings flow, but add Soniox as an explicit provider with its own API key and realtime toggle. Batch mode will use Soniox's async REST flow (`/v1/files` -> `/v1/transcriptions` -> polling -> `/transcript`), while realtime mode will use Soniox's WebSocket API (`wss://stt-rt.soniox.com/transcribe-websocket`) with `audio_format: "auto"`, manual `finalize`, keepalive support, and partial/final token aggregation for live dictation UI updates.

**Tech Stack:** React 19, TypeScript, Zustand, Electron IPC/preload bridge, Node `ws`, node:test source-assertion tests

---

### Task 1: Lock the Soniox contract with failing tests

**Files:**
- Create: `tests/soniox-provider.test.mjs`
- Create: `tests/soniox-ui-wiring.test.mjs`

**Step 1: Write the failing test**

Add assertions that:
- `src/models/modelRegistryData.json` exposes a `soniox` transcription provider with `stt-async-v4` and `stt-rt-v4`.
- `src/components/TranscriptionModelPicker.tsx` exposes Soniox as a provider tab and accepts Soniox API key + realtime toggle props.
- `src/components/SettingsPage.tsx` passes Soniox props into `TranscriptionModelPicker`.
- A new shared Soniox helper module exists for stream config / transcript assembly behavior.

**Step 2: Run test to verify it fails**

Run: `node --test tests/soniox-provider.test.mjs tests/soniox-ui-wiring.test.mjs`

Expected: FAIL because Soniox is not yet wired into the registry, settings, picker, or helpers.

### Task 2: Add Soniox metadata and shared helpers

**Files:**
- Modify: `src/models/modelRegistryData.json`
- Create: `src/helpers/sonioxShared.js`

**Step 1: Write minimal implementation**

Add Soniox to the transcription provider registry with:
- provider id `soniox`
- base URL `https://api.soniox.com/v1`
- async model `stt-async-v4`
- realtime model `stt-rt-v4`

Create shared helper utilities that:
- choose the correct Soniox model based on realtime toggle
- build realtime WebSocket config using `audio_format: "auto"`
- merge Soniox final/non-final tokens into live partial text and stable final text
- detect `<fin>` tokens from manual finalization

**Step 2: Run test to verify it passes**

Run: `node --test tests/soniox-provider.test.mjs`

Expected: PASS for provider metadata and helper assertions.

### Task 3: Add Soniox settings state and runtime selection

**Files:**
- Modify: `src/stores/settingsStore.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/helpers/audioManager.js`

**Step 1: Write minimal implementation**

Add persisted settings for:
- `sonioxApiKey`
- `sonioxRealtimeEnabled`

Update runtime selection so:
- `getAPIKey()` returns the Soniox key for provider `soniox`
- `getTranscriptionModel()` defaults to `stt-async-v4` or `stt-rt-v4` depending on realtime toggle
- `shouldUseStreaming()` supports provider-specific BYOK streaming for Soniox instead of only Mouthpiece Cloud config

**Step 2: Run test to verify it passes**

Run: `node --test tests/soniox-provider.test.mjs tests/soniox-ui-wiring.test.mjs`

Expected: PASS for source assertions covering settings and runtime selection.

### Task 4: Implement Soniox async batch transcription

**Files:**
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`
- Modify: `src/helpers/audioManager.js`

**Step 1: Write the failing test**

Extend `tests/soniox-provider.test.mjs` with assertions that:
- Soniox async IPC endpoints exist.
- `audioManager` routes Soniox batch mode through dedicated Soniox code, not OpenAI-style `/audio/transcriptions`.

**Step 2: Run test to verify it fails**

Run: `node --test tests/soniox-provider.test.mjs`

Expected: FAIL because Soniox async handlers are not implemented yet.

**Step 3: Write minimal implementation**

Implement Soniox async flow in main/preload/renderer:
- upload audio to `POST /v1/files`
- create transcription via `POST /v1/transcriptions`
- poll `GET /v1/transcriptions/{id}`
- fetch final transcript via `GET /v1/transcriptions/{id}/transcript`
- clean up uploaded files / transcriptions best-effort

**Step 4: Run test to verify it passes**

Run: `node --test tests/soniox-provider.test.mjs`

Expected: PASS.

### Task 5: Implement Soniox realtime streaming

**Files:**
- Create: `src/helpers/sonioxStreaming.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`
- Modify: `src/helpers/audioManager.js`

**Step 1: Write the failing test**

Extend `tests/soniox-provider.test.mjs` with assertions that:
- a dedicated Soniox streaming helper exists
- preload/types expose Soniox streaming methods and event listeners
- `AudioManager` includes Soniox in `STREAMING_PROVIDERS`

**Step 2: Run test to verify it fails**

Run: `node --test tests/soniox-provider.test.mjs`

Expected: FAIL because Soniox streaming plumbing does not exist yet.

**Step 3: Write minimal implementation**

Implement Soniox realtime flow using official protocol details:
- connect to `wss://stt-rt.soniox.com/transcribe-websocket`
- send config JSON containing API key, realtime model, and `audio_format: "auto"`
- send audio as binary frames
- emit partial/live text from non-final tokens
- emit stable final text from final tokens
- send `{"type":"finalize"}` on stop
- honor keepalive with `{"type":"keepalive"}` during pauses
- detect `<fin>` and finish cleanly
- send empty frame to close gracefully

**Step 4: Run test to verify it passes**

Run: `node --test tests/soniox-provider.test.mjs`

Expected: PASS.

### Task 6: Wire Soniox controls into the UI and translations

**Files:**
- Modify: `src/components/TranscriptionModelPicker.tsx`
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

**Step 1: Write minimal implementation**

Update the picker and settings UI so:
- Soniox appears as a cloud provider tab
- Soniox shows a dedicated API key input
- Soniox shows a realtime toggle with clear description
- toggle `on` means live partial/final streaming
- toggle `off` means async batch transcription

Add only the new translation keys required for the Soniox provider UI.

**Step 2: Run test to verify it passes**

Run: `node --test tests/soniox-provider.test.mjs tests/soniox-ui-wiring.test.mjs`

Expected: PASS.

### Task 7: Verify end-to-end

**Files:**
- Modify: `src/helpers/audioManager.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/helpers/sonioxStreaming.js`

**Step 1: Run verification**

Run:
- `node --test tests/soniox-provider.test.mjs tests/soniox-ui-wiring.test.mjs`
- `npm run typecheck`
- `npm run i18n:check`

Expected: tests pass, TypeScript is clean, and i18n validation is clean.
