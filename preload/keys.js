const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke } = utils(ipcRenderer);

/**
 * API Key management module
 * Handles all API key get/set operations
 *
 * SECURITY: This module only exposes key management to the main process.
 * Raw API keys are never sent to the renderer. All API calls are proxied
 * through the main process (see system.js cloudTranscribe/cloudReason).
 */
module.exports = {
  // OpenAI
  getOpenAIKey: invoke("get-openai-key"),
  saveOpenAIKey: invoke("save-openai-key"),
  createProductionEnvFile: invoke("create-production-env-file"),

  // Anthropic
  getAnthropicKey: invoke("get-anthropic-key"),
  saveAnthropicKey: invoke("save-anthropic-key"),

  // Gemini
  getGeminiKey: invoke("get-gemini-key"),
  saveGeminiKey: invoke("save-gemini-key"),

  // Groq
  getGroqKey: invoke("get-groq-key"),
  saveGroqKey: invoke("save-groq-key"),

  // Mistral
  getMistralKey: invoke("get-mistral-key"),
  saveMistralKey: invoke("save-mistral-key"),

  // Soniox
  getSonioxKey: invoke("get-soniox-key"),
  saveSonioxKey: invoke("save-soniox-key"),

  // Bailian
  getBailianKey: invoke("get-bailian-key"),
  saveBailianKey: invoke("save-bailian-key"),

  // Deepgram
  getDeepgramKey: invoke("get-deepgram-key"),
  saveDeepgramKey: invoke("save-deepgram-key"),

  // Custom endpoints
  getCustomTranscriptionKey: invoke("get-custom-transcription-key"),
  saveCustomTranscriptionKey: invoke("save-custom-transcription-key"),
  getCustomReasoningKey: invoke("get-custom-reasoning-key"),
  saveCustomReasoningKey: invoke("save-custom-reasoning-key"),

  // Dictation key persistence
  getDictationKey: invoke("get-dictation-key"),
  saveDictationKey: invoke("save-dictation-key"),

  // Bulk operations
  saveAllKeysToEnv: invoke("save-all-keys-to-env"),
  syncStartupPreferences: invoke("sync-startup-preferences"),
};
