import 'package:flutter/material.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key, this.ready = true});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF1B7F4C) : const Color(0xFF8A6D3B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.cloud_off,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            ready ? 'On-device AI' : 'Model not ready',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
