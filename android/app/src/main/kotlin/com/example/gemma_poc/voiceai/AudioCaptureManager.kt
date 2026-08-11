package com.example.gemma_poc.voiceai

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Low-latency mono PCM16 capture. Emits fixed-duration chunks for Gemma 3n
 * clip inference (runtime does not expose continuous ASR streaming).
 */
class AudioCaptureManager(
    private val sampleRateHz: Int,
    private val chunkDurationMs: Int,
    private val onChunk: (ByteArray, Int) -> Unit,
    private val onError: (String, String) -> Unit,
) {
    private val running = AtomicBoolean(false)
    private var recordThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private var chunkIndex = 0

    fun start() {
        if (!running.compareAndSet(false, true)) return

        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRateHz,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer == AudioRecord.ERROR || minBuffer == AudioRecord.ERROR_BAD_VALUE) {
            running.set(false)
            onError("AUDIO_INIT_FAILED", "Audio initialization failed.")
            return
        }

        val bytesPerSecond = sampleRateHz * 2 // 16-bit mono
        val chunkBytes = (bytesPerSecond * (chunkDurationMs / 1000.0)).toInt()
            .coerceAtLeast(minBuffer)
        val bufferSize = maxOf(minBuffer * 2, chunkBytes)

        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRateHz,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        } catch (t: Throwable) {
            running.set(false)
            onError("MIC_UNAVAILABLE", "Microphone is unavailable.")
            return
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            running.set(false)
            onError("AUDIO_INIT_FAILED", "Audio initialization failed.")
            return
        }

        audioRecord = recorder
        chunkIndex = 0
        recorder.startRecording()

        recordThread = thread(name = "OnDeviceVoiceAi-Audio", isDaemon = true) {
            val chunk = ByteArray(chunkBytes)
            var offset = 0
            val readBuf = ByteArray(minBuffer)
            try {
                while (running.get()) {
                    val read = recorder.read(readBuf, 0, readBuf.size)
                    if (read <= 0) continue
                    var srcPos = 0
                    while (srcPos < read) {
                        val copy = minOf(read - srcPos, chunk.size - offset)
                        System.arraycopy(readBuf, srcPos, chunk, offset, copy)
                        offset += copy
                        srcPos += copy
                        if (offset >= chunk.size) {
                            val index = chunkIndex++
                            val payload = chunk.copyOf()
                            onChunk(payload, index)
                            offset = 0
                        }
                    }
                }
                // Flush remaining audio on stop if it contains signal.
                if (offset > bytesPerSecond / 10) {
                    val payload = chunk.copyOfRange(0, offset)
                    onChunk(payload, chunkIndex++)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Audio capture failed", t)
                onError("AUDIO_INIT_FAILED", "Audio initialization failed.")
            }
        }
    }

    fun stop() {
        running.set(false)
        try {
            recordThread?.join(1000)
        } catch (_: InterruptedException) {
        }
        recordThread = null
        try {
            audioRecord?.stop()
        } catch (_: Throwable) {
        }
        audioRecord?.release()
        audioRecord = null
    }

    companion object {
        private const val TAG = "AudioCaptureManager"
    }
}
