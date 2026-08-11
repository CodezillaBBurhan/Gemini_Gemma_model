import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gemma_poc/core/config/on_device_ai_config.dart';
import 'package:gemma_poc/core/platform/on_device_ai_channel.dart';
import 'package:gemma_poc/features/voice_ai/models/benchmark_metrics.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_voice_ai_service.dart';

/// Flutter ↔ native bridge using MethodChannel + EventChannel.
class OnDeviceVoiceAiPlatform implements OnDeviceVoiceAiService {
  OnDeviceVoiceAiPlatform({
    MethodChannel? methods,
    EventChannel? events,
  })  : _methods = methods ?? OnDeviceAiChannel.methods,
        _events = events ?? OnDeviceAiChannel.events;

  final MethodChannel _methods;
  final EventChannel _events;

  final _transcriptController = StreamController<String>.broadcast();
  final _stateController = StreamController<VoiceAiState>.broadcast();
  final _downloadController = StreamController<double>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  bool _disposed = false;

  @override
  Stream<String> get transcriptStream => _transcriptController.stream;

  @override
  Stream<VoiceAiState> get stateStream => _stateController.stream;

  @override
  Stream<double> get downloadProgressStream => _downloadController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void _ensureListening() {
    if (_eventSub != null || _disposed) return;
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error, StackTrace stack) {
        debugPrint('Voice AI event channel error: $error');
        _errorController.add(_friendlyError(error));
        _stateController.add(VoiceAiState.error);
      },
    );
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    _eventController.add(event);

    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'state':
        final stateName = event['state'] as String? ?? '';
        final state = _parseState(stateName);
        if (state != null) _stateController.add(state);
      case 'partialTranscript':
      case 'finalTranscript':
        final text = event['text'] as String? ?? '';
        if (text.isNotEmpty) _transcriptController.add(text);
      case 'downloadProgress':
        final progress = (event['progress'] as num?)?.toDouble() ?? 0;
        _downloadController.add(progress.clamp(0, 1));
      case 'error':
        final message = event['message'] as String? ?? 'On-device model unavailable.';
        _errorController.add(message);
        _stateController.add(VoiceAiState.error);
      case 'benchmark':
        // Consumed via getBenchmarkMetrics / eventStream.
        break;
      default:
        break;
    }
  }

  VoiceAiState? _parseState(String name) {
    for (final value in VoiceAiState.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'MODEL_NOT_FOUND':
          return 'On-device AI model is not ready.';
        case 'MODEL_LOAD_FAILED':
          return 'Model loading failed.';
        case 'MODEL_CORRUPTED':
          return 'Model file appears corrupted.';
        case 'INSUFFICIENT_MEMORY':
          return 'Not enough memory to run on-device AI.';
        case 'UNSUPPORTED_DEVICE':
          return 'This device does not meet the minimum requirements for on-device voice AI.';
        case 'PERMISSION_DENIED':
          return 'Microphone permission is required.';
        case 'MIC_UNAVAILABLE':
          return 'Microphone is unavailable.';
        case 'AUDIO_INIT_FAILED':
          return 'Audio initialization failed.';
        case 'INFERENCE_FAILED':
          return 'On-device inference failed.';
        case 'RUNTIME_UNAVAILABLE':
          return 'Native on-device AI runtime is unavailable.';
        case 'UNSUPPORTED_MODEL':
          return 'Unsupported model format.';
        default:
          return error.message ?? 'On-device model unavailable.';
      }
    }
    return 'On-device model unavailable.';
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    _ensureListening();
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      final message = _friendlyError(e);
      _errorController.add(message);
      _stateController.add(VoiceAiState.error);
      rethrow;
    }
  }

  @override
  Future<void> initialize({String? modelPath, String? backend}) async {
    _ensureListening();
    _stateController.add(VoiceAiState.initializing);
    await _invoke<void>('initialize', {
      'modelPath': modelPath,
                  'backend': backend ?? 'cpu',
                  'sampleRateHz': OnDeviceAiConfig.sampleRateHz,
      'chunkDurationMs': OnDeviceAiConfig.chunkDurationMs,
                  'transcriptionPrompt': OnDeviceAiConfig.conversationPrompt,
      'maxOutputTokens': OnDeviceAiConfig.maxOutputTokens,
      'modelFileName': OnDeviceAiConfig.modelFileName,
    });
  }

  @override
  Future<void> prepareModel({
    required String downloadUrl,
    String? authToken,
  }) async {
    _ensureListening();
    _stateController.add(VoiceAiState.modelDownloading);
    await _invoke<void>('prepareModel', {
      'downloadUrl': downloadUrl,
      'authToken': authToken,
      'expectedBytes': OnDeviceAiConfig.expectedModelBytes,
      'fileName': OnDeviceAiConfig.modelFileName,
    });
  }

  @override
  Future<Map<String, dynamic>> checkCompatibility() async {
    _ensureListening();
    final result = await _invoke<Map<dynamic, dynamic>>('checkCompatibility');
    return Map<String, dynamic>.from(result ?? const {});
  }

  @override
  Future<void> startListening() async {
    await _invoke<void>('startListening');
  }

  @override
  Future<void> stopListening({String? conversationContext}) async {
    await _invoke<void>('stopListening', {
      'conversationContext': conversationContext,
      'prompt': OnDeviceAiConfig.conversationPrompt,
    });
  }

  @override
  Future<void> unloadModel() async {
    await _invoke<void>('unloadModel');
  }

  @override
  Future<BenchmarkMetrics> getBenchmarkMetrics() async {
    final result = await _invoke<Map<dynamic, dynamic>>('getBenchmarkMetrics');
    return BenchmarkMetrics.fromMap(result);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _methods.invokeMethod<void>('dispose');
    } catch (_) {
      // Best-effort native cleanup.
    }
    await _eventSub?.cancel();
    _eventSub = null;
    await _transcriptController.close();
    await _stateController.close();
    await _downloadController.close();
    await _errorController.close();
    await _eventController.close();
  }
}
