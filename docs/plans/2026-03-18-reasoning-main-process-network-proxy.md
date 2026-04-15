# Reasoning Main-Process Network Proxy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move cloud reasoning HTTP requests off the renderer and through a main-process IPC proxy without breaking existing provider behavior.

**Architecture:** Keep provider selection, prompt construction, endpoint fallback, and response parsing in `ReasoningService`, but route the actual network fetch through a new preload-exposed IPC method when running in Electron. Preserve the current direct `fetch` fallback for tests and non-Electron environments so existing browser-bundled tests stay lightweight.

**Tech Stack:** Electron IPC, Node fetch in main process, TypeScript service layer, source-assertion tests, node test runner

---

### Task 1: Guardrails for the new proxy

**Files:**
- Modify: `tests/repo-reality-alignment.test.mjs`
- Modify: `tests/custom-reasoning-availability.test.mjs`

**Step 1: Write the failing tests**

Add source assertions that:
- `preload.js` exposes a `processCloudReasoningRequest` bridge
- `ipcHandlers.js` registers a `process-cloud-reasoning-request` handler
- `ReasoningService.ts` prefers the IPC proxy before falling back to direct `fetch`

Add a behavior test that:
- injects `window.electronAPI.processCloudReasoningRequest`
- confirms custom reasoning uses the IPC proxy and does not hit global `fetch`

**Step 2: Run the targeted tests to verify they fail**

Run: `node --test tests/repo-reality-alignment.test.mjs tests/custom-reasoning-availability.test.mjs`

Expected: FAIL because the bridge and handler do not exist yet.

### Task 2: Add the main-process proxy

**Files:**
- Modify: `src/helpers/ipcHandlers.js`
- Modify: `preload.js`
- Modify: `src/types/electron.ts`

**Step 1: Add a new IPC handler**

Implement `process-cloud-reasoning-request` in `ipcHandlers.js` that:
- accepts `endpoint`, `method`, `headers`, `body`, and `timeoutMs`
- performs the network request in the main process
- returns `{ ok, status, statusText, text, json }`
- safely serializes non-JSON error bodies

**Step 2: Expose the bridge**

Add `processCloudReasoningRequest` in `preload.js` and the matching type in `src/types/electron.ts`.

**Step 3: Run targeted tests**

Run: `node --test tests/repo-reality-alignment.test.mjs`

Expected: PASS for the new source assertions.

### Task 3: Route reasoning requests through the proxy

**Files:**
- Modify: `src/services/ReasoningService.ts`
- Test: `tests/custom-reasoning-availability.test.mjs`

**Step 1: Add a request helper**

Create a helper in `ReasoningService.ts` that:
- uses `window.electronAPI.processCloudReasoningRequest` when available
- otherwise falls back to the existing renderer `fetch`
- preserves timeout semantics and response parsing

**Step 2: Reuse the helper**

Update OpenAI/custom/Bailian, Gemini, and Groq reasoning paths to use the helper instead of direct `fetch`.

**Step 3: Run targeted tests**

Run: `node --test tests/custom-reasoning-availability.test.mjs`

Expected: PASS, including the new “prefer IPC proxy” case.

### Task 4: Verify the slice

**Files:**
- No additional files unless fixes are needed

**Step 1: Run validation**

Run: `npm run typecheck`

Expected: PASS

**Step 2: Run lint**

Run: `npm run lint`

Expected: PASS

**Step 3: Run full tests**

Run: `node --test tests/*.mjs`

Expected: PASS
