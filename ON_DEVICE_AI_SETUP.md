# On-Device Gemma 3n Voice-to-Text Setup

Fully offline voice transcription using **Google AI Edge LiteRT-LM** and **Gemma 3n E2B** on Android and iOS. No Gemini API, Google Cloud Speech, backend, or WebSocket inference path is used.

## Capability verification (read this first)

Verified against Google AI Edge documentation (LiteRT-LM 0.15.x / Gemma 3n mobile):

| Capability | Status |
|---|---|
| Audio input into mobile runtime | **Supported** (`Content.AudioBytes` / audio backend) |
| Batch / clip transcription | **Supported** (clips; encoder historically ~30s) |
| Continuous microphone streaming ASR | **Not supported** as a first-class STT stream |
| Incremental token output for a clip | **Supported** (`sendMessageAsync` stream) |
| Partial ASR hypotheses like cloud STT | **Not supported** |
| Airplane-mode inference after model install | **Supported** (required) |

**Honest architecture used by this app**

```text
Microphone → PCM16 @ 16 kHz mono → short chunks (~3s)
    → LiteRT-LM + Gemma 3n (local) → transcript chunk
    → Flutter UI (progressive append)
```

This is **chunked on-device transcription**, not fake continuous streaming. Latency is dominated by chunk length + model prefill/decode.

If product requirements need lower-latency ASR later, keep Gemma 3n for NLU and add a dedicated on-device STT model (still offline). Do not fall back to cloud APIs.

## Model

| Field | Value |
|---|---|
| Model | **Gemma 3n E2B** (preferred over E4B for mobile RAM/latency) |
| Source | Official Hugging Face: `google/gemma-3n-E2B-it-litert-lm` |
| File | `gemma-3n-E2B-it-int4.litertlm` |
| Format | `.litertlm` (LiteRT-LM bundle) |
| Quantization | int4 weights |
| Approx size | ~2.97 GB (config: `expectedModelBytes`) |
| Expected RAM | Recommend **6 GB+** device RAM for multimodal audio |
| Hardware | CPU required; GPU preferred when available; NPU optional |
| License | Gemma Terms of Use (accept on Hugging Face before download) |
| Config class | `lib/core/config/on_device_ai_config.dart` |

E4B was evaluated and **not** selected by default (larger memory / slower decode on phones).

## Distribution strategy

**Option B — download after install** (default)

1. App installs without embedding the ~3 GB model.
2. User taps **Prepare Model** (needs network once).
3. Model is stored under app support/files (`…/models/`).
4. After that, inference works in Airplane Mode.

**Option A — bundle in APK/IPA** is supported only if you place the `.litertlm` under `assets/models/` and update packaging. Not recommended for store size limits.

Download URL is the official Hugging Face resolve URL. The Gemma repo is **gated**: accept the license and pass a Hugging Face token (this is **not** a Gemini API key):

```bash
flutter run --dart-define=HF_TOKEN=hf_xxx
```

## Project inventory (Phase 1)

| Item | Value |
|---|---|
| Flutter | 3.38.5 |
| Dart | 3.10.4 |
| Android minSdk | 26 |
| Android target/compileSdk | 36 |
| Kotlin | 2.2.20 |
| Android Gradle Plugin | 8.11.1 |
| Gradle | 8.14 |
| iOS deployment target | 15.0 |
| Xcode | 26.1 |
| State management | `ChangeNotifier` / `AnimatedBuilder` (no GetX/Bloc/Riverpod) |
| Audio packages (Flutter) | none for inference; mic captured natively |
| AI API keys in repo | **none** |

## Flutter integration

Feature path:

```text
lib/features/voice_ai/
  controllers/voice_ai_controller.dart
  services/on_device_voice_ai_service.dart
  services/on_device_voice_ai_platform.dart
  services/model_download_service.dart
  models/...
  screens/voice_ai_screen.dart
  screens/voice_ai_benchmark_screen.dart
  widgets/...
lib/core/platform/on_device_ai_channel.dart
lib/core/config/on_device_ai_config.dart
```

Channels:

- MethodChannel: `com.example.gemma_poc/on_device_voice_ai/methods`
- EventChannel: `com.example.gemma_poc/on_device_voice_ai/events`

## Native integration

### Android

