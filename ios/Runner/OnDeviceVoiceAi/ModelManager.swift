import Foundation
import UIKit

#if canImport(LiteRTLM)
import LiteRTLM
#endif

/// Loads / unloads the local Gemma 3n `.litertlm` model via LiteRT-LM Swift API.
final class ModelManager {
  private(set) var backendName = "cpu"
  private(set) var modelLoadMs: Int?
  private(set) var lastInferenceMs: Int?
  private var inferenceDurations: [Int] = []

  #if canImport(LiteRTLM)
  private var engine: Engine?
  private var conversation: Conversation?
  #endif

  var isReady: Bool {
    #if canImport(LiteRTLM)
    return engine != nil && conversation != nil
    #else
    return false
    #endif
  }

  var averageInferenceMs: Int? {
    guard !inferenceDurations.isEmpty else { return nil }
    return inferenceDurations.reduce(0, +) / inferenceDurations.count
  }

  func checkCompatibility() -> [String: Any] {
    #if canImport(LiteRTLM)
    let supported = true
    let message = "Device supports on-device AI"
    #else
    let supported = false
    let message =
      "LiteRT-LM Swift package is not linked. Add https://github.com/google-ai-edge/LiteRT-LM via SPM."
    #endif
    return [
      "supported": supported,
      "message": message,
      "osVersion": UIDevice.current.systemVersion,
      "recommendedRamMb": 6144,
      "runtime": "LiteRT-LM",
    ]
  }

  func initialize(modelPath: String, preferredBackend: String, maxOutputTokens: Int) async throws {
    #if canImport(LiteRTLM)
    release()
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw ModelError.modelNotFound
    }

    let started = Date()
    let backend: Backend = preferredBackend.lowercased() == "cpu" ? .cpu : .gpu
    backendName = preferredBackend.lowercased() == "cpu" ? "cpu" : "gpu"

    let config = try EngineConfig(
      modelPath: modelPath,
      backend: backend,
      audioBackend: .cpu(),
      maxNumTokens: max(maxOutputTokens, 512),
      cacheDir: NSTemporaryDirectory()
    )
    let eng = Engine(engineConfig: config)
    try await eng.initialize()
    let conv = try eng.createConversation()
    engine = eng
    conversation = conv
    modelLoadMs = Int(Date().timeIntervalSince(started) * 1000)
    #else
    throw ModelError.runtimeUnavailable
    #endif
  }

  func transcribe(pcm: Data, prompt: String, onPartial: @escaping (String) -> Void) async throws -> String {
    #if canImport(LiteRTLM)
    guard let conversation else { throw ModelError.runtimeUnavailable }
    let started = Date()
    var assembled = ""

    // miniaudio requires WAV/FLAC/MP3 — wrap PCM16 mono in a WAV header.
    let wav = Self.pcm16MonoToWav(pcm, sampleRateHz: 16_000)

    let stream = try conversation.sendMessageAsync(
      contents: [
        .audioBytes(wav),
        .text(prompt),
      ]
    )
    for try await message in stream {
      let text = String(describing: message)
      if !text.isEmpty {
        assembled = text
        onPartial(assembled)
      }
    }

    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    lastInferenceMs = elapsed
    inferenceDurations.append(elapsed)
    return assembled.trimmingCharacters(in: .whitespacesAndNewlines)
    #else
    throw ModelError.runtimeUnavailable
    #endif
  }

  private static func pcm16MonoToWav(_ pcm: Data, sampleRateHz: Int) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRateHz) * UInt32(channels) * UInt32(bitsPerSample) / 8
    let blockAlign = channels * bitsPerSample / 8
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.append(UInt32(36 + pcm.count).littleEndianData)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    data.append(UInt32(16).littleEndianData)
    data.append(UInt16(1).littleEndianData)
    data.append(channels.littleEndianData)
    data.append(UInt32(sampleRateHz).littleEndianData)
    data.append(byteRate.littleEndianData)
    data.append(blockAlign.littleEndianData)
    data.append(bitsPerSample.littleEndianData)
    data.append(contentsOf: Array("data".utf8))
    data.append(UInt32(pcm.count).littleEndianData)
    data.append(pcm)
    return data
  }

  func release() {
    #if canImport(LiteRTLM)
    conversation = nil
    engine = nil
    #endif
  }
}

enum ModelError: LocalizedError {
  case modelNotFound
  case runtimeUnavailable
  case inferenceFailed
  case insufficientMemory

  var code: String {
    switch self {
    case .modelNotFound: return "MODEL_NOT_FOUND"
    case .runtimeUnavailable: return "RUNTIME_UNAVAILABLE"
    case .inferenceFailed: return "INFERENCE_FAILED"
    case .insufficientMemory: return "INSUFFICIENT_MEMORY"
    }
  }

  var errorDescription: String? {
    switch self {
    case .modelNotFound: return "On-device AI model is not ready."
    case .runtimeUnavailable: return "Native on-device AI runtime is unavailable."
    case .inferenceFailed: return "On-device inference failed."
    case .insufficientMemory: return "Not enough memory to run on-device AI."
    }
  }
}

private extension FixedWidthInteger {
  var littleEndianData: Data {
    var value = self.littleEndian
    return Data(bytes: &value, count: MemoryLayout<Self>.size)
  }
}
