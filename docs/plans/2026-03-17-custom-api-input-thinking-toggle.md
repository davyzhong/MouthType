# Custom API Input And Thinking Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make custom API key entry in transcription and intelligence settings save directly while typing, and add a custom reasoning `enable_thinking` toggle that users can control.

**Architecture:** Keep the existing settings store as the single source of truth. Add one opt-in immediate-save mode to the shared API key input component, wire it only into custom provider flows, and extend reasoning settings so the custom provider can persist and forward the `enable_thinking` flag into OpenAI-compatible chat-completions requests.

**Tech Stack:** React 19, TypeScript, Zustand, react-i18next, node:test, esbuild

---

### Task 1: Lock the behavior with failing tests

**Files:**
- Modify: `tests/custom-reasoning-availability.test.mjs`
- Create: `tests/custom-api-settings-ui.test.mjs`

**Step 1: Write the failing test**

Add one request-level test that expects custom reasoning to send `enable_thinking: true` when the new setting is enabled. Add one UI-source regression test that expects the custom transcription and custom reasoning sections to opt into immediate API key saving.

**Step 2: Run test to verify it fails**

Run: `node --test tests/custom-reasoning-availability.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL because the setting does not exist yet and the custom selectors do not pass an immediate-save prop.

**Step 3: Write minimal implementation**

Add only the code required to make those assertions true.

**Step 4: Run test to verify it passes**

Run: `node --test tests/custom-reasoning-availability.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: PASS

### Task 2: Extend settings state for custom reasoning thinking

**Files:**
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/stores/settingsStore.ts`

**Step 1: Write the failing test**

Use the request-level test from Task 1 to prove the missing setting is not currently available.

**Step 2: Run test to verify it fails**

Run: `node --test tests/custom-reasoning-availability.test.mjs`

Expected: FAIL on the missing `enable_thinking` behavior.

**Step 3: Write minimal implementation**

Add `customReasoningEnableThinking` to the reasoning settings contract, initialize it from localStorage, expose a setter, and include it in `updateReasoningSettings`.

**Step 4: Run test to verify it passes**

Run: `node --test tests/custom-reasoning-availability.test.mjs`

Expected: PASS for the new setting behavior.

### Task 3: Update the UI and request payload

**Files:**
- Modify: `src/components/ui/ApiKeyInput.tsx`
- Modify: `src/components/TranscriptionModelPicker.tsx`
- Modify: `src/components/ReasoningModelSelector.tsx`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/services/ReasoningService.ts`
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

Reuse the tests from Task 1 so the UI and request body expectations stay red until both are wired.

**Step 2: Run test to verify it fails**

Run: `node --test tests/custom-reasoning-availability.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: FAIL

**Step 3: Write minimal implementation**

Add an immediate-save mode to `ApiKeyInput`, enable it only for custom transcription and custom reasoning providers, add a toggle plus copy for the custom reasoning `enable_thinking` setting, and make custom chat-completions requests send the stored boolean instead of hard-coding `false` for Qwen models.

**Step 4: Run test to verify it passes**

Run: `node --test tests/custom-reasoning-availability.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: PASS

### Task 4: Verify the broader app still builds

**Files:**
- Modify: none unless verification reveals a gap

**Step 1: Run focused verification**

Run: `node --test tests/custom-reasoning-availability.test.mjs tests/custom-api-settings-ui.test.mjs`

Expected: PASS

**Step 2: Run broader safety checks**

Run: `npm run typecheck`

Expected: PASS

**Step 3: Optional UI smoke check**

Keep `npm run dev` running and confirm the settings UI renders the new custom API key fields and thinking toggle without runtime errors.
