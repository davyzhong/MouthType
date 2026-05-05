const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke, send, registerListener } = utils(ipcRenderer);

/**
 * Model management module
 * Handles local model downloads, checks, and deletion
 */
module.exports = {
  // Unified model management
  modelGetAll: invoke("model-get-all"),
  modelCheck: invoke("model-check"),
  modelDownload: invoke("model-download"),
  modelDelete: invoke("model-delete"),
  modelDeleteAll: invoke("model-delete-all"),
  modelCheckRuntime: invoke("model-check-runtime"),
  modelCancelDownload: invoke("model-cancel-download"),
  onModelDownloadProgress: registerListener("model-download-progress"),

  // Whisper-specific
  transcribeLocalWhisper: invoke("transcribe-local-whisper"),
  checkWhisperInstallation: invoke("check-whisper-installation"),
  downloadWhisperModel: invoke("download-whisper-model"),
  onWhisperDownloadProgress: registerListener("whisper-download-progress"),
  checkModelStatus: invoke("check-model-status"),
  listWhisperModels: invoke("list-whisper-models"),
  deleteWhisperModel: invoke("delete-whisper-model"),
  deleteAllWhisperModels: invoke("delete-all-whisper-models"),
  cancelWhisperDownload: invoke("cancel-whisper-download"),
  checkFFmpegAvailability: invoke("check-ffmpeg-availability"),
  getAudioDiagnostics: invoke("get-audio-diagnostics"),

  // Whisper server
  whisperServerStart: invoke("whisper-server-start"),
  whisperServerStop: invoke("whisper-server-stop"),
  whisperServerStatus: invoke("whisper-server-status"),

  // CUDA GPU acceleration
  detectGpu: invoke("detect-gpu"),
  getCudaWhisperStatus: invoke("get-cuda-whisper-status"),
  downloadCudaWhisperBinary: invoke("download-cuda-whisper-binary"),
  cancelCudaWhisperDownload: invoke("cancel-cuda-whisper-download"),
  deleteCudaWhisperBinary: invoke("delete-cuda-whisper-binary"),
  onCudaDownloadProgress: registerListener(
    "cuda-download-progress",
    (callback) => (_event, data) => callback(data)
  ),
  onCudaFallbackNotification: registerListener(
    "cuda-fallback-notification",
    (callback) => () => callback()
  ),

  // Parakeet (NVIDIA)
  transcribeLocalParakeet: invoke("transcribe-local-parakeet"),
  checkParakeetInstallation: invoke("check-parakeet-installation"),
  downloadParakeetModel: invoke("download-parakeet-model"),
  onParakeetDownloadProgress: registerListener("parakeet-download-progress"),
  checkParakeetModelStatus: invoke("check-parakeet-model-status"),
  listParakeetModels: invoke("list-parakeet-models"),
  deleteParakeetModel: invoke("delete-parakeet-model"),
  deleteAllParakeetModels: invoke("delete-all-parakeet-models"),
  cancelParakeetDownload: invoke("cancel-parakeet-download"),
  getParakeetDiagnostics: invoke("get-parakeet-diagnostics"),

  // Parakeet server
  parakeetServerStart: invoke("parakeet-server-start"),
  parakeetServerStop: invoke("parakeet-server-stop"),
  parakeetServerStatus: invoke("parakeet-server-status"),

  // llama.cpp
  llamaCppCheck: invoke("llama-cpp-check"),
  llamaCppInstall: invoke("llama-cpp-install"),
  llamaCppUninstall: invoke("llama-cpp-uninstall"),

  // llama-server
  llamaServerStart: invoke("llama-server-start"),
  llamaServerStop: invoke("llama-server-stop"),
  llamaServerStatus: invoke("llama-server-status"),
  llamaGpuReset: invoke("llama-gpu-reset"),

  // Vulkan GPU acceleration
  detectVulkanGpu: invoke("detect-vulkan-gpu"),
  getLlamaVulkanStatus: invoke("get-llama-vulkan-status"),
  downloadLlamaVulkanBinary: invoke("download-llama-vulkan-binary"),
  cancelLlamaVulkanDownload: invoke("cancel-llama-vulkan-download"),
  deleteLlamaVulkanBinary: invoke("delete-llama-vulkan-binary"),
  onLlamaVulkanDownloadProgress: registerListener(
    "llama-vulkan-download-progress",
    (callback) => (_event, data) => callback(data)
  ),
};
