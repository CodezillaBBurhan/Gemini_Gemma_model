import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_poc/features/voice_ai/models/transcript_model.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';

void main() {
  test('TranscriptModel round-trips JSON', () {
    final original = TranscriptModel(
      text: 'hello',
      isFinal: true,
      timestamp: DateTime.parse('2026-08-11T10:00:00.000Z'),
      chunkIndex: 2,
    );
    final restored = TranscriptModel.fromJson(original.toJson());
    expect(restored.text, 'hello');
    expect(restored.isFinal, isTrue);
    expect(restored.chunkIndex, 2);
  });

  test('VoiceAiState helpers', () {
    expect(VoiceAiState.listening.isBusy, isTrue);
    expect(VoiceAiState.modelReady.canStartListening, isTrue);
    expect(VoiceAiState.error.label, 'Error');
  });
}
