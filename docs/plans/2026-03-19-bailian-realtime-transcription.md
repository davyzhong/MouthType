# Bailian Realtime Transcription Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a realtime transcription toggle inside the existing Alibaba Bailian provider UI so users can switch between batch `qwen3-asr-flash` and manual realtime `qwen3-asr-flash-realtime` without introducing a separate provider.

**Architecture:** Keep Bailian as a single provider in settings and UI, but split its runtime behavior into two paths. Batch transcription continues to use the existing DashScope-compatible HTTP path, while realtime mode uses a new WebSocket helper in the main process that speaks the official Qwen ASR Realtime protocol in Manual mode and feeds live text back into the existing streaming dictation pipeline.

**Tech Stack:** Electron, React 19, TypeScript, Zustand settings store, `ws`, react-i18next, existing AudioWorklet PCM streaming pipeline.

---

### Task 1: Add Bailian realtime settings and runtime model resolution

**Files:**
- Modify: `src/stores/settingsStore.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/types/electron.ts`

**Step 1: Add the new persisted toggle**

Add `bailianRealtimeEnabled` to the transcription settings/state shape alongside `deepgramStreamingEnabled` and `sonioxRealtimeEnabled`.

Required store work:
- Add the boolean key to the settings type and boolean key list.
- Read it from storage with a safe default of `false`.
- Expose `setBailianRealtimeEnabled`.
- Include it in `updateTranscriptionSettings`.

**Step 2: Thread the setting through hooks and component props**

Expose `bailianRealtimeEnabled` and `setBailianRealtimeEnabled` from `useSettings.ts` so `SettingsPage` can pass them into `TranscriptionModelPicker`.

**Step 3: Separate batch-model resolution from realtime-model resolution**

Do not overwrite the existing `cloudTranscriptionModel` value with the realtime model ID.

In `src/helpers/audioManager.js`, introduce explicit helpers:

```js
getBatchTranscriptionModel() {}
getRealtimeStreamingModel() {}
isByokBailianStreamingEnabled() {}
isByokStreamingEnabled() {}
```

Rules:
- Bailian batch mode always resolves to `qwen3-asr-flash` unless a valid future batch model is selected.
- Bailian realtime mode always resolves to `qwen3-asr-flash-realtime`.
- Existing Deepgram and Soniox behavior must remain unchanged.

**Step 4: Update runtime branching to use the new helpers**

Adjust:
- streaming-provider selection
- streaming option generation
- streaming usage reporting guardrails
- batch fallback selection

Expected behavior:
- Bailian realtime uses the realtime model only in the streaming path.
- Any batch fallback from realtime uses the batch model and the existing Bailian HTTP path.

**Step 5: Verify the settings surface compiles**

Run:

```bash
npm run typecheck
```

Expected:
- Passes without missing property/type errors for `bailianRealtimeEnabled`.

### Task 2: Add the Bailian realtime toggle to the existing provider capsule

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
- Modify: `src/locales/zh-CN/translation.json`
- Modify: `src/locales/zh-TW/translation.json`
- Modify: `src/locales/ja/translation.json`

**Step 1: Add the prop plumbing**

Update `SettingsPage` and `TranscriptionModelPicker` props so Bailian receives:

```ts
bailianRealtimeEnabled?: boolean;
setBailianRealtimeEnabled?: (enabled: boolean) => void;
```

**Step 2: Add the toggle block inside the existing Bailian section**

Mirror the existing Deepgram/Soniox card style instead of creating a new provider or new page section.

UI content:
- label: realtime transcription
- helper: explain that enabling it streams live text while speaking and uses the realtime model; disabling it uses standard batch ASR Flash after recording stops

**Step 3: Keep the model card UI stable**

Do not add a second Bailian model card for realtime in this first version.

The Bailian capsule should keep showing the existing provider/model area while the toggle controls whether runtime behavior is batch or realtime.

**Step 4: Add translations for all supported locales**

Add Bailian-specific keys under `transcription.bailian.*`, for example:

```json
"bailian": {
  "apiKeyHelp": "...",
  "realtimeLabel": "...",
  "realtimeEnabledDescription": "...",
  "realtimeDisabledDescription": "..."
}
```

Keep existing provider text intact.

**Step 5: Verify i18n coverage**

Run:

```bash
npm run i18n:check
```

Expected:
- No missing translation key failures.

### Task 3: Implement the Bailian realtime WebSocket client and IPC bridge

**Files:**
- Create: `src/helpers/qwenRealtimeStreaming.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`

