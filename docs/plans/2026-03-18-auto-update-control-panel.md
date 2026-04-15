# Auto Update Control Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore packaged-app auto updates with startup checks, 12-hour polling, background downloads, and a control panel install prompt.

**Architecture:** Add a main-process update manager around `electron-updater`, expose its state through IPC/preload, and surface a left-sidebar action in the control panel only when an update is ready to install. Keep update checks silent and automatic; require explicit user confirmation before calling `quitAndInstall()`.

**Tech Stack:** Electron 36, electron-builder, electron-updater, React 19, TypeScript, react-i18next, node:test

---

### Task 1: Lock the desired updater behavior in tests

**Files:**
- Modify: `tests/update-removal.test.mjs`
- Create: `tests/update-manager.test.mjs`

**Step 1: Write the failing test**

Add assertions that:
- updater wiring is present in `main.js`, `preload.js`, `src/helpers/ipcHandlers.js`, and `src/components/ControlPanel.tsx`
- `package.json` includes `electron-updater`
- the control panel sidebar exposes an update action that waits for user confirmation before installation
- the update manager schedules a `12 * 60 * 60 * 1000` polling interval and performs an initial check

**Step 2: Run test to verify it fails**

Run: `node --test tests/update-removal.test.mjs tests/update-manager.test.mjs`
Expected: FAIL because updater code is not present yet

**Step 3: Write minimal implementation**

No implementation in this task.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `node --test tests/update-removal.test.mjs tests/update-manager.test.mjs`
Expected: FAIL on missing updater wiring

### Task 2: Reintroduce the main-process updater manager

**Files:**
- Create: `src/helpers/updateManager.js`
- Modify: `main.js`

**Step 1: Write the failing test**

Add a unit-style test for the update manager that instantiates it with a mocked updater and asserts:
- unsupported environments do not start polling
- supported packaged apps perform one immediate check
- the poll interval is set to 12 hours
- downloaded updates move state to an installable status

**Step 2: Run test to verify it fails**

Run: `node --test tests/update-manager.test.mjs`
Expected: FAIL because `src/helpers/updateManager.js` does not exist

**Step 3: Write minimal implementation**

Implement an `UpdateManager` class that:
- wraps `electron-updater`
- tracks updater state and metadata
- emits state changes back to the main process
- starts silent polling only for supported packaged targets
- disables automatic install-on-quit so installation always waits for explicit confirmation

**Step 4: Run test to verify it passes**

Run: `node --test tests/update-manager.test.mjs`
Expected: PASS

### Task 3: Add IPC and preload surface for updater state

**Files:**
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`

**Step 1: Write the failing test**

Extend the source assertions so they require:
- `get-update-status`
- `install-update`
- `onUpdateStatusChanged`

**Step 2: Run test to verify it fails**

Run: `node --test tests/update-removal.test.mjs`
Expected: FAIL because the IPC surface does not exist yet

**Step 3: Write minimal implementation**

Expose updater state through a small IPC API and broadcast update status changes to renderer windows.

**Step 4: Run test to verify it passes**

Run: `node --test tests/update-removal.test.mjs`
Expected: PASS

### Task 4: Add the control panel update action and confirmation flow

**Files:**
- Modify: `src/components/ControlPanel.tsx`
- Modify: `src/components/ControlPanelSidebar.tsx`

**Step 1: Write the failing test**

Add assertions that:
- the sidebar accepts update props
- the control panel loads updater status from `window.electronAPI`
- clicking the update action opens a confirm dialog before install

**Step 2: Run test to verify it fails**

Run: `node --test tests/update-removal.test.mjs`
Expected: FAIL because the renderer update flow does not exist yet

**Step 3: Write minimal implementation**

Use control panel state to:
- subscribe to update status events
- show a left-sidebar install action when an update is ready
- ask for confirmation before calling the install IPC action

**Step 4: Run test to verify it passes**

Run: `node --test tests/update-removal.test.mjs`
Expected: PASS

### Task 5: Update strings, dependency metadata, and verify

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
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

**Step 1: Write the failing test**

Require any new updater copy used by the control panel to exist in English and all supported locales.

**Step 2: Run test to verify it fails**

Run: `npm run i18n:check`
Expected: FAIL if any new keys are missing

**Step 3: Write minimal implementation**

Add `electron-updater` as an app dependency and fill in any missing update-related translation keys.

**Step 4: Run verification**

Run:
- `node --test tests/update-removal.test.mjs tests/update-manager.test.mjs`
- `npm run typecheck`
- `npm run i18n:check`

Expected:
- updater tests PASS
- TypeScript check passes
- i18n check passes
