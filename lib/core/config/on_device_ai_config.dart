/// Configurable on-device AI settings. Do not hard-code model paths elsewhere.
class OnDeviceAiConfig {
  OnDeviceAiConfig._();

  /// Preferred model: Gemma 3n E2B (smallest multimodal with audio).
  static const String modelId = 'gemma-3n-E2B-it-int4';

  /// Local filename after download / optional asset copy.
  static const String modelFileName = 'gemma-3n-E2B-it-int4.litertlm';

  /// Relative path used when the model is bundled as a Flutter asset.
  static const String modelAssetPath = 'assets/models/gemma-3n-E2B-it-int4.litertlm';

  /// Official Hugging Face repo (gated; requires HF access token for download).
  static const String modelHuggingFaceRepo = 'google/gemma-3n-E2B-it-litert-lm';

  /// Direct resolve URL for the mobile `.litertlm` bundle.
  static const String modelDownloadUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/'
      'gemma-3n-E2B-it-int4.litertlm';

  /// Approximate download size in bytes (~2.97 GB). Used for progress UI.
  static const int expectedModelBytes = 3113851289;

  /// LiteRT-LM runtime version pin (Android Maven / iOS SPM).
  static const String liteRtLmVersion = '0.15.0';

  /// PCM capture settings for Gemma 3n audio encoder.
  static const int sampleRateHz = 16000;
  static const int channelCount = 1;
  static const int bitsPerSample = 16;

  /// Preferred backends in order of preference.
  /// CPU is more reliable for multimodal audio on mid-range phones.
  static const List<String> preferredBackends = ['cpu', 'gpu'];

  /// Chunked transcription window (ms). Runtime does not provide continuous STT.
  static const int chunkDurationMs = 4000;

  /// Max tokens for assistant replies / KV cache hint.
  static const int maxOutputTokens = 512;

  /// Conversational instruction for Gemma 3n audio turns.
  /// Not transcription-only: the model should answer the user.
  static const String conversationPrompt =
      'You are a helpful on-device voice assistant running fully offline. '
      'Listen to the user audio and reply conversationally. '
      'Be concise, clear, and useful. '
      'Do NOT only transcribe the speech. Understand it and respond as an assistant. '
      'If the audio is unclear, ask a short clarifying question.';

  /// Kept for compatibility with older native call sites.
  static const String transcriptionPrompt = conversationPrompt;

  /// Optional Hugging Face token for gated model download (NOT a Gemini API key).
  /// Pass via: flutter run --dart-define=HF_TOKEN=hf_xxx
  static const String hfToken = String.fromEnvironment('HF_TOKEN');

  /// Channel names shared with native plugins.
  static const String methodChannelName = 'com.example.gemma_poc/on_device_voice_ai/methods';
  static const String eventChannelName = 'com.example.gemma_poc/on_device_voice_ai/events';
}
