package com.example.gemma_poc.voiceai

/**
 * Manual / instrumented verification checklist for on-device voice AI.
 *
 * Automate with Espresso/UIAutomator on a physical device once a model file is present:
 * 1) Grant RECORD_AUDIO
 * 2) Initialize with a local .litertlm path
 * 3) Start listening, speak, assert finalTranscript events
 * 4) Enable Airplane Mode and repeat step 3
 * 5) Background/foreground the app during listening and confirm no crash
 * 6) Trigger low-memory trim and confirm unload/reload path
 *
 * These steps require a real device + model download and are not executed in CI by default.
 */
object OnDeviceVoiceAiInstrumentedHints {
    const val AIRPLANE_MODE_REQUIRED = true
    const val NO_CLOUD_FALLBACK = true
}
