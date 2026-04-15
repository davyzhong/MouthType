# Remove Updater And Usage Sharing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove application update detection/install flows and remove the privacy usage-sharing toggle so Mouthpiece no longer checks the original upstream project for releases or exposes usage analytics sharing in settings.

**Architecture:** Remove the updater as a full stack concern: main process wiring, IPC surface, preload bridge, renderer hooks, UI entry points, and build packaging references. Remove the usage-sharing toggle from persisted settings and settings UI while preserving unrelated privacy controls such as cloud backup and permissions.

**Tech Stack:** Electron, React 19, TypeScript, Zustand, react-i18next, node:test

---

### Task 1: Add regression tests for removed functionality

**Files:**
- Create: `tests/update-removal.test.mjs`

**Step 1: Write the failing test**

Add node tests that assert:
- `main.js`, `preload.js`, `src/helpers/ipcHandlers.js`, `src/components/ControlPanel.tsx`, and `src/components/SettingsPage.tsx` no longer reference updater wiring
- `package.json` no longer depends on `electron-updater`
- `electron-builder.json` no longer packages `src/updater.js`
- `src/components/SettingsPage.tsx`, `src/hooks/useSettings.ts`, and `src/stores/settingsStore.ts` no longer expose usage analytics / telemetry settings

**Step 2: Run test to verify it fails**

Run: `node --test tests/update-removal.test.mjs`
Expected: FAIL because updater and telemetry code still exists

**Step 3: Write minimal implementation**

No implementation in this task.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `node --test tests/update-removal.test.mjs`
Expected: FAIL on updater and telemetry references

### Task 2: Remove updater backend and packaging

**Files:**
- Modify: `main.js`
- Modify: `preload.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/types/electron.ts`
- Modify: `package.json`
- Modify: `electron-builder.json`
- Delete: `src/updater.js`

**Step 1: Remove updater manager wiring from main process**

Delete `UpdateManager` import, instance creation, window registration, startup checks, and cleanup in `main.js`.

**Step 2: Remove updater IPC endpoints and preload bridge**

Delete updater invoke handlers and listener registrations from `src/helpers/ipcHandlers.js` and `preload.js`.

**Step 3: Remove updater types and packaging references**

Remove update-related Electron API types from `src/types/electron.ts`, delete `electron-updater` from `package.json`, and remove `src/updater.js` from `electron-builder.json`.

**Step 4: Delete obsolete updater module**

Remove `src/updater.js`.

### Task 3: Remove renderer update UI and usage-sharing settings

**Files:**
- Modify: `src/components/ControlPanel.tsx`
- Modify: `src/components/SettingsPage.tsx`
- Delete: `src/hooks/useUpdater.ts`
- Modify: `src/hooks/useSettings.ts`
- Modify: `src/stores/settingsStore.ts`

**Step 1: Remove updater hook consumers**

Delete update button/toast logic from `src/components/ControlPanel.tsx`, remove update section logic from `src/components/SettingsPage.tsx`, and delete the now-unused `src/hooks/useUpdater.ts`.

**Step 2: Preserve version visibility without update actions**

Replace updater-based version loading with a direct `getAppVersion` preload call in `src/components/SettingsPage.tsx`.

**Step 3: Remove telemetry storage and UI**

Delete `telemetryEnabled` from store state, hook exports, and privacy section UI while preserving cloud backup and permissions.

### Task 4: Update visible copy and verify

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

**Step 1: Adjust visible section descriptions**

Update the settings modal section descriptions so they no longer mention analytics or updates.

**Step 2: Remove obsolete privacy usage analytics copy if no longer referenced**

Delete or stop exposing the usage analytics strings in translation files as appropriate.

**Step 3: Run verification**

Run:
- `node --test tests/update-removal.test.mjs`
- `node --test tests/automatic-activation-mode.test.mjs`
- `npm run typecheck`
- `npm run i18n:check`

Expected:
- Regression tests PASS
- Existing related smoke test PASS
- TypeScript check passes
- i18n check passes
