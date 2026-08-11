import 'package:flutter/material.dart';
import 'package:gemma_poc/features/voice_ai/controllers/voice_ai_controller.dart';
import 'package:gemma_poc/features/voice_ai/models/voice_ai_state.dart';
import 'package:gemma_poc/features/voice_ai/screens/voice_ai_benchmark_screen.dart';
import 'package:gemma_poc/features/voice_ai/widgets/conversation_view.dart';
import 'package:gemma_poc/features/voice_ai/widgets/microphone_button.dart';
import 'package:gemma_poc/features/voice_ai/widgets/model_download_view.dart';
import 'package:gemma_poc/features/voice_ai/widgets/offline_indicator.dart';
import 'package:gemma_poc/features/voice_ai/widgets/voice_status_view.dart';

class VoiceAiScreen extends StatefulWidget {
  const VoiceAiScreen({super.key});

  @override
  State<VoiceAiScreen> createState() => _VoiceAiScreenState();
}

class _VoiceAiScreenState extends State<VoiceAiScreen> {
  late final VoiceAiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VoiceAiController()..bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final c = _controller;
        final permissionDenied = c.errorMessage.contains('Microphone permission');

        return Scaffold(
          appBar: AppBar(
            title: const Text('Voice Assistant'),
            actions: [
              IconButton(
                tooltip: c.voiceReplyEnabled
                    ? 'Voice reply on'
                    : 'Voice reply off',
                onPressed: c.toggleVoiceReply,
                icon: Icon(
                  c.voiceReplyEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Replay last reply',
                onPressed: c.replayLastAssistantReply,
                icon: const Icon(Icons.replay_rounded),
              ),
              IconButton(
                tooltip: 'Benchmarks',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VoiceAiBenchmarkScreen(controller: c),
                    ),
                  );
                },
                icon: const Icon(Icons.speed),
              ),
              IconButton(
                tooltip: 'Clear conversation',
                onPressed: c.clearTranscript,
                icon: const Icon(Icons.clear_all),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  OfflineIndicator(ready: c.modelReady),
                  const SizedBox(height: 16),
                  VoiceStatusView(
                    state: c.state,
                    errorMessage: c.errorMessage,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (!c.supported) ...[
                            Text(
                              c.compatibilityMessage,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ] else if (!c.modelReady &&
                              c.state != VoiceAiState.modelLoading &&
                              c.state != VoiceAiState.initializing) ...[
                            if (c.lowMemoryWarning) ...[
                              Text(
                                c.compatibilityMessage,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                            ],
                            ModelDownloadView(
                              progress: c.downloadProgress,
                              isDownloading:
                                  c.state == VoiceAiState.modelDownloading,
                              onPrepare: c.prepareModel,
                            ),
                          ] else if (c.state == VoiceAiState.modelLoading ||
                              c.state == VoiceAiState.initializing) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(c.state.label),
                          ] else if (permissionDenied) ...[
                            const Text(
                              'Microphone permission is required.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: c.openAppSettingsPage,
                              child: const Text('Open Settings'),
                            ),
                          ] else ...[
                            ConversationView(
                              messages: c.messages,
                              isProcessing: c.state == VoiceAiState.processing,
                            ),
                            const SizedBox(height: 20),
                            MicrophoneButton(
                              state: c.state,
                              onStart: c.startListening,
                              onStop: c.stopListening,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (c.modelReady)
                    Text(
                      c.isSpeaking
                          ? '🔊 Speaking reply…'
                          : (c.voiceReplyEnabled
                              ? '✓ Text + voice reply on device'
                              : '✓ Text reply on device (voice muted)'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
