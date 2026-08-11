import 'package:flutter/material.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';

class VoiceStatusView extends StatelessWidget {
  const VoiceStatusView({
    super.key,
    required this.state,
    this.errorMessage = '',
  });

  final VoiceAiState state;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = state == VoiceAiState.error;
    return Column(
      children: [
        Text(
          isError && errorMessage.isNotEmpty ? errorMessage : state.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: isError ? theme.colorScheme.error : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Badge(icon: Icons.phonelink_lock, label: 'Processing on device'),
            SizedBox(width: 12),
            _Badge(icon: Icons.wifi_off, label: 'No internet required'),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
