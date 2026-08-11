package com.example.gemma_poc.voiceai

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.SamplerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.sqrt

/**
 * LiteRT-LM wrapper tuned for MediaTek / mid-range stability:
 * - Prefer CPU + audioBackend CPU
 * - Use synchronous sendMessage only (async crashes on callback_thread on some SoCs)
 * - Recreate Engine after each audio turn (known sequential Conversation crash on Dimensity)
 */
class ModelInferenceEngine(
    private val context: Context,
) {
    private var engine: Engine? = null
    private var modelPath: String? = null
    private var preferredBackend: String = "cpu"
    private var maxNumTokens: Int = 2048

    var backendName: String = "cpu"
        private set
    var modelLoadMs: Long? = null
        private set
    var lastInferenceMs: Long? = null
        private set
    private val inferenceDurations = mutableListOf<Long>()

    val averageInferenceMs: Long?
        get() = if (inferenceDurations.isEmpty()) null
        else inferenceDurations.sum() / inferenceDurations.size

    val isReady: Boolean get() = engine != null && !modelPath.isNullOrBlank()

    suspend fun initialize(
        modelPath: String,
        preferredBackend: String,
        maxOutputTokens: Int,
    ) = withContext(Dispatchers.Default) {
        this@ModelInferenceEngine.modelPath = modelPath
        this@ModelInferenceEngine.preferredBackend = preferredBackend
        this@ModelInferenceEngine.maxNumTokens = maxOf(maxOutputTokens, 2048)
        loadEngine()
    }

    private fun loadEngine() {
        releaseInternal()
        val path = modelPath ?: throw ModelException("MODEL_NOT_FOUND", "On-device AI model is not ready.")
        val file = File(path)
        if (!file.exists() || file.length() < 1024L * 1024L) {
            throw ModelException("MODEL_NOT_FOUND", "On-device AI model is not ready.")
        }

        val backends = buildList {
            add(selectBackend(preferredBackend))
            add(Backend.CPU())
        }.distinctBy { it::class }

        var lastError: Throwable? = null
        for (backend in backends) {
            try {
                val started = System.nanoTime()
                val config = EngineConfig(
                    modelPath = path,
                    backend = backend,
                    audioBackend = Backend.CPU(),
                    cacheDir = context.cacheDir.path,
                    maxNumTokens = maxNumTokens,
                )
                val eng = Engine(config)
                eng.initialize()
                engine = eng
                backendName = when (backend) {
                    is Backend.GPU -> "gpu"
                    is Backend.NPU -> "npu"
                    else -> "cpu"
                }
                modelLoadMs = (System.nanoTime() - started) / 1_000_000
                Log.i(TAG, "Engine ready backend=$backendName loadMs=$modelLoadMs")
                return
            } catch (t: Throwable) {
                lastError = t
                Log.w(TAG, "Engine init failed for ${backend::class.simpleName}", t)
                releaseInternal()
            }
        }

        val message = lastError?.message.orEmpty().lowercase()
        when {
            lastError is OutOfMemoryError || message.contains("memory") ->
                throw ModelException("INSUFFICIENT_MEMORY", "Not enough memory to run on-device AI.")
            else ->
                throw ModelException("MODEL_LOAD_FAILED", "Model loading failed.")
        }
    }

    private fun selectBackend(preferred: String): Backend {
        return when (preferred.lowercase()) {
            "gpu" -> try {
                Backend.GPU()
            } catch (_: Throwable) {
                Backend.CPU()
            }
            else -> Backend.CPU()
        }
    }

    /**
     * One-shot transcription. Intentionally avoids sendMessageAsync (SIGSEGV on
     * MediaTek callback_thread) and avoids a second sendMessage on the same Conversation.
     */
    suspend fun transcribeUtterance(
        pcmBytes: ByteArray,
        prompt: String,
        sampleRateHz: Int = 16_000,
    ): String = withContext(Dispatchers.Default) {
        if (engine == null) loadEngine()
        val eng = engine
            ?: throw ModelException("RUNTIME_UNAVAILABLE", "Native on-device AI runtime is unavailable.")

        if (pcmBytes.size < sampleRateHz) {
            throw ModelException("INFERENCE_FAILED", "Recording too short. Speak for a few seconds, then stop.")
        }
        if (rmsPcm16(pcmBytes) < SILENCE_RMS_THRESHOLD) {
            throw ModelException("INFERENCE_FAILED", "No speech detected. Try again closer to the mic.")
        }

        // Cap to ~20s to stay within practical audio-window limits.
        val maxBytes = sampleRateHz * 2 * MAX_SECONDS
        val clipped = if (pcmBytes.size > maxBytes) {
            pcmBytes.copyOfRange(pcmBytes.size - maxBytes, pcmBytes.size)
        } else {
            pcmBytes
        }

        val wavBytes = WavEncoder.pcm16MonoToWav(clipped, sampleRateHz)
        Log.i(TAG, "Transcribing wavBytes=${wavBytes.size} backend=$backendName")

        val started = System.nanoTime()
        var conversation: Conversation? = null
        try {
            conversation = eng.createConversation(
                ConversationConfig(
                    samplerConfig = SamplerConfig(
                        topK = 1,
                        topP = 0.9,
                        temperature = 0.0,
                    ),
                ),
            )

            // Synchronous only — async callback_thread crashes on some MediaTek devices.
            val response: Message = conversation.sendMessage(
                Contents.of(
                    Content.Text(prompt),
                    Content.AudioBytes(wavBytes),
                ),
            )
            val text = extractText(response)
            lastInferenceMs = (System.nanoTime() - started) / 1_000_000
            lastInferenceMs?.let { inferenceDurations.add(it) }
            Log.i(TAG, "Transcription done ms=$lastInferenceMs chars=${text.length}")
            if (text.isBlank()) {
                throw ModelException("INFERENCE_FAILED", "Model returned an empty transcript. Please try again.")
            }
            text
        } catch (me: ModelException) {
            throw me
        } catch (t: Throwable) {
            Log.e(TAG, "Transcription failed", t)
            val detail = t.message?.take(160).orEmpty()
            throw ModelException(
                "INFERENCE_FAILED",
                if (detail.isNotBlank()) "On-device inference failed: $detail"
                else "On-device inference failed.",
            )
        } finally {
            try {
                conversation?.close()
            } catch (_: Throwable) {
            }
            // MediaTek workaround: Conversation often becomes unusable after one turn.
            // Reload Engine so the next utterance is a clean first call.
            try {
                loadEngine()
            } catch (t: Throwable) {
                Log.w(TAG, "Engine reload after turn failed", t)
                releaseInternal()
            }
        }
    }

    private fun extractText(message: Message): String {
        return try {
            val direct = runCatching {
                message.javaClass.getMethod("getText").invoke(message) as? String
            }.getOrNull()
            if (!direct.isNullOrBlank()) return direct.trim()

            val contents = runCatching {
                message.javaClass.getMethod("getContents").invoke(message)
            }.getOrNull()
            if (contents is Iterable<*>) {
                val joined = contents.mapNotNull { item ->
                    runCatching {
                        item?.javaClass?.getMethod("getText")?.invoke(item) as? String
                    }.getOrNull()
                }.filter { it.isNotBlank() }.joinToString("")
                if (joined.isNotBlank()) return joined.trim()
            }
            message.toString().trim()
        } catch (_: Throwable) {
            message.toString().trim()
        }
    }

    private fun rmsPcm16(pcm: ByteArray): Double {
        if (pcm.size < 4) return 0.0
        var sumSquares = 0.0
        var samples = 0
        var i = 0
        while (i + 1 < pcm.size) {
            val sample = (pcm[i].toInt() and 0xff) or (pcm[i + 1].toInt() shl 8)
            val signed = sample.toShort().toInt()
            sumSquares += signed.toDouble() * signed.toDouble()
            samples++
            i += 2
        }
        if (samples == 0) return 0.0
        return sqrt(sumSquares / samples)
    }

    fun release() {
        releaseInternal()
    }

    private fun releaseInternal() {
        try {
            engine?.close()
        } catch (_: Throwable) {
        }
        engine = null
    }

    fun deviceCompatibility(): Map<String, Any?> {
        val totalMemMb = try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val info = android.app.ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            info.totalMem / (1024.0 * 1024.0)
        } catch (_: Throwable) {
            0.0
        }

        val supported = totalMemMb <= 0 || totalMemMb >= MINIMUM_RAM_MB
        val lowMemoryWarning = supported && totalMemMb > 0 && totalMemMb < RECOMMENDED_RAM_MB
        val message = when {
            !supported ->
                "This device does not meet the minimum requirements for on-device voice AI."
            lowMemoryWarning ->
                "Device supports on-device AI with limited RAM " +
                    "(${"%.1f".format(totalMemMb / 1024.0)}GB). Use short clips."
            else -> "Device supports on-device AI"
        }

        return mapOf(
            "supported" to supported,
            "message" to message,
            "osVersion" to Build.VERSION.SDK_INT,
            "ramMb" to totalMemMb,
            "abi" to Build.SUPPORTED_ABIS.toList(),
            "minimumRamMb" to MINIMUM_RAM_MB,
            "recommendedRamMb" to RECOMMENDED_RAM_MB,
            "lowMemoryWarning" to lowMemoryWarning,
            "runtime" to "LiteRT-LM",
            "mode" to "push_to_talk",
        )
    }

    companion object {
        private const val TAG = "ModelInferenceEngine"
        const val MINIMUM_RAM_MB = 3072.0
        const val RECOMMENDED_RAM_MB = 6144.0
        private const val SILENCE_RMS_THRESHOLD = 180.0
        private const val MAX_SECONDS = 20
    }
}

class ModelException(val code: String, override val message: String) : Exception(message)