**Step 1: Create a dedicated realtime helper in the main process**

Build a new class modeled after the existing realtime helpers, but tailored to Qwen ASR Realtime Manual mode.

Minimum public surface:

```js
warmup(options)
connect(options)
sendAudio(audioBuffer)
finalize()
disconnect()
getStatus()
```

Minimum callback surface:

```js
this.onPartialTranscript
this.onFinalTranscript
this.onError
this.onSessionEnd
```

**Step 2: Implement the official Qwen event flow in Manual mode**

Connection flow:
- open websocket with `wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime`
- send `Authorization: Bearer <bailian key>`
- wait for `session.created`
- send `session.update` with:
  - `input_audio_format: "pcm"`
  - `sample_rate: 16000`
  - optional language when not `auto`
  - `turn_detection: null`

Streaming flow:
- every PCM chunk is sent as `input_audio_buffer.append`
- `finalize()` sends `input_audio_buffer.commit`
- `disconnect()` sends `session.finish` and waits for `session.finished`

**Step 3: Map Qwen events onto the app’s existing realtime contract**

Event mapping:
- `conversation.item.input_audio_transcription.text` => partial preview should emit `text + stash`
- `conversation.item.input_audio_transcription.completed` => append finalized `transcript` to the accumulated final text and emit via `onFinalTranscript`
- `error` and `conversation.item.input_audio_transcription.failed` => normalize to readable app errors
- `session.finished` => resolve pending close and emit session-end payload

**Step 4: Add IPC methods and renderer bridge**

Add preload + main IPC endpoints matching the existing provider pattern:

```ts
bailianRealtimeWarmup
bailianRealtimeStart
bailianRealtimeSend
bailianRealtimeFinalize
bailianRealtimeStop
bailianRealtimeStatus
onBailianRealtimePartialTranscript
onBailianRealtimeFinalTranscript
onBailianRealtimeError
onBailianRealtimeSessionEnd
```

**Step 5: Keep region scope explicit**

First version assumption:
- use the China mainland websocket endpoint only
- align with the current Bailian provider’s existing China-mainland HTTP base configuration

Add a short code comment near the websocket URL noting that Singapore/international routing can be added later if provider-region settings are introduced.

**Step 6: Verify the helper compiles and the IPC surface is wired**

Run:

```bash
npm run lint
npm run typecheck
```

Expected:
- No missing preload/type/IPC references.

### Task 4: Plug Bailian realtime into the existing dictation streaming pipeline

**Files:**
- Modify: `src/helpers/audioManager.js`

**Step 1: Register Bailian in `STREAMING_PROVIDERS`**

Add a `bailian` entry that forwards to the new preload APIs.

**Step 2: Route provider selection correctly**

Update:
- `getStreamingProviderName()`
- `getStreamingProvider()`
- `getStreamingRequestOptions()`
- `runStreamingAction()`
- `shouldUseStreaming()`

Behavior target:
- Bailian realtime ON => uses streaming path
- Bailian realtime OFF => uses existing non-streaming batch path

**Step 3: Preserve low-latency live text feel**

Keep the existing renderer update contract:
- partial preview updates every realtime text event
- final commit updates only when Qwen emits completed transcript

This means `onPartialTranscript` receives `text + stash`, while `onStreamingCommit` continues to receive only newly finalized delta text.

**Step 4: Fix batch fallback and usage-reporting guards**

Adjust the stop/fallback path so that:
- Bailian realtime no-text fallback uses the existing Bailian batch HTTP transcription path
- BYOK Bailian realtime does not report Mouthpiece Cloud streaming usage

**Step 5: Verify end-to-end branch behavior**

Manual checks:
1. Bailian realtime OFF: start/stop recording and confirm batch transcription still works.
2. Bailian realtime ON: start recording, confirm the capsule shows live text while speaking, stop recording, confirm the final transcript settles cleanly.
3. Disconnect/error path: confirm the UI exits processing state and shows a readable error.

### Task 5: Final verification and cleanup

**Files:**
- Modify only as needed from prior tasks

**Step 1: Run the focused verification suite**

Run:

```bash
npm run typecheck
npm run lint
npm run i18n:check
```

If renderer-only verification is needed during iteration, also run:

```bash
npm run build:renderer
```

**Step 2: Smoke-check the worktree state**

Run:

```bash
git status --short
```

Expected:
- Only the intended implementation files are modified.

**Step 3: Commit in bilingual format once verified**

Use a bilingual plain-text commit message consistent with repository rules.
