import AVFoundation
import Foundation

/// Mono PCM16 capture at the configured sample rate. Emits fixed-duration chunks.
final class AudioCapture {
  private let sampleRate: Double
  private let chunkDurationMs: Int
  private let onChunk: (Data, Int) -> Void
  private let onError: (String, String) -> Void

  private let engine = AVAudioEngine()
  private var chunkIndex = 0
  private var buffer = Data()
  private var running = false

  init(
    sampleRate: Double,
    chunkDurationMs: Int,
    onChunk: @escaping (Data, Int) -> Void,
    onError: @escaping (String, String) -> Void
  ) {
    self.sampleRate = sampleRate
    self.chunkDurationMs = chunkDurationMs
    self.onChunk = onChunk
    self.onError = onError
  }

  func start() {
    if running { return }
    running = true
    chunkIndex = 0
    buffer.removeAll(keepingCapacity: true)

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: 1,
      interleaved: true
    ) else {
      onError("AUDIO_INIT_FAILED", "Audio initialization failed.")
      running = false
      return
    }

    let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    let bytesPerChunk = Int(sampleRate) * 2 * max(chunkDurationMs, 500) / 1000

    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      guard let self, self.running else { return }
      guard let converter else { return }

      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (self.sampleRate / inputFormat.sampleRate) + 32)
      guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

      var error: NSError?
      let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }
      converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
      if error != nil { return }
      guard let channel = pcmBuffer.int16ChannelData?[0] else { return }
      let byteCount = Int(pcmBuffer.frameLength) * MemoryLayout<Int16>.size
      let data = Data(bytes: channel, count: byteCount)
      self.buffer.append(data)

      while self.buffer.count >= bytesPerChunk {
        let chunk = self.buffer.prefix(bytesPerChunk)
        self.buffer.removeFirst(bytesPerChunk)
        let index = self.chunkIndex
        self.chunkIndex += 1
        self.onChunk(Data(chunk), index)
      }
    }

    do {
      try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.duckOthers])
      try AVAudioSession.sharedInstance().setActive(true)
      try engine.start()
    } catch {
      onError("AUDIO_INIT_FAILED", "Audio initialization failed.")
      stop()
    }
  }

  func stop() {
    running = false
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    if buffer.count > Int(sampleRate) / 5 {
      onChunk(buffer, chunkIndex)
      chunkIndex += 1
    }
    buffer.removeAll()
    try? AVAudioSession.sharedInstance().setActive(false)
  }
}
