import 'package:flutter/material.dart';

class ModelDownloadView extends StatelessWidget {
  const ModelDownloadView({
    super.key,
    required this.progress,
    required this.onPrepare,
    this.isDownloading = false,
  });

  final double progress;
  final VoidCallback onPrepare;
  final bool isDownloading;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Column(
      children: [
        Text(
          isDownloading
              ? 'AI Model\nDownloading: $percent%'
              : 'On-device AI model is not ready.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (isDownloading) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Do not close the app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else
          FilledButton(
            onPressed: onPrepare,
            child: const Text('Prepare Model'),
          ),
      ],
    );
  }
}
