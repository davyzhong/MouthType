const utils = require("./utils");
const { ipcRenderer } = require("electron");
const { invoke, send, registerListener } = utils(ipcRenderer);

/**
 * Streaming ASR module
 * Handles all real-time transcription providers
 */
module.exports = {
  // Assembly AI Streaming
  assemblyAiStreamingWarmup: invoke("assemblyai-streaming-warmup"),
  assemblyAiStreamingStart: invoke("assemblyai-streaming-start"),
  assemblyAiStreamingSend: send("assemblyai-streaming-send"),
  assemblyAiStreamingForceEndpoint: send("assemblyai-streaming-force-endpoint"),
  assemblyAiStreamingStop: invoke("assemblyai-streaming-stop"),
  assemblyAiStreamingStatus: invoke("assemblyai-streaming-status"),
  onAssemblyAiPartialTranscript: registerListener(
    "assemblyai-partial-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onAssemblyAiFinalTranscript: registerListener(
    "assemblyai-final-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onAssemblyAiError: registerListener(
    "assemblyai-error",
    (callback) => (_event, error) => callback(error)
  ),
  onAssemblyAiSessionEnd: registerListener(
    "assemblyai-session-end",
    (callback) => (_event, data) => callback(data)
  ),

  // Soniox Streaming
  sonioxStreamingWarmup: invoke("soniox-streaming-warmup"),
  sonioxStreamingStart: invoke("soniox-streaming-start"),
  sonioxStreamingSend: send("soniox-streaming-send"),
  sonioxStreamingFinalize: send("soniox-streaming-finalize"),
  sonioxStreamingStop: invoke("soniox-streaming-stop"),
  sonioxStreamingStatus: invoke("soniox-streaming-status"),
  onSonioxPartialTranscript: registerListener(
    "soniox-partial-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onSonioxFinalTranscript: registerListener(
    "soniox-final-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onSonioxError: registerListener(
    "soniox-error",
    (callback) => (_event, error) => callback(error)
  ),
  onSonioxSessionEnd: registerListener(
    "soniox-session-end",
    (callback) => (_event, data) => callback(data)
  ),

  // Bailian Realtime Streaming
  bailianRealtimeWarmup: invoke("bailian-realtime-warmup"),
  bailianRealtimeStart: invoke("bailian-realtime-start"),
  bailianRealtimeSend: send("bailian-realtime-send"),
  bailianRealtimeFinalize: send("bailian-realtime-finalize"),
  bailianRealtimeStop: invoke("bailian-realtime-stop"),
  bailianRealtimeStatus: invoke("bailian-realtime-status"),
  onBailianRealtimePartialTranscript: registerListener(
    "bailian-realtime-partial-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onBailianRealtimeFinalTranscript: registerListener(
    "bailian-realtime-final-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onBailianRealtimeError: registerListener(
    "bailian-realtime-error",
    (callback) => (_event, error) => callback(error)
  ),
  onBailianRealtimeSpeechStarted: registerListener(
    "bailian-realtime-speech-started",
    (callback) => (_event, data) => callback(data)
  ),
  onBailianRealtimeSessionEnd: registerListener(
    "bailian-realtime-session-end",
    (callback) => (_event, data) => callback(data)
  ),

  // Deepgram Streaming
  deepgramStreamingWarmup: invoke("deepgram-streaming-warmup"),
  deepgramStreamingStart: invoke("deepgram-streaming-start"),
  deepgramStreamingSend: send("deepgram-streaming-send"),
  deepgramStreamingFinalize: send("deepgram-streaming-finalize"),
  deepgramStreamingStop: invoke("deepgram-streaming-stop"),
  deepgramStreamingStatus: invoke("deepgram-streaming-status"),
  onDeepgramPartialTranscript: registerListener(
    "deepgram-partial-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onDeepgramFinalTranscript: registerListener(
    "deepgram-final-transcript",
    (callback) => (_event, text) => callback(text)
  ),
  onDeepgramError: registerListener(
    "deepgram-error",
    (callback) => (_event, error) => callback(error)
  ),
  onDeepgramSessionEnd: registerListener(
    "deepgram-session-end",
    (callback) => (_event, data) => callback(data)
  ),
};
