# Repo Reality Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align Mouthpiece's real product behavior, branding, defaults, and docs so the repository stops advertising stale OpenWhispr-era assumptions and discontinued cloud paths.

**Architecture:** Use a compatibility-first cleanup. First, encode the intended posture in regression tests, then centralize brand/runtime flags, force deprecated cloud paths off by default, and reconcile onboarding, docs, locale metadata, and duplicate runtime modules without breaking existing user data or cache directories.

**Tech Stack:** Electron 36, React 19, TypeScript, JavaScript, Zustand, react-i18next, better-sqlite3, node:test

---

### Task 1: Lock the intended product posture in failing tests

**Files:**
- Create: `tests/repo-reality-alignment.test.mjs`

**Step 1: Write the failing test**

Add `node:test` assertions that encode the target state:
- discontinued Mouthpiece Cloud is not the default runtime mode anywhere
- onboarding does not hardcode the agent name string inline
- supported UI languages come from one exported source and match locale assets
- `llamaCppInstaller` no longer exists as both `.js` and `.ts`
- docs no longer claim an 8-step onboarding flow or the old rich transcription schema

Example assertions:

```js
test("cloud defaults no longer point at deprecated openwhispr mode", async () => {
  const source = await readRepoFile("src/stores/settingsStore.ts");
  assert.doesNotMatch(source, /cloudTranscriptionMode:\s*readString\([^)]*"openwhispr"/);
  assert.doesNotMatch(source, /cloudReasoningMode:\s*readString\([^)]*"openwhispr"/);
});

test("onboarding does not hardcode the Mouthpiece agent name", async () => {
  const source = await readRepoFile("src/components/OnboardingFlow.tsx");
  assert.doesNotMatch(source, /const agentName = "Mouthpiece"/);
});
```

**Step 2: Run test to verify it fails**

Run: `node --test tests/repo-reality-alignment.test.mjs`

Expected: FAIL on the deprecated cloud defaults, the hardcoded onboarding agent name, duplicated installer module, and stale docs.

**Step 3: Write minimal implementation**

No implementation in this task.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `node --test tests/repo-reality-alignment.test.mjs`

Expected: FAIL with only the newly added regression expectations.

### Task 2: Centralize brand and compatibility identifiers

**Files:**
- Create: `src/config/productIdentity.ts`
- Modify: `main.js`
- Modify: `src/main.jsx`
- Modify: `src/helpers/gnomeShortcut.js`
- Modify: `src/helpers/modelDirUtils.js`
- Modify: `src/helpers/modelManagerBridge.js`
- Modify: `src/helpers/ModelManager.ts`
- Modify: `src/utils.js`
- Modify: `cleanup.js`

**Step 1: Create a single product identity module**

Add constants for:
- user-facing brand name: `Mouthpiece`
- current protocol: `mouthpiece`
- legacy protocol aliases: `openwhispr`, `openwhispr-dev`, `openwhispr-staging`
- legacy cache/app-data identifiers that must remain readable
- current compatibility policy: preserve old storage locations until an explicit migration

Example shape:

```ts
export const PRODUCT_NAME = "Mouthpiece";
export const PRIMARY_PROTOCOL = "mouthpiece";
export const LEGACY_PROTOCOLS = ["openwhispr", "openwhispr-dev", "openwhispr-staging"];
export const LEGACY_CACHE_NAMESPACE = "openwhispr";
```

**Step 2: Replace scattered hardcoded identity strings**

Use the new constants instead of inline protocol and brand strings in:
- `main.js`
- `src/main.jsx`
- GNOME shortcut identifiers
- cache/model path helpers
- cleanup helpers

Do not rename cache roots or delete legacy lookup logic yet.

**Step 3: Preserve backward compatibility explicitly**

Keep:
- old user-data directory probing in `main.js`
- legacy cache folder names such as `~/.cache/openwhispr`
- legacy protocol handling for already-issued auth callbacks when safe

Do not silently move user files in this task.

**Step 4: Run focused verification**

