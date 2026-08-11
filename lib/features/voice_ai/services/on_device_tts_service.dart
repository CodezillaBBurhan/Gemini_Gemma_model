import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// On-device speech synthesis via OS TTS engines (Android/iOS).
/// No cloud APIs — works offline after language voices are installed on the device.
class OnDeviceTtsService {
  OnDeviceTtsService({FlutterTts? tts}) : _tts = tts;

  FlutterTts? _tts;
  bool _ready = false;
  bool _speaking = false;
  bool _unavailable = false;

  bool get isSpeaking => _speaking;
  bool get isAvailable => !_unavailable;

  FlutterTts get _engine => _tts ??= FlutterTts();

  Future<void> initialize() async {
    if (_ready || _unavailable) return;
    try {
      final tts = _engine;
      await tts.setSpeechRate(0.48);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);

      tts.setStartHandler(() {
        _speaking = true;
      });
      tts.setCompletionHandler(() {
        _speaking = false;
      });
      tts.setCancelHandler(() {
        _speaking = false;
      });
      tts.setErrorHandler((_) {
        _speaking = false;
      });

      try {
        await tts.setLanguage('en-US');
      } catch (_) {}

      _ready = true;
    } catch (e) {
      debugPrint('On-device TTS unavailable: $e');
      _unavailable = true;
      _ready = false;
    }
  }

  Future<void> speak(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || _unavailable) return;
    await initialize();
    if (_unavailable || !_ready) return;
    await stop();
    _speaking = true;
    try {
      await _engine.speak(cleaned);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      _speaking = false;
    }
  }

  Future<void> stop() async {
    if (!_ready) {
      _speaking = false;
      return;
    }
    try {
      await _engine.stop();
    } catch (_) {}
    _speaking = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}

/// No-op TTS used by unit tests.
class FakeOnDeviceTtsService extends OnDeviceTtsService {
  FakeOnDeviceTtsService() : super(tts: null);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
