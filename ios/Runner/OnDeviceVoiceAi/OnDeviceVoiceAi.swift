import AVFoundation
import Flutter
import Foundation
import UIKit

/// Flutter platform bridge for on-device voice AI on iOS.
final class OnDeviceVoiceAiPlugin: NSObject, FlutterStreamHandler {
  private static let methodChannelName = "com.example.gemma_poc/on_device_voice_ai/methods"
  private static let eventChannelName = "com.example.gemma_poc/on_device_voice_ai/events"

  private let modelManager = ModelManager()
  private var eventSink: FlutterEventSink?
  private var capture: AudioCapture?
  private var listening = false
  private var processingQueue = DispatchQueue(label: "on.device.voice.ai.infer")
  private var sampleRateHz = 16000
  private var chunkDurationMs = 3000
  private var transcriptionPrompt =
    "Transcribe the following speech exactly. Output only the spoken words."
  private var maxOutputTokens = 256
  private var backend = "gpu"
  private var modelPath: String?
  private var firstTranscriptMs: Int?
  private var listenStartedAt: Date?
  private var pendingChunks = [(Data, Int)]()
  private let chunkLock = NSLock()
  private var pumpTimer: Timer?
  private var methodChannel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let instance = OnDeviceVoiceAiPlugin()
    let methods = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    instance.methodChannel = methods
    methods.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    events.setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkCompatibility":
      result(modelManager.checkCompatibility())
    case "initialize":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "MODEL_NOT_FOUND", message: "On-device AI model is not ready.", details: nil))
        return
      }
      sampleRateHz = args["sampleRateHz"] as? Int ?? 16000
      chunkDurationMs = args["chunkDurationMs"] as? Int ?? 3000
      transcriptionPrompt = args["transcriptionPrompt"] as? String ?? transcriptionPrompt
      maxOutputTokens = args["maxOutputTokens"] as? Int ?? 256
      backend = args["backend"] as? String ?? "gpu"
      modelPath = args["modelPath"] as? String
      guard let path = modelPath, !path.isEmpty else {
        result(FlutterError(code: "MODEL_NOT_FOUND", message: "On-device AI model is not ready.", details: nil))
        return
      }
      emitState("modelLoading")
      Task {
        do {
          try await modelManager.initialize(
            modelPath: path,
            preferredBackend: backend,
            maxOutputTokens: maxOutputTokens
          )
          emitState("modelReady")
          DispatchQueue.main.async { result(nil) }
        } catch let error as ModelError {
          emitError(error.code, error.localizedDescription)
          DispatchQueue.main.async {
            result(FlutterError(code: error.code, message: error.localizedDescription, details: nil))
          }
        } catch {
          emitError("MODEL_LOAD_FAILED", "Model loading failed.")
          DispatchQueue.main.async {
            result(
              FlutterError(code: "MODEL_LOAD_FAILED", message: "Model loading failed.", details: nil)
            )
          }
        }
      }
    case "prepareModel":
      guard let args = call.arguments as? [String: Any],
            let urlString = args["downloadUrl"] as? String,
            let url = URL(string: urlString)
      else {
        result(FlutterError(code: "MODEL_NOT_FOUND", message: "On-device AI model is not ready.", details: nil))
        return
      }
      let token = args["authToken"] as? String
      let fileName = args["fileName"] as? String ?? "gemma-3n-E2B-it-int4.litertlm"
      emitState("modelDownloading")
      downloadModel(url: url, token: token, fileName: fileName, result: result)
    case "startListening":
      startListening(result: result)
    case "stopListening":
      stopListening()
      emitState("completed")
      result(nil)
    case "unloadModel":
      stopListening()
      modelManager.release()
      emitState("uninitialized")
      result(nil)
    case "getBenchmarkMetrics":
      result(benchmarkMap())
    case "dispose":
      stopListening()
      modelManager.release()
      emitState("disposed")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startListening(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    switch session.recordPermission {
    case .granted:
      beginCapture(result: result)
    case .denied:
      emitError("PERMISSION_DENIED", "Microphone permission is required.")
      result(
        FlutterError(
          code: "PERMISSION_DENIED",
          message: "Microphone permission is required.",
          details: nil
        )
      )
    case .undetermined:
      emitState("requestingPermission")
      session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.beginCapture(result: result)
          } else {
            self?.emitError("PERMISSION_DENIED", "Microphone permission is required.")
            result(
              FlutterError(
                code: "PERMISSION_DENIED",
                message: "Microphone permission is required.",
                details: nil
              )
            )
          }
        }
      }
    @unknown default:
      result(FlutterError(code: "MIC_UNAVAILABLE", message: "Microphone is unavailable.", details: nil))
    }
  }

  private func beginCapture(result: @escaping FlutterResult) {
    guard modelManager.isReady else {
      result(
        FlutterError(code: "MODEL_NOT_FOUND", message: "On-device AI model is not ready.", details: nil)
      )
      return
    }
    listening = true
    firstTranscriptMs = nil
    listenStartedAt = Date()
    chunkLock.lock()
    pendingChunks.removeAll()
    chunkLock.unlock()

    capture = AudioCapture(
      sampleRate: Double(sampleRateHz),
      chunkDurationMs: chunkDurationMs,
      onChunk: { [weak self] data, index in
        self?.enqueue(data, index: index)
      },
      onError: { [weak self] code, message in
        self?.emitError(code, message)
        self?.stopListening()
      }
    )
    capture?.start()
    emitState("listening")
    startPump()
    result(nil)
  }

  private func enqueue(_ data: Data, index: Int) {
    chunkLock.lock()
    pendingChunks.append((data, index))
    chunkLock.unlock()
  }

  private func startPump() {
    pumpTimer?.invalidate()
    pumpTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.pump()
    }
  }

  private func pump() {
    guard listening else { return }
    chunkLock.lock()
    guard !pendingChunks.isEmpty else {
      chunkLock.unlock()
      return
    }
    let item = pendingChunks.removeFirst()
    chunkLock.unlock()

    processingQueue.async { [weak self] in
      guard let self else { return }
      self.emitState("processing")
      let semaphore = DispatchSemaphore(value: 0)
      Task {
        do {
          let text = try await self.modelManager.transcribe(
            pcm: item.0,
            prompt: self.transcriptionPrompt
          ) { partial in
            self.emit(
              [
                "type": "partialTranscript",
                "text": partial,
                "chunkIndex": item.1,
                "isFinal": false,
              ]
            )
          }
          if self.firstTranscriptMs == nil, !text.isEmpty, let started = self.listenStartedAt {
            self.firstTranscriptMs = Int(Date().timeIntervalSince(started) * 1000)
          }
          if !text.isEmpty {
            self.emit(
              [
                "type": "finalTranscript",
                "text": text,
                "chunkIndex": item.1,
                "isFinal": true,
              ]
            )
          }
          if self.listening { self.emitState("listening") }
        } catch let error as ModelError {
          self.emitError(error.code, error.localizedDescription)
        } catch {
          self.emitError("INFERENCE_FAILED", "On-device inference failed.")
        }
        semaphore.signal()
      }
      _ = semaphore.wait(timeout: .now() + 120)
    }
  }

  private func stopListening() {
    listening = false
    pumpTimer?.invalidate()
    pumpTimer = nil
    capture?.stop()
    capture = nil
    chunkLock.lock()
    pendingChunks.removeAll()
    chunkLock.unlock()
  }

  private func downloadModel(
    url: URL,
    token: String?,
    fileName: String,
    result: @escaping FlutterResult
  ) {
    var request = URLRequest(url: url)
    request.setValue("gemma_poc-on-device-ai", forHTTPHeaderField: "User-Agent")
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("models", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let destination = dir.appendingPathComponent(fileName)

    let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
      if let error {
        self.emitError("MODEL_LOAD_FAILED", error.localizedDescription)
        DispatchQueue.main.async {
          result(FlutterError(code: "MODEL_LOAD_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        let message = (http.statusCode == 401 || http.statusCode == 403)
          ? "Model download requires Hugging Face access for the gated Gemma repo."
          : "Model download failed (HTTP \(http.statusCode))."
        self.emitError("MODEL_LOAD_FAILED", message)
        DispatchQueue.main.async {
          result(FlutterError(code: "MODEL_LOAD_FAILED", message: message, details: nil))
        }
        return
      }
      guard let tempURL else {
        self.emitError("MODEL_LOAD_FAILED", "Model download failed.")
        DispatchQueue.main.async {
          result(FlutterError(code: "MODEL_LOAD_FAILED", message: "Model download failed.", details: nil))
        }
        return
      }
      do {
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        self.modelPath = destination.path
        self.emit(["type": "downloadProgress", "progress": 1.0])
        self.emitState("modelReady")
        DispatchQueue.main.async { result(destination.path) }
      } catch {
        self.emitError("MODEL_LOAD_FAILED", "Model download failed.")
        DispatchQueue.main.async {
          result(FlutterError(code: "MODEL_LOAD_FAILED", message: "Model download failed.", details: nil))
        }
      }
    }

    // Basic progress via KVO observation of countOfBytesReceived when available.
    let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
      self.emit(["type": "downloadProgress", "progress": progress.fractionCompleted])
    }
    objc_setAssociatedObject(task, "progressObs", observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    task.resume()
  }

  private func benchmarkMap() -> [String: Any?] {
    [
      "modelId": "gemma-3n-E2B-it-int4",
      "backend": modelManager.backendName,
      "modelLoadMs": modelManager.modelLoadMs,
      "audioProcessingMs": modelManager.lastInferenceMs,
      "firstTranscriptMs": firstTranscriptMs,
      "averageInferenceMs": modelManager.averageInferenceMs,
      "ramMb": nil,
      "cpuPercent": nil,
      "chunkCount": modelManager.averageInferenceMs == nil ? 0 : 1,
    ]
  }

  private func emitState(_ state: String) {
    emit(["type": "state", "state": state])
  }

  private func emitError(_ code: String, _ message: String) {
    emit(["type": "error", "code": code, "message": message])
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async {
      self.eventSink?(event)
    }
  }
}
