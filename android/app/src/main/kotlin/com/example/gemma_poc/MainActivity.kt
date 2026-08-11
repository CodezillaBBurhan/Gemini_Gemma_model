package com.example.gemma_poc

import com.example.gemma_poc.voiceai.OnDeviceVoiceAiPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(OnDeviceVoiceAiPlugin())
    }
}
