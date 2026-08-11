package com.example.gemma_poc.voiceai

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class OnDeviceVoiceAiPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener,
    android.content.ComponentCallbacks2 {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var activity: Activity? = null
    private var appContext: android.content.Context? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var engine: ModelInferenceEngine? = null
    private var capture: AudioCaptureManager? = null
    private var listenJob: Job? = null

    private var sampleRateHz: Int = 16000
    private var chunkDurationMs: Int = 3000
    private var transcriptionPrompt: String =
        "You are a helpful on-device voice assistant. Listen to the user and reply conversationally. Do not only transcribe."
    private var maxOutputTokens: Int = 256
    private var modelPath: String? = null
    private var backend: String = "cpu"

    private val listening = AtomicBoolean(false)
    private val pcmBuffer = ByteArrayOutputStream()
    private val inferMutex = Mutex()

    private var firstTranscriptMs: Long? = null
    private var listenStartedAtMs: Long? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "com.example.gemma_poc/on_device_voice_ai/methods",
        )
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "com.example.gemma_poc/on_device_voice_ai/events",
        )
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        engine = ModelInferenceEngine(binding.applicationContext)
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        binding.applicationContext.registerComponentCallbacks(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        try {
            binding.applicationContext.unregisterComponentCallbacks(this)
        } catch (_: Throwable) {
        }
        teardown()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        appContext = null
    }

    override fun onTrimMemory(level: Int) {
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
            level == android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE
        ) {
            if (!listening.get()) {
                engine?.release()
                emitState("uninitialized")
                emitError("INSUFFICIENT_MEMORY", "Not enough memory to run on-device AI.")
            }
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) = Unit
    override fun onLowMemory() {
        onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkCompatibility" -> {
                val map = engine?.deviceCompatibility() ?: mapOf(
                    "supported" to false,
                    "message" to "Native on-device AI runtime is unavailable.",
                )
                result.success(map)
            }

            "initialize" -> {
                sampleRateHz = call.argument<Int>("sampleRateHz") ?: 16000
                chunkDurationMs = call.argument<Int>("chunkDurationMs") ?: 3000
                transcriptionPrompt = call.argument<String>("transcriptionPrompt")
                    ?: transcriptionPrompt
                maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256
                backend = call.argument<String>("backend") ?: "cpu"
                modelPath = call.argument<String>("modelPath")
                val path = modelPath
                if (path.isNullOrBlank()) {
                    result.error("MODEL_NOT_FOUND", "On-device AI model is not ready.", null)
                    return
                }
                emitState("modelLoading")
                scope.launch(Dispatchers.Default) {
                    try {
                        engine?.initialize(path, backend, maxOutputTokens)
                        emitState("modelReady")
                        mainHandler.post { result.success(null) }
                    } catch (me: ModelException) {
                        emitError(me.code, me.message)
                        mainHandler.post { result.error(me.code, me.message, null) }
                    } catch (t: Throwable) {
                        emitError("MODEL_LOAD_FAILED", "Model loading failed.")
                        mainHandler.post {
                            result.error("MODEL_LOAD_FAILED", "Model loading failed.", null)
                        }
                    }
                }
            }

            "prepareModel" -> {
                val url = call.argument<String>("downloadUrl")
                val token = call.argument<String>("authToken")
                val fileName = call.argument<String>("fileName") ?: "gemma-3n-E2B-it-int4.litertlm"
                val expected = call.argument<Number>("expectedBytes")?.toLong() ?: -1L
                if (url.isNullOrBlank()) {
                    result.error("MODEL_NOT_FOUND", "On-device AI model is not ready.", null)
                    return
                }
                emitState("modelDownloading")
                scope.launch(Dispatchers.IO) {
                    try {
                        val file = downloadModel(url, token, fileName, expected)
                        modelPath = file.absolutePath
                        emitState("modelReady")
                        mainHandler.post { result.success(file.absolutePath) }
                    } catch (t: Throwable) {
                        emitError("MODEL_LOAD_FAILED", t.message ?: "Model download failed.")
                        mainHandler.post {
                            result.error("MODEL_LOAD_FAILED", t.message, null)
                        }
                    }
                }
            }

            "startListening" -> startListening(result)
            "stopListening" -> {
                val args = call.arguments as? Map<*, *>
                val contextText = args?.get("conversationContext") as? String
                val promptOverride = args?.get("prompt") as? String
                if (!promptOverride.isNullOrBlank()) {
                    transcriptionPrompt = promptOverride
                }
                stopListeningAndTranscribe(result, contextText)
            }

            "unloadModel" -> {
                stopCaptureOnly()
                engine?.release()
                emitState("uninitialized")
                result.success(null)
            }

            "getBenchmarkMetrics" -> result.success(benchmarkMap())
            "dispose" -> {
                teardown()
                emitState("disposed")
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun startListening(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("MIC_UNAVAILABLE", "Microphone is unavailable.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(act, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            permissionResult = result
            emitState("requestingPermission")
            ActivityCompat.requestPermissions(
                act,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQUEST_RECORD_AUDIO,
            )
            return
        }
        beginCapture(result)
    }

    private fun beginCapture(result: MethodChannel.Result) {
        if (engine?.isReady != true) {
            result.error("MODEL_NOT_FOUND", "On-device AI model is not ready.", null)
            return
        }
        if (!listening.compareAndSet(false, true)) {
            result.success(null)
            return
        }

        pcmBuffer.reset()
        firstTranscriptMs = null
        listenStartedAtMs = System.currentTimeMillis()

        // Capture short segments into one buffer; inference runs only after Stop.
        // Live multi-turn sendMessageAsync SIGSEGVs on many MediaTek devices.
        capture = AudioCaptureManager(
            sampleRateHz = sampleRateHz,
            chunkDurationMs = 500,
            onChunk = { bytes, _ ->
                synchronized(pcmBuffer) {
                    val maxBytes = sampleRateHz * 2 * 20 // ~20s cap
                    if (pcmBuffer.size() < maxBytes) {
                        val room = maxBytes - pcmBuffer.size()
                        pcmBuffer.write(bytes, 0, minOf(bytes.size, room))
                    }
                }
            },
            onError = { code, message ->
                emitError(code, message)
                stopCaptureOnly()
            },
        )
        capture?.start()
        emitState("listening")
        result.success(null)
    }

    private fun stopListeningAndTranscribe(
        result: MethodChannel.Result,
        conversationContext: String?,
    ) {
        if (!listening.get() && pcmBuffer.size() == 0) {
            emitState("completed")
            result.success(null)
            return
        }

        stopCaptureOnly()
        emitState("processing")

        val pcm = synchronized(pcmBuffer) {
            val bytes = pcmBuffer.toByteArray()
            pcmBuffer.reset()
            bytes
        }

        val prompt = buildString {
            append(transcriptionPrompt.trim())
            append('\n')
            if (!conversationContext.isNullOrBlank()) {
                append('\n')
                append(conversationContext.trim())
                append('\n')
            }
            append("\nListen to the new user audio and reply as the assistant.")
        }

        scope.launch(Dispatchers.Default) {
            inferMutex.withLock {
                try {
                    val text = engine?.transcribeUtterance(
                        pcmBytes = pcm,
                        prompt = prompt,
                        sampleRateHz = sampleRateHz,
                    ).orEmpty()

                    if (firstTranscriptMs == null && text.isNotBlank()) {
                        firstTranscriptMs =
                            System.currentTimeMillis() -
                                (listenStartedAtMs ?: System.currentTimeMillis())
                    }

                    if (text.isNotBlank()) {
                        emitEvent(
                            mapOf(
                                "type" to "assistantReply",
                                "text" to text,
                                "chunkIndex" to 0,
                                "isFinal" to true,
                            ),
                        )
                    }
                    emitState("completed")
                    mainHandler.post { result.success(null) }
                } catch (me: ModelException) {
                    emitError(me.code, me.message)
                    emitState("error")
                    mainHandler.post { result.error(me.code, me.message, null) }
                } catch (t: Throwable) {
                    Log.e("OnDeviceVoiceAi", "Utterance failed", t)
                    emitError("INFERENCE_FAILED", t.message ?: "On-device inference failed.")
                    emitState("error")
                    mainHandler.post {
                        result.error("INFERENCE_FAILED", t.message, null)
                    }
                }
            }
        }
    }

    private fun stopCaptureOnly() {
        listening.set(false)
        capture?.stop()
        capture = null
        listenJob?.cancel()
        listenJob = null
    }

    private fun downloadModel(
        url: String,
        token: String?,
        fileName: String,
        expectedBytes: Long,
    ): File {
        val ctx = appContext ?: throw IllegalStateException("No context")
        val dir = File(ctx.filesDir, "models").apply { mkdirs() }
        val target = File(dir, fileName)
        val partial = File(dir, "$fileName.partial")

        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 60_000
            setRequestProperty("User-Agent", "gemma_poc-on-device-ai")
            if (!token.isNullOrBlank()) {
                setRequestProperty("Authorization", "Bearer $token")
            }
        }

        val code = connection.responseCode
        if (code == 401 || code == 403) {
            throw IllegalStateException(
                "Model download requires Hugging Face access for the gated Gemma repo.",
            )
        }
        if (code !in 200..299) {
            throw IllegalStateException("Model download failed (HTTP $code).")
        }

        val total = connection.contentLengthLong.takeIf { it > 0 } ?: expectedBytes
        var received = 0L
        BufferedInputStream(connection.inputStream).use { input ->
            FileOutputStream(partial).use { output ->
                val buffer = ByteArray(1024 * 256)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                    received += read
                    if (total > 0) {
                        emitEvent(
                            mapOf(
                                "type" to "downloadProgress",
                                "progress" to (received.toDouble() / total.toDouble()).coerceIn(0.0, 1.0),
                            ),
                        )
                    }
                }
            }
        }
        connection.disconnect()
        if (target.exists()) target.delete()
        if (!partial.renameTo(target)) {
            partial.copyTo(target, overwrite = true)
            partial.delete()
        }
        emitEvent(mapOf("type" to "downloadProgress", "progress" to 1.0))
        return target
    }

    private fun benchmarkMap(): Map<String, Any?> {
        val eng = engine
        return mapOf(
            "modelId" to "gemma-3n-E2B-it-int4",
            "backend" to (eng?.backendName ?: backend),
            "modelLoadMs" to eng?.modelLoadMs,
            "audioProcessingMs" to eng?.lastInferenceMs,
            "firstTranscriptMs" to firstTranscriptMs,
            "averageInferenceMs" to eng?.averageInferenceMs,
            "ramMb" to (eng?.deviceCompatibility()?.get("ramMb")),
            "cpuPercent" to null,
            "chunkCount" to (eng?.averageInferenceMs?.let { 1 } ?: 0),
        )
    }

    private fun emitState(state: String) {
        emitEvent(mapOf("type" to "state", "state" to state))
    }

    private fun emitError(code: String, message: String) {
        emitEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
            ),
        )
    }

    private fun emitEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private fun teardown() {
        stopCaptureOnly()
        synchronized(pcmBuffer) { pcmBuffer.reset() }
        engine?.release()
        engine = null
        scope.cancel()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_RECORD_AUDIO) return false
        val result = permissionResult ?: return true
        permissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            beginCapture(result)
        } else {
            emitError("PERMISSION_DENIED", "Microphone permission is required.")
            result.error("PERMISSION_DENIED", "Microphone permission is required.", null)
        }
        return true
    }

    companion object {
        private const val REQUEST_RECORD_AUDIO = 2401
    }
}
