/**
 * Preload utility factory — call with ipcRenderer to get bound helpers.
 *
 * @param {Electron.IpcRenderer} ipcRenderer
 * @returns {{invoke: Function, send: Function, registerListener: Function}}
 */
module.exports = (ipcRenderer) => {
  /**
   * Create a standard IPC invoke wrapper
   */
  const invoke = (channel) => (...args) => ipcRenderer.invoke(channel, ...args);

  /**
   * Create a standard IPC send wrapper
   */
  const send = (channel) => (...args) => ipcRenderer.send(channel, ...args);

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

  return { invoke, send, registerListener };
};
