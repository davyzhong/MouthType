# Deepgram Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Deepgram as a first-class transcription provider with both batch and realtime modes, plus a provider-level toggle for realtime streaming.

**Architecture:** Reuse the existing cloud transcription settings and picker flow so Deepgram behaves like OpenAI, Groq, Mistral, and Bailian. Batch transcription will call Deepgram's pre-recorded `/v1/listen` endpoint directly, while realtime transcription will reuse the existing Deepgram streaming helper after teaching the IPC path to authenticate with either a Mouthpiece Cloud temporary token or a user-provided Deepgram API key.

**Tech Stack:** Electron IPC, React, Zustand, TypeScript, node:test, Deepgram Speech-to-Text HTTP and WebSocket APIs

---

### Task 1: Lock the behavior with failing tests

**Files:**
- Create: `tests/transcription-deepgram-provider.test.mjs`
- Modify: `tests/custom-api-settings-ui.test.mjs`

**Step 1: Write the failing tests**

Add tests that assert:
- Deepgram is exposed as a first-class transcription provider in the registry and picker tabs.
- Deepgram has its own API key wiring and realtime toggle in the settings UI.
- Settings store and settings hook expose `deepgramApiKey` and `deepgramStreamingEnabled`.
- Audio manager includes Deepgram-specific provider handling for API key lookup, default model, endpoint resolution, and streaming enablement.

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL because Deepgram provider wiring does not exist yet.

**Step 3: Write minimal implementation**

Do not touch production code yet beyond what is required for the failing assertions to make sense.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL with missing Deepgram provider or missing Deepgram setting references.

### Task 2: Add settings and persistence wiring

**Files:**
- Modify: `src/stores/settingsStore.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/helpers/environment.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`
- Modify: `src/utils/byokDetection.ts`

**Step 1: Write the failing test**

Extend the Deepgram test coverage to assert that:
- `DEEPGRAM_API_KEY` is persisted in the environment manager.
- preload and window typings expose Deepgram get/save key functions.
- the settings store initializes and updates the new Deepgram key and realtime toggle.

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: FAIL because the new key and toggle do not exist.

**Step 3: Write minimal implementation**

Add:
- `deepgramApiKey`
- `deepgramStreamingEnabled`
- getter/setter plumbing in store, hook, env manager, preload, and Electron types
- BYOK detection support for the Deepgram key

**Step 4: Run test to verify it passes**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: PASS for settings and persistence assertions.

### Task 3: Add Deepgram provider and UI controls

**Files:**
- Modify: `src/models/modelRegistryData.json`
- Modify: `src/components/TranscriptionModelPicker.tsx`
- Modify: `src/components/SettingsPage.tsx`

**Step 1: Write the failing test**

Add assertions that:
- Deepgram appears in transcription provider tabs.
- Deepgram model options exist.
- Selecting Deepgram shows a dedicated API key section and a realtime toggle.
- Settings page passes the Deepgram props through to the picker.

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL because the UI does not render the new provider-specific controls.

**Step 3: Write minimal implementation**

Expose a curated Deepgram model list with `nova-3` as the default, then add the provider tab, API key input, and realtime toggle UI.

**Step 4: Run test to verify it passes**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: PASS for Deepgram picker and settings wiring.

### Task 4: Implement Deepgram batch transcription

**Files:**
- Modify: `src/helpers/audioManager.js`

**Step 1: Write the failing test**

Add assertions that Deepgram:
- resolves its own API key source
- uses `nova-3` as the default model
- resolves the Deepgram `/v1/listen` endpoint
- parses transcript data from `results.channels[0].alternatives[0].transcript`

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: FAIL because the audio manager does not handle Deepgram batch requests.

**Step 3: Write minimal implementation**

Implement a Deepgram-specific request branch in the cloud transcription path using:
- `Authorization: Token <api key>`
- binary audio body
- query params for `model`, `smart_format`, optional `language`, and optional vocabulary hints

**Step 4: Run test to verify it passes**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: PASS for Deepgram batch routing assertions.

### Task 5: Implement BYOK realtime streaming

**Files:**
- Modify: `src/helpers/deepgramStreaming.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/types/electron.ts`

**Step 1: Write the failing test**

Add assertions that:
- Deepgram streaming supports user API key auth in addition to temporary tokens.
- `shouldUseStreaming()` allows Deepgram BYOK streaming when the new toggle is enabled.
- streaming stop/finalization does not require Mouthpiece Cloud reasoning or usage reporting for BYOK Deepgram.

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: FAIL because streaming is currently restricted to signed-in Mouthpiece Cloud mode.

**Step 3: Write minimal implementation**

Update the streaming stack so:
- IPC accepts either `authMode: "token"` or `authMode: "apiKey"`
- Deepgram streaming uses `Authorization: Token ...` for BYOK API keys and `Bearer ...` for temporary tokens
- audio manager chooses streaming for Deepgram only when the provider is Deepgram and the realtime toggle is enabled
- BYOK realtime completion flows through normal transcription post-processing instead of Mouthpiece Cloud usage/reasoning APIs

**Step 4: Run test to verify it passes**

Run: `node --test tests/transcription-deepgram-provider.test.mjs`

Expected: PASS for Deepgram realtime routing assertions.

### Task 6: Add locale strings and verify end-to-end

**Files:**
- Modify: `src/locales/en/translation.json`
- Modify: `src/locales/de/translation.json`
- Modify: `src/locales/es/translation.json`
- Modify: `src/locales/fr/translation.json`
- Modify: `src/locales/it/translation.json`
- Modify: `src/locales/ja/translation.json`
- Modify: `src/locales/pt/translation.json`
- Modify: `src/locales/ru/translation.json`
- Modify: `src/locales/zh-CN/translation.json`
- Modify: `src/locales/zh-TW/translation.json`

**Step 1: Write the failing test**

Add locale assertions for the new Deepgram-specific labels and toggle copy.

**Step 2: Run test to verify it fails**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL because the new translation keys are missing.

**Step 3: Write minimal implementation**

Add the new translation keys to every locale file.

**Step 4: Run test to verify it passes**

Run: `node --test tests/transcription-deepgram-provider.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: PASS.

**Step 5: Run the full verification suite**

Run: `node --test tests/*.mjs`

Expected: all tests pass.
