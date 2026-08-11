import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gemma_poc/core/config/on_device_ai_config.dart';
import 'package:gemma_poc/features/voice_ai/controllers/voice_ai_controller.dart';

class VoiceAiBenchmarkScreen extends StatelessWidget {
  const VoiceAiBenchmarkScreen({super.key, required this.controller});

  final VoiceAiController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final b = controller.benchmarks;
        return Scaffold(
          appBar: AppBar(title: const Text('Voice AI Benchmarks')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _row('Model', b.modelId.isEmpty ? OnDeviceAiConfig.modelId : b.modelId),
              _row('Backend', b.backend.isEmpty ? '—' : b.backend),
              _row('Model Load', _ms(b.modelLoadMs)),
              _row('Audio Processing', _ms(b.audioProcessingMs)),
              _row('First Transcript', _ms(b.firstTranscriptMs)),
              _row('Average Inference', _ms(b.averageInferenceMs)),
              _row('RAM', b.ramMb == null ? '—' : '${b.ramMb!.toStringAsFixed(0)} MB'),
              _row('CPU', b.cpuPercent == null ? '—' : '${b.cpuPercent!.toStringAsFixed(0)}%'),
              _row('Chunks', '${b.chunkCount}'),
              _row('Battery', 'Monitoring…'),
              const Divider(height: 32),
              Text(
                'Architecture note',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Gemma 3n mobile audio is clip/chunk inference (not continuous '
                'ASR streaming). This screen reports measured chunk latency.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (kDebugMode) ...[
                FilledButton(
                  onPressed: controller.refreshBenchmarks,
                  child: const Text('Refresh Metrics'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: controller.markOfflineVerified,
                  child: Text(
                    controller.offlineVerified
                        ? 'Offline verified ✓'
                        : 'Mark Airplane Mode Verified',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _ms(int? value) => value == null ? '—' : '$value ms';

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
