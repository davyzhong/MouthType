# Bailian Transcription Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose Alibaba Bailian as a first-class cloud transcription provider in Settings, instead of only reaching DashScope through the generic custom provider path.

**Architecture:** Reuse the existing cloud transcription picker and the already-supported Bailian API key storage, but promote Bailian into the transcription provider registry and runtime provider switch. Add a small normalization layer so legacy custom DashScope transcription setups automatically land on the explicit Bailian provider without deleting the user's custom endpoint state.

**Tech Stack:** React 19, TypeScript, Zustand, Electron preload IPC, node:test source-assertion tests

---

### Task 1: Lock the new UI contract with failing tests

**Files:**
- Modify: `tests/custom-api-settings-ui.test.mjs`
- Create: `tests/transcription-bailian-provider.test.mjs`

**Step 1: Write the failing test**

Add assertions that:
- `src/components/TranscriptionModelPicker.tsx` exposes `bailian` in the cloud provider tabs.
- `src/components/TranscriptionModelPicker.tsx` has an explicit `selectedCloudProvider === "bailian"` branch with `bailianApiKey`.
- `src/components/SettingsPage.tsx` passes Bailian key props into `TranscriptionModelPicker`.
- A new helper file normalizes legacy custom DashScope transcription settings into the explicit Bailian provider.

**Step 2: Run test to verify it fails**

Run: `node --test tests/custom-api-settings-ui.test.mjs tests/transcription-bailian-provider.test.mjs`

Expected: FAIL because transcription does not yet expose `bailian`, and the normalization helper does not exist yet.

### Task 2: Add explicit Bailian provider metadata and picker props

**Files:**
- Modify: `src/models/modelRegistryData.json`
- Modify: `src/components/TranscriptionModelPicker.tsx`
- Modify: `src/components/SettingsPage.tsx`

**Step 1: Write minimal implementation**

Add Bailian to the transcription provider list with DashScope base URL and at least one supported Qwen ASR model. Extend picker props with `bailianApiKey` and `setBailianApiKey`, add the Bailian tab, show its dedicated API key panel, and keep `custom` as the real arbitrary endpoint provider.

**Step 2: Run test to verify it passes**

Run: `node --test tests/custom-api-settings-ui.test.mjs`

Expected: PASS for the transcription UI assertions.

### Task 3: Normalize and migrate legacy custom DashScope transcription state

**Files:**
- Create: `src/utils/transcriptionProviderConfig.mjs`
- Modify: `src/stores/settingsStore.ts`

**Step 1: Write minimal implementation**

Create a helper that:
- Detects DashScope-compatible transcription base URLs.
- Returns normalized explicit Bailian provider settings for legacy `custom` + DashScope setups.
- Copies the custom transcription key into the Bailian key slot when the Bailian slot is empty.

Use it for initial store state and startup migration persistence.

**Step 2: Run test to verify it passes**

Run: `node --test tests/transcription-bailian-provider.test.mjs`

Expected: PASS for helper behavior and source wiring assertions.

### Task 4: Switch runtime transcription behavior onto explicit Bailian provider

**Files:**
- Modify: `src/helpers/audioManager.js`

**Step 1: Write minimal implementation**

Update runtime logic so:
- `getAPIKey()` uses `bailianApiKey` when provider is `bailian`.
- `getTranscriptionModel()` defaults Bailian to `qwen3-asr-flash`.
- `getTranscriptionEndpoint()` resolves Bailian to DashScope base URL instead of `audio/transcriptions`.
- Qwen ASR chat-completions flow is enabled for explicit Bailian, not only `custom`.
- Provider auto-detection from matching base URLs uses provider defaults instead of hard-coded `whisper-1`.

**Step 2: Run test to verify it passes**

Run: `node --test tests/custom-api-settings-ui.test.mjs tests/transcription-bailian-provider.test.mjs`

Expected: PASS.

### Task 5: Fill i18n gaps and verify end-to-end

**Files:**
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

Add only the new translation keys needed for Bailian transcription help/model descriptions if existing keys cannot be reused cleanly.

**Step 2: Run verification**

Run:
- `node --test tests/custom-api-settings-ui.test.mjs tests/transcription-bailian-provider.test.mjs`
- `npm run typecheck`

Expected: all tests pass and TypeScript is clean.
