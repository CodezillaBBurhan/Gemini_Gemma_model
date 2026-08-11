enum VoiceAiState {
  uninitialized,
  initializing,
  modelLoading,
  modelDownloading,
  modelReady,
  requestingPermission,
  listening,
  processing,
  completed,
  error,
  disposed,
  unsupportedDevice,
}

extension VoiceAiStateX on VoiceAiState {
  bool get isBusy =>
      this == VoiceAiState.initializing ||
      this == VoiceAiState.modelLoading ||
      this == VoiceAiState.modelDownloading ||
      this == VoiceAiState.requestingPermission ||
      this == VoiceAiState.listening ||
      this == VoiceAiState.processing;

  bool get canStartListening =>
      this == VoiceAiState.modelReady ||
      this == VoiceAiState.completed ||
      this == VoiceAiState.error;

  String get label {
    switch (this) {
      case VoiceAiState.uninitialized:
        return 'Not initialized';
      case VoiceAiState.initializing:
        return 'Initializing…';
      case VoiceAiState.modelLoading:
        return 'Loading model…';
      case VoiceAiState.modelDownloading:
        return 'Downloading model…';
      case VoiceAiState.modelReady:
        return 'Model ready';
      case VoiceAiState.requestingPermission:
        return 'Requesting microphone…';
      case VoiceAiState.listening:
        return 'Listening…';
      case VoiceAiState.processing:
        return 'Processing locally…';
      case VoiceAiState.completed:
        return 'Completed';
      case VoiceAiState.error:
        return 'Error';
      case VoiceAiState.disposed:
        return 'Disposed';
      case VoiceAiState.unsupportedDevice:
        return 'Unsupported device';
    }
  }
}
