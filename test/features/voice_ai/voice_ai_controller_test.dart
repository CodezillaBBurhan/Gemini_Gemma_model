import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_poc/features/voice_ai/controllers/voice_ai_controller.dart';
import 'package:gemma_poc/features/voice_ai/models/benchmark_metrics.dart';
import 'package:gemma_poc/features/voice_ai/models/chat_message.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';
import 'package:gemma_poc/features/voice_ai/services/model_download_service.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_tts_service.dart';
import 'package:gemma_poc/features/voice_ai/services/on_device_voice_ai_service.dart';

class FakeService implements OnDeviceVoiceAiService {
  final transcriptController = StreamController<String>.broadcast();
  final stateController = StreamController<VoiceAiState>.broadcast();
  final downloadController = StreamController<double>.broadcast();
  final errorController = StreamController<String>.broadcast();
  final eventController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<String> get transcriptStream => transcriptController.stream;

  @override
  Stream<VoiceAiState> get stateStream => stateController.stream;

  @override
  Stream<double> get downloadProgressStream => downloadController.stream;

  @override
  Stream<String> get errorStream => errorController.stream;

  @override
  Stream<Map<String, dynamic>> get eventStream => eventController.stream;

  @override
  Future<Map<String, dynamic>> checkCompatibility() async => {
        'supported': true,
        'message': 'Device supports on-device AI',
      };

  @override
  Future<void> initialize({String? modelPath, String? backend}) async {
    stateController.add(VoiceAiState.modelReady);
  }

  @override
  Future<void> prepareModel({
    required String downloadUrl,
    String? authToken,
  }) async {}

  @override
  Future<void> startListening() async {
    stateController.add(VoiceAiState.listening);
  }

  @override
  Future<void> stopListening({String? conversationContext}) async {
    stateController.add(VoiceAiState.completed);
  }

  @override
  Future<void> unloadModel() async {
    stateController.add(VoiceAiState.uninitialized);
  }

  @override
  Future<BenchmarkMetrics> getBenchmarkMetrics() async =>
      const BenchmarkMetrics(modelId: 'gemma-3n-E2B-it-int4', backend: 'cpu');

  @override
  Future<void> dispose() async {
    await transcriptController.close();
    await stateController.close();
    await downloadController.close();
    await errorController.close();
    await eventController.close();
  }
}

class FakeDownload extends ModelDownloadService {
  FakeDownload({this.ready = false, File? file}) : _file = file;

  bool ready;
  final File? _file;

  @override
  Future<bool> isModelReady() async => ready;

  @override
  Future<File> resolveLocalModelFile() async {
    return _file ?? File('${Directory.systemTemp.path}/fake-model.litertlm');
  }

  @override
  Stream<double> downloadModel({String? url, String? authToken}) async* {
    yield 0.5;
    yield 1.0;
    ready = true;
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assistant reply is appended to conversation', () async {
    final service = FakeService();
    final controller = VoiceAiController(
      service: service,
      downloadService: FakeDownload(),
      ttsService: FakeOnDeviceTtsService(),
    );

    service.eventController.add({
      'type': 'assistantReply',
      'text': 'I can help you book a cab.',
      'isFinal': true,
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.length, 1);
    expect(controller.messages.first.role, ChatRole.assistant);
    expect(controller.messages.first.text, contains('book a cab'));
    controller.dispose();
  });

  test('error stream surfaces user-friendly state', () async {
    final service = FakeService();
    final controller = VoiceAiController(
      service: service,
      downloadService: FakeDownload(),
      ttsService: FakeOnDeviceTtsService(),
    );

    service.errorController.add('Microphone permission is required.');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, VoiceAiState.error);
    expect(controller.errorMessage, contains('Microphone'));
    controller.dispose();
  });

  test('clearTranscript resets conversation', () async {
    final service = FakeService();
    final controller = VoiceAiController(
      service: service,
      downloadService: FakeDownload(),
      ttsService: FakeOnDeviceTtsService(),
    );

    service.eventController.add({
      'type': 'assistantReply',
      'text': 'Hello there',
      'isFinal': true,
    });
    await Future<void>.delayed(Duration.zero);
    controller.clearTranscript();
    expect(controller.messages, isEmpty);
    controller.dispose();
  });

  test('bootstrap marks unsupported devices', () async {
    final service = UnsupportedFakeService();
    final controller = VoiceAiController(
      service: service,
      downloadService: FakeDownload(),
      ttsService: FakeOnDeviceTtsService(),
    );

    await controller.bootstrap();
    expect(controller.supported, isFalse);
    expect(controller.state, VoiceAiState.unsupportedDevice);
    controller.dispose();
  });
}

class UnsupportedFakeService extends FakeService {
  @override
  Future<Map<String, dynamic>> checkCompatibility() async => {
        'supported': false,
        'message':
            'This device does not meet the minimum requirements for on-device voice AI.',
      };
}
