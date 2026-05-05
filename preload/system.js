const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke, registerListener } = utils(ipcRenderer);

/**
 * System module
 * Handles clipboard, permissions, settings, logging, and external links
 *
 * SECURITY: All cloud API calls are proxied through the main process.
 * The renderer never sees raw API keys. Keys are stored in the OS keychain
 * and injected into requests by the main process.
 */
module.exports = {
  // Clipboard
  checkAccessibilityPermission: invoke("check-accessibility-permission"),
  resetAccessibilityPermissions: invoke("reset-accessibility-permissions"),
  readClipboard: invoke("read-clipboard"),
  writeClipboard: invoke("write-clipboard"),
  checkPasteTools: invoke("check-paste-tools"),
  pasteText: invoke("paste-text"),

  // System settings
  requestMicrophoneAccess: invoke("request-microphone-access"),
  openMicrophoneSettings: invoke("open-microphone-settings"),
  openSoundInputSettings: invoke("open-sound-input-settings"),
  openAccessibilitySettings: invoke("open-accessibility-settings"),
  openWhisperModelsFolder: invoke("open-whisper-models-folder"),
  openExternal: invoke("open-external"),

  // UI language
  getUiLanguage: invoke("get-ui-language"),
  saveUiLanguage: invoke("save-ui-language"),
  setUiLanguage: invoke("set-ui-language"),

  // Logging
  getLogLevel: invoke("get-log-level"),
  log: invoke("app-log"),
  getDebugState: invoke("get-debug-state"),
  setDebugLogging: invoke("set-debug-logging"),
  openLogsFolder: invoke("open-logs-folder"),

  // Auth
  authClearSession: invoke("auth-clear-session"),

  // Cloud API — SECURITY: main-process proxy, no raw key exposure
  cloudTranscribe: invoke("cloud-transcribe"),
  cloudReason: invoke("cloud-reason"),
  cloudStreamingUsage: invoke("cloud-streaming-usage"),
  getSttConfig: invoke("get-stt-config"),

  // Referral
  getReferralStats: invoke("get-referral-stats"),
  sendReferralInvite: invoke("send-referral-invite"),
  getReferralInvites: invoke("get-referral-invites"),

  // Updates
  getAppVersion: invoke("get-app-version"),
  checkForUpdates: invoke("check-for-updates"),
  getUpdateStatus: invoke("get-update-status"),
  installUpdate: invoke("install-update"),
  onUpdateStatusChanged: registerListener(
    "update-status-changed",
    (callback) => (_event, data) => callback(data)
  ),

  // Runtime config
  getRuntimeConfig: invoke("get-runtime-config"),
  proxyRuntimeApiRequest: invoke("proxy-runtime-api-request"),

  // Reasoning
  processLocalReasoning: invoke("process-local-reasoning"),
  checkLocalReasoningAvailable: invoke("check-local-reasoning-available"),
  processAnthropicReasoning: invoke("process-anthropic-reasoning"),
  processCloudReasoningRequest: invoke("process-cloud-reasoning-request"),

  // Proxy transcription
  proxyMistralTranscription: invoke("proxy-mistral-transcription"),
  proxySonioxTranscription: invoke("proxy-soniox-transcription"),
};