- Dependency: `com.google.ai.edge.litertlm:litertlm-android:0.15.0`
- Plugin: `android/.../voiceai/OnDeviceVoiceAiPlugin.kt`
- Capture: `AudioRecord` PCM16 mono 16 kHz
- Inference: LiteRT-LM `Engine` + `Conversation` with `Content.AudioBytes`
- Permissions: `RECORD_AUDIO` (+ `INTERNET` only for model download)
- GPU optional native libs declared in `AndroidManifest.xml`

### iOS

- SPM package: `https://github.com/google-ai-edge/LiteRT-LM` (product `LiteRTLM`)
- Sources: `ios/Runner/OnDeviceVoiceAi/*.swift`
- Capture: `AVAudioEngine` → PCM16 mono 16 kHz
- `NSMicrophoneUsageDescription` explains **local** processing
- If SPM is missing, app reports `RUNTIME_UNAVAILABLE` (no cloud fallback)
- Add SPM manually in Xcode (see `scripts/add_ios_litertlm_spm.md`). Do not rely on headless auto-resolve; it can stall `xcodebuild`.

## Running the app

```bash
flutter pub get
flutter run --dart-define=HF_TOKEN=hf_xxx   # first model download
```

Then:

1. Tap **Prepare Model** and wait for 100%.
2. Enable Airplane Mode.
3. Tap **Start Listening** and speak.
4. Confirm progressive chunk transcripts appear.
5. Confirm no network calls are required for inference.

## Offline test checklist

- [ ] Internet ON → model download works
- [ ] Wi-Fi OFF / Cellular OFF / Airplane Mode → listening + transcription still works
- [ ] No Gemini / Cloud Speech / backend traffic during inference
- [ ] Denying microphone shows Open Settings path
- [ ] Missing model shows Prepare Model path

## Performance benchmarks

Fill after device runs (Benchmark screen in-app):

| Device class | Backend | Model load | First transcript | Avg chunk inference | Peak RAM |
|---|---|---|---|---|---|
| Low-end Android | CPU | | | | |
| Mid-range Android | GPU/CPU | | | | |
| High-end Android | GPU | | | | |
| Recent iPhone | GPU/Metal | | | | |
| Older supported iPhone | CPU | | | | |

Reference (Google LiteRT-LM table, text chat, Samsung S24 Ultra, Gemma-3n-E2B): CPU ~16 tok/s decode, GPU ~16 tok/s decode; multimodal audio adds encoder cost on top.

## Known limitations

1. Not continuous cloud-style partial ASR; chunk windows (~3s default).
2. Gemma audio quality depends on prompt + acoustics; not a dedicated ASR model.
3. First model download requires HF access + large download.
4. Large RAM / thermal impact; model is unloaded on dispose / unload.
5. iOS LiteRT-LM Swift API is early preview; validate on a **real device**.
6. MediaPipe LLM Inference API is maintenance-only; this project uses **LiteRT-LM**.
7. `flutter build ios --no-codesign` succeeds for the Runner shell; link **LiteRTLM** via SPM before expecting audio inference on device.
8. Audio bytes sent to LiteRT-LM must be **WAV** (or FLAC/MP3). Raw PCM alone fails with miniaudio error `-10`; the app wraps mic PCM in a WAV header before inference.
9. On some **MediaTek** devices, LiteRT-LM can SIGSEGV on `sendMessageAsync` / second Conversation turns. This app uses **push-to-talk**: record → Stop → one synchronous `sendMessage`, then reload Engine.

## Troubleshooting

| Symptom | Fix |
|---|---|
| HTTP 401/403 on download | Accept Gemma license on HF; pass `HF_TOKEN` |
| `RUNTIME_UNAVAILABLE` on iOS | Add LiteRT-LM SPM product to Runner |
| `INSUFFICIENT_MEMORY` | Close background apps; use E2B; unload when idle |
| `PERMISSION_DENIED` | Grant mic in system settings |
| Slow transcripts | Prefer GPU backend; reduce `chunkDurationMs` cautiously |
| App size too large | Keep Option B (do not bundle model) |

## Security & privacy

- No Gemini / Google Cloud credentials in `lib/`, `android/`, `ios/`, or `assets/`.
- Microphone audio and transcripts stay on-device.
- Do not log raw audio or sensitive transcript content in production builds.
