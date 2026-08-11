import 'package:flutter/material.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';

class MicrophoneButton extends StatelessWidget {
  const MicrophoneButton({
    super.key,
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final VoiceAiState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  bool get _listening => state == VoiceAiState.listening;
  bool get _processing => state == VoiceAiState.processing;

  @override
  Widget build(BuildContext context) {
    final color = _listening
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Material(
          color: color.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _processing ? null : (_listening ? onStop : onStart),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: _listening ? 108 : 96,
              height: _listening ? 108 : 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: _processing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 42,
                      color: color,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _processing
              ? 'Processing reply…'
              : (_listening ? 'Stop & Reply' : 'Start Listening'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (_listening) ...[
          const SizedBox(height: 8),
          Text(
            'Ask Gemma something, then tap Stop & Reply',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