Run:
- `node --test tests/repo-reality-alignment.test.mjs`
- `npm run typecheck`

Expected:
- identity-related expectations now pass
- no type regressions

### Task 3: Force deprecated Mouthpiece Cloud paths off by default

**Files:**
- Modify: `src/config/runtimeConfig.ts`
- Modify: `src/config/constants.ts`
- Modify: `src/stores/settingsStore.ts`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/components/ControlPanel.tsx`
- Modify: `src/components/HistoryView.tsx`
- Modify: `src/components/ui/PromptStudio.tsx`
- Modify: `src/helpers/audioManager.js`
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `src/hooks/useAuth.ts`
- Modify: `src/lib/neonAuth.ts`

**Step 1: Introduce an explicit runtime flag**

Add `enableMouthpieceCloud` to runtime config, defaulting to `false` unless explicitly enabled by environment.

Example:

```ts
enableMouthpieceCloud:
  (preloadConfig?.enableMouthpieceCloud ||
    env.VITE_ENABLE_MOUTHPIECE_CLOUD ||
    "") === "true",
```

**Step 2: Migrate persisted settings away from deprecated cloud modes**

In `src/stores/settingsStore.ts`:
- default transcription mode to `byok`
- default reasoning mode to `byok`
- if localStorage still says `openwhispr` while the flag is off, coerce to `byok`
- ensure selectors such as `selectIsCloudReasoningMode()` return `false` when the flag is off

**Step 3: Remove stale UI transitions and hidden dead branches**

Delete or neutralize:
- `pendingCloudMigration` logic in `ControlPanel.tsx`
- stale “cloud migration” banners in history if the service is gone
- PromptStudio options that still present `openwhispr` as live
- auth-dependent streaming warmup assumptions that require an unavailable cloud backend

**Step 4: Guard runtime cloud calls**

In `audioManager.js` and `ipcHandlers.js`, fail closed when deprecated cloud mode is disabled:
- no automatic selection of `openwhispr-cloud`
- no streaming warmup based solely on stale signed-in state
- clear user-facing error that cloud mode is unavailable and BYOK/local must be used

**Step 5: Run focused verification**

Run:
- `node --test tests/repo-reality-alignment.test.mjs`
- `node --test tests/*.test.mjs`
- `npm run typecheck`

Expected:
- deprecated cloud defaults and dead migration flows are gone
- existing dictation tests still pass

### Task 4: Reconcile agent-name behavior with the simplified onboarding flow

**Files:**
- Modify: `src/components/OnboardingFlow.tsx`
- Modify: `src/utils/agentName.ts`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/main.jsx`
- Modify: `src/config/prompts.ts`

**Step 1: Make settings the source of truth for the agent name**

Use `getAgentName()` / `useAgentName()` instead of a hardcoded onboarding constant.

In onboarding:
- seed from stored value or default helper
- do not overwrite a user-customized name with `"Mouthpiece"` on finish

**Step 2: Keep the onboarding simple**

Do not restore the old 8-step onboarding. Instead:
- keep the 3-step flow
- document that the default agent name is `Mouthpiece`
- allow editing later in Settings, which already exists

**Step 3: Ensure prompts and examples stay in sync**

All agent examples in settings and prompt templating should read from the same helper. No inline fallback strings should compete with `DEFAULT_AGENT_NAME`.

**Step 4: Run focused verification**

Run:
- `node --test tests/onboarding-setup.test.mjs tests/repo-reality-alignment.test.mjs`
- `npm run typecheck`

Expected:
- onboarding remains 3-step
- agent name no longer has split behavior between onboarding and settings

### Task 5: Reconcile docs with the real database and onboarding model

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `DEBUG.md`
- Modify: `LOCAL_WHISPER_SETUP.md`
- Modify: `TROUBLESHOOTING.md`
- Modify: `WINDOWS_TROUBLESHOOTING.md`

**Step 1: Update onboarding documentation**

Remove claims that:
- onboarding has 8 steps
- onboarding is where users currently name the agent

Replace with the real flow:
- authentication
- permissions
- activation
- agent name editable later in settings

**Step 2: Update the database schema documentation**

Replace stale schema examples with the actual current tables from `src/helpers/database.js`:

```sql
CREATE TABLE transcriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE custom_dictionary (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT NOT NULL UNIQUE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**Step 3: Call out compatibility behavior clearly**

Document that:
- legacy cache directories still use `openwhispr` naming
- this is intentional for upgrade compatibility
- the user-facing product name is still Mouthpiece

**Step 4: Run verification**

Run: `node --test tests/repo-reality-alignment.test.mjs`

Expected: docs-related expectations pass.

### Task 6: Create one source of truth for supported UI languages

**Files:**
- Create: `src/locales/localeManifest.ts`
- Modify: `src/i18n.ts`
- Modify: `src/helpers/i18nMain.js`
- Modify: `src/components/SettingsPage.tsx`
- Modify: `src/locales/translations.ts`
- Modify: `src/locales/prompts.ts`

**Step 1: Export a shared locale manifest**

Move the supported locale list and labels into one place, for example:

```ts
export const SUPPORTED_UI_LANGUAGES = [
  "en",
  "es",
  "fr",
  "de",
  "pt",
  "it",
  "ru",
  "ja",
  "zh-CN",
  "zh-TW",
] as const;
```

Include per-locale display metadata so settings does not maintain a second list manually.

**Step 2: Make renderer and main process consume the same manifest**

Use the shared manifest in:
- `src/i18n.ts`
- `src/helpers/i18nMain.js`
- settings language selector data

Avoid one file claiming 9 languages while another exports 10.

**Step 3: Add a consistency assertion**

In `tests/repo-reality-alignment.test.mjs`, assert that locale directories and exported language identifiers match.

**Step 4: Run verification**

Run:
- `node --test tests/repo-reality-alignment.test.mjs tests/default-ui-language.test.mjs`
- `npm run typecheck`
- `npm run i18n:check`

Expected:
- locale count and fallbacks stay synchronized
- i18n checks remain green

### Task 7: Remove the stale `llamaCppInstaller.ts` fork and keep one runtime path

**Files:**
- Delete: `src/helpers/llamaCppInstaller.ts`
- Modify: `src/helpers/llamaCppInstaller.js`
- Modify: `src/helpers/ModelManager.ts`
- Modify: `src/helpers/ipcHandlers.js`

**Step 1: Decide which implementation is canonical**

Keep `src/helpers/llamaCppInstaller.js` as the canonical runtime module because Node/Electron main-process `require("./llamaCppInstaller")` resolves to the JavaScript file today.

**Step 2: Port any still-needed behavior from the stale TypeScript fork**

If the `.ts` file contains logic worth keeping, move that logic into the `.js` file before deletion. Do not keep two divergent installers with different binary names and install stories.

**Step 3: Delete the duplicate file**

Remove `src/helpers/llamaCppInstaller.ts` once the runtime behavior is preserved in one place.

**Step 4: Run focused verification**

Run:
- `node --test tests/repo-reality-alignment.test.mjs`
- `npm run typecheck`

Expected:
- only one installer implementation remains
- runtime imports still resolve

### Task 8: Final regression pass and cleanup

**Files:**
- Modify: `tests/repo-reality-alignment.test.mjs`
- Modify: any touched files above

**Step 1: Run the full lightweight verification set**

Run:
- `node --test tests/*.test.mjs`
- `npm run typecheck`
- `npm run i18n:check`

Expected:
- all tests pass
- typecheck passes
- translations remain complete

**Step 2: Run renderer verification**

Run:
- `npm run build:renderer`

Expected:
- renderer builds cleanly after config and locale refactors

**Step 3: Commit in small slices**

Suggested commit boundaries:
- tests + product identity
- deprecated cloud shutdown
- onboarding/docs alignment
- locale manifest
- installer dedupe

Use bilingual commit messages per repository rules.
