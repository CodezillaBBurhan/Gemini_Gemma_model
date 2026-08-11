import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gemma_poc/core/config/on_device_ai_config.dart';
import 'package:gemma_poc/features/voice_ai/models/benchmark_metrics.dart';
import 'package:gemma_poc/features/voice_ai/models/chat_message.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';
import 'package:gemma_poc/features/voice_ai/services/model_download_service.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_tts_service.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_voice_ai_platform.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_voice_ai_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// UI-facing controller. Uses [ChangeNotifier] to match the app's simple architecture.
class VoiceAiController extends ChangeNotifier {
  VoiceAiController({
    OnDeviceVoiceAiService? service,
    ModelDownloadService? downloadService,
    OnDeviceTtsService? ttsService,
  })  : _service = service ?? OnDeviceVoiceAiPlatform(),
        _downloadService = downloadService ?? ModelDownloadService(),
        _tts = ttsService ?? OnDeviceTtsService() {
    _bindService();
    unawaited(_tts.initialize());
  }

  final OnDeviceVoiceAiService _service;
  final ModelDownloadService _downloadService;
  final OnDeviceTtsService _tts;

  final List<StreamSubscription<dynamic>> _subs = [];
  final List<ChatMessage> _messages = [];

  VoiceAiState _state = VoiceAiState.uninitialized;
  String _partialText = '';
  String _errorMessage = '';
  double _downloadProgress = 0;
  bool _modelReady = false;
  bool _supported = true;
  String _compatibilityMessage = '';
  BenchmarkMetrics _benchmarks = const BenchmarkMetrics();
  bool _offlineVerified = false;
  bool _lowMemoryWarning = false;
  bool _voiceReplyEnabled = true;
  bool _isSpeaking = false;

  VoiceAiState get state => _state;
  String get partialText => _partialText;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String get errorMessage => _errorMessage;
  double get downloadProgress => _downloadProgress;
  bool get modelReady => _modelReady;
  bool get supported => _supported;
  String get compatibilityMessage => _compatibilityMessage;
  bool get lowMemoryWarning => _lowMemoryWarning;
  BenchmarkMetrics get benchmarks => _benchmarks;
  bool get offlineVerified => _offlineVerified;
  bool get voiceReplyEnabled => _voiceReplyEnabled;
  bool get isSpeaking => _isSpeaking;

