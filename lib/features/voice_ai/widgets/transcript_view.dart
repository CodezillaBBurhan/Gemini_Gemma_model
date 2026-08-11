import 'package:flutter/material.dart';

class TranscriptView extends StatelessWidget {
  const TranscriptView({
    super.key,
    required this.text,
    this.isProcessing = false,
  });

  final String text;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: text.isEmpty
          ? Text(
              isProcessing
                  ? 'Listening for speech…'
                  : 'Transcript will appear here.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : SelectableText(
              text,
              style: theme.textTheme.titleMedium?.copyWith(height: 1.45),
            ),
    );
  }
}
