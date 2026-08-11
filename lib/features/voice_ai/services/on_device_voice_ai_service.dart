import 'package:gemma_poc/features/voice_ai/models/benchmark_metrics.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';

/// Platform-agnostic contract for on-device voice AI.
abstract class OnDeviceVoiceAiService {
  Future<void> initialize({String? modelPath, String? backend});

  Future<void> prepareModel({
    required String downloadUrl,
    String? authToken,
  });

  Future<Map<String, dynamic>> checkCompatibility();

  Future<void> startListening();

  Future<void> stopListening({String? conversationContext});

  Future<void> unloadModel();

  Future<void> dispose();

  Future<BenchmarkMetrics> getBenchmarkMetrics();

  Stream<String> get transcriptStream;

  Stream<VoiceAiState> get stateStream;

  Stream<double> get downloadProgressStream;

  Stream<String> get errorStream;

  Stream<Map<String, dynamic>> get eventStream;
}
