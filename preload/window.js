const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke, registerListener } = utils(ipcRenderer);

/**
 * Window control module
 * Handles window operations, hotkeys, and UI state
 */
module.exports = {
  // Window operations
  windowMinimize: invoke("window-minimize"),
  windowMaximize: invoke("window-maximize"),
  windowClose: invoke("window-close"),
  windowIsMaximized: invoke("window-is-maximized"),
  getPlatform: () => process.platform,
  getTargetAppInfo: invoke("get-target-app-info"),
  appQuit: invoke("app-quit"),
  cleanupApp: invoke("cleanup-app"),

  // Dictation control
  hideWindow: invoke("hide-window"),
  showDictationPanel: invoke("show-dictation-panel"),
  onToggleDictation: registerListener("toggle-dictation", (callback) => () => callback()),
  onStartDictation: registerListener("start-dictation", (callback) => () => callback()),
  onStopDictation: registerListener("stop-dictation", (callback) => () => callback()),
  onCancelDictation: registerListener(
    "cancel-dictation",
    (callback) => (_event, data) => callback(data)
  ),

  // Window drag and resize
  startWindowDrag: invoke("start-window-drag"),
  stopWindowDrag: invoke("stop-window-drag"),
  setMainWindowInteractivity: invoke("set-main-window-interactivity"),
  setDictationCancelEnabled: invoke("set-dictation-cancel-enabled"),
  resizeMainWindow: invoke("resize-main-window"),

  // Hotkey management
  updateHotkey: invoke("update-hotkey"),
  setHotkeyListeningMode: invoke("set-hotkey-listening-mode"),
  getHotkeyModeInfo: invoke("get-hotkey-mode-info"),
  notifyHotkeyChanged: (hotkey) => ipcRenderer.send("hotkey-changed", hotkey),

  // Hotkey events
  onHotkeyFallbackUsed: (callback) => {
    const listener = (_event, data) => callback?.(data);
    ipcRenderer.on("hotkey-fallback-used", listener);
    return () => ipcRenderer.removeListener("hotkey-fallback-used", listener);
  },
  onHotkeyRegistrationFailed: (callback) => {
    const listener = (_event, data) => callback?.(data);
    ipcRenderer.on("hotkey-registration-failed", listener);
    return () => ipcRenderer.removeListener("hotkey-registration-failed", listener);
  },
  onWindowsPushToTalkUnavailable: registerListener("windows-ptt-unavailable"),

  // Globe key listener (macOS only)
  onGlobeKeyPressed: (callback) => {
    const listener = () => callback?.();
    ipcRenderer.on("globe-key-pressed", listener);
    return () => ipcRenderer.removeListener("globe-key-pressed", listener);
  },
  onGlobeKeyReleased: (callback) => {
    const listener = () => callback?.();
    ipcRenderer.on("globe-key-released", listener);
    return () => ipcRenderer.removeListener("globe-key-released", listener);
  },

  // Audio events
  onNoAudioDetected: registerListener("no-audio-detected"),

  // Auto-start
  getAutoStartEnabled: invoke("get-auto-start-enabled"),
  setAutoStartEnabled: invoke("set-auto-start-enabled"),
};