  void _bindService() {
    _subs.addAll([
      _service.stateStream.listen((s) {
        _state = s;
        if (s == VoiceAiState.modelReady) {
          _modelReady = true;
        }
        notifyListeners();
      }),
      _service.transcriptStream.listen((_) {}),
      _service.downloadProgressStream.listen((p) {
        _downloadProgress = p;
        _state = VoiceAiState.modelDownloading;
        notifyListeners();
      }),
      _service.errorStream.listen((message) {
        _errorMessage = message;
        _state = VoiceAiState.error;
        notifyListeners();
      }),
      _service.eventStream.listen((event) {
        final type = event['type'] as String? ?? '';
        if (type == 'partialTranscript' || type == 'assistantPartial') {
          final text = (event['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            _partialText = text;
            _state = VoiceAiState.processing;
            notifyListeners();
          }
        } else if (type == 'finalTranscript' || type == 'assistantReply') {
          final text = (event['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            _messages.add(
              ChatMessage(
                role: ChatRole.assistant,
                text: text,
                timestamp: DateTime.now(),
              ),
            );
            unawaited(_speakAssistantReply(text));
          }
          _partialText = '';
          notifyListeners();
        } else if (type == 'benchmark') {
          _benchmarks = BenchmarkMetrics.fromMap(event);
          notifyListeners();
        }
      }),
    ]);
  }

  Future<void> _speakAssistantReply(String text) async {
    if (!_voiceReplyEnabled) return;
    try {
      _isSpeaking = true;
      notifyListeners();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS failed: $e');
    } finally {
      _isSpeaking = false;
      try {
        notifyListeners();
      } catch (_) {}
    }
  }

  void toggleVoiceReply() {
    _voiceReplyEnabled = !_voiceReplyEnabled;
    if (!_voiceReplyEnabled) {
      unawaited(stopSpeaking());
    }
    notifyListeners();
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    if (!hasListeners && _state == VoiceAiState.disposed) return;
    _isSpeaking = false;
    // Avoid notify after dispose from fire-and-forget clear/dispose paths.
    try {
      notifyListeners();
    } catch (_) {}
  }

  void clearTranscript() {
    unawaited(_tts.stop());
    _isSpeaking = false;
    _partialText = '';
    _messages.clear();
    notifyListeners();
  }

  Future<void> replayLastAssistantReply() async {
    final lastAssistant = _messages.reversed.firstWhere(
      (m) => m.role == ChatRole.assistant,
      orElse: () => ChatMessage(
        role: ChatRole.assistant,
        text: '',
        timestamp: DateTime.now(),
      ),
    );
    if (lastAssistant.text.trim().isEmpty) return;
    await _speakAssistantReply(lastAssistant.text);
  }

  String _buildConversationContext() {
    if (_messages.isEmpty) return '';
    final recent = _messages.length <= 6
        ? _messages
        : _messages.sublist(_messages.length - 6);
    final buffer = StringBuffer('Recent conversation:\n');
    for (final message in recent) {
      final who = message.role == ChatRole.user ? 'User' : 'Assistant';
      buffer.writeln('$who: ${message.text}');
    }
    return buffer.toString();
  }

  Future<void> bootstrap() async {
    _state = VoiceAiState.initializing;
    _errorMessage = '';
    notifyListeners();

    try {
      await _tts.initialize();
      final compatibility = await _service.checkCompatibility();
      _supported = compatibility['supported'] as bool? ?? true;
      _lowMemoryWarning = compatibility['lowMemoryWarning'] as bool? ?? false;
      _compatibilityMessage =
          compatibility['message'] as String? ??
              (_supported
                  ? 'Device supports on-device AI'
                  : 'This device does not meet the minimum requirements for on-device voice AI.');
      if (!_supported) {
        _state = VoiceAiState.unsupportedDevice;
        notifyListeners();
        return;
      }

      _modelReady = await _downloadService.isModelReady();
      if (_modelReady) {
        await _initializeNativeWithLocalModel();
      } else {
        _state = VoiceAiState.uninitialized;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to initialize on-device AI.';
      _state = VoiceAiState.error;
      notifyListeners();
    }
  }

  Future<void> prepareModel() async {
    _errorMessage = '';
    _downloadProgress = 0;
    _state = VoiceAiState.modelDownloading;
    notifyListeners();

    try {
      await for (final progress in _downloadService.downloadModel(
        authToken: OnDeviceAiConfig.hfToken.isEmpty
            ? null
            : OnDeviceAiConfig.hfToken,
      )) {
        _downloadProgress = progress;
        notifyListeners();
      }
      _modelReady = await _downloadService.isModelReady();
      if (!_modelReady) {
        throw StateError('Model download incomplete.');
      }
      await _initializeNativeWithLocalModel();
    } catch (e) {
      _errorMessage = e is StateError
          ? e.message
          : 'Model download failed. Check network and Hugging Face access.';
      _state = VoiceAiState.error;
      notifyListeners();
    }
  }

  Future<void> _initializeNativeWithLocalModel() async {
    _state = VoiceAiState.modelLoading;
    notifyListeners();
    final file = await _downloadService.resolveLocalModelFile();
    await _service.initialize(modelPath: file.path);
    _benchmarks = await _service.getBenchmarkMetrics();
    _modelReady = true;
    _state = VoiceAiState.modelReady;
    notifyListeners();
  }

  Future<bool> _ensureMicPermission() async {
    _state = VoiceAiState.requestingPermission;
    notifyListeners();
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _errorMessage = 'Microphone permission is required.';
      _state = VoiceAiState.error;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> startListening() async {
    if (!_modelReady) {
      _errorMessage = 'On-device AI model is not ready.';
      _state = VoiceAiState.error;
      notifyListeners();
      return;
    }
    if (!await _ensureMicPermission()) return;

    await stopSpeaking();
    _partialText = '';
    _errorMessage = '';
    try {
      await _service.startListening();
      _state = VoiceAiState.listening;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopListening() async {
    final context = _buildConversationContext();
    _messages.add(
      ChatMessage(
        role: ChatRole.user,
        text: '🎤 Voice message',
        timestamp: DateTime.now(),
        isVoice: true,
      ),
    );
    _state = VoiceAiState.processing;
    notifyListeners();

    try {
      await _service.stopListening(conversationContext: context);
      _benchmarks = await _service.getBenchmarkMetrics();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> unloadModel() async {
    await stopSpeaking();
    await _service.unloadModel();
    _modelReady = false;
    _state = VoiceAiState.uninitialized;
    notifyListeners();
  }

  Future<void> refreshBenchmarks() async {
    _benchmarks = await _service.getBenchmarkMetrics();
    notifyListeners();
  }

  Future<void> markOfflineVerified() async {
    _offlineVerified = true;
    final dir = await getTemporaryDirectory();
    final marker = File('${dir.path}/offline_voice_ai_verified');
    await marker.writeAsString(DateTime.now().toIso8601String());
    notifyListeners();
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    unawaited(_tts.dispose());
    _downloadService.dispose();
    unawaited(_service.dispose());
    super.dispose();
  }
}
