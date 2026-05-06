const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke, registerListener } = utils(ipcRenderer);

/**
 * Database module
 * Handles transcription history and custom dictionary
 */
module.exports = {
  // Transcription CRUD
  saveTranscription: invoke("db-save-transcription"),
  getTranscriptions: invoke("db-get-transcriptions"),
  clearTranscriptions: invoke("db-clear-transcriptions"),
  deleteTranscription: invoke("db-delete-transcription"),

  // Dictionary
  getDictionary: invoke("db-get-dictionary"),
  setDictionary: invoke("db-set-dictionary"),
  onDictionaryUpdated: (callback) => {
    const listener = (_event, words) => callback?.(words);
    ipcRenderer.on("dictionary-updated", listener);
    return () => ipcRenderer.removeListener("dictionary-updated", listener);
  },

  // Auto-learn
  setAutoLearnEnabled: (enabled) => {
    ipcRenderer.send("auto-learn-changed", enabled);
  },
  onCorrectionsLearned: (callback) => {
    const listener = (_event, words) => callback?.(words);
    ipcRenderer.on("corrections-learned", listener);
    return () => ipcRenderer.removeListener("corrections-learned", listener);
  },
  undoLearnedCorrections: invoke("undo-learned-corrections"),

  // Transcription events
  onTranscriptionAdded: (callback) => {
    const listener = (_event, transcription) => callback?.(transcription);
    ipcRenderer.on("transcription-added", listener);
    return () => ipcRenderer.removeListener("transcription-added", listener);
  },
  onTranscriptionDeleted: (callback) => {
    const listener = (_event, data) => callback?.(data);
    ipcRenderer.on("transcription-deleted", listener);
    return () => ipcRenderer.removeListener("transcription-deleted", listener);
  },
  onTranscriptionsCleared: (callback) => {
    const listener = (_event, data) => callback?.(data);
    ipcRenderer.on("transcriptions-cleared", listener);
    return () => ipcRenderer.removeListener("transcriptions-cleared", listener);
  },
};
