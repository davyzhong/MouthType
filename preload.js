const { contextBridge, ipcRenderer } = require("electron");

// Import modular API sections
const keysAPI = require("./preload/keys");
const streamingAPI = require("./preload/streaming");
const modelsAPI = require("./preload/models");
const windowAPI = require("./preload/window");
const databaseAPI = require("./preload/database");
const systemAPI = require("./preload/system");

let runtimeConfig = {
  apiUrl: "",
  authUrl: "",
  enableMouthpieceCloud: false,
  oauthProtocol: "",
  oauthAuthBridgeUrl: "",
  oauthCallbackUrl: "",
};

try {
  runtimeConfig = {
    ...runtimeConfig,
    ...(ipcRenderer.sendSync("get-runtime-config-sync") || {}),
  };
} catch {
  // Leave empty defaults when the main-process runtime config is unavailable.
}

/**
 * Helper to register an IPC listener and return a cleanup function.
 * Ensures renderer code can easily remove listeners to avoid leaks.
 */
const registerListener = (channel, handlerFactory) => {
  return (callback) => {
    if (typeof callback !== "function") {
      return () => {};
    }

    const listener =
      typeof handlerFactory === "function"
        ? handlerFactory(callback)
        : (event, ...args) => callback(event, ...args);

    ipcRenderer.on(channel, listener);
    return () => {
      ipcRenderer.removeListener(channel, listener);
    };
  };
};

// Combine all API sections
contextBridge.exposeInMainWorld("electronAPI", {
  runtimeConfig,

  // Keys
  ...keysAPI,

  // Streaming
  ...streamingAPI,

  // Models
  ...modelsAPI,

  // Window
  ...windowAPI,

  // Database
  ...databaseAPI,

  // System
  ...systemAPI,
});
