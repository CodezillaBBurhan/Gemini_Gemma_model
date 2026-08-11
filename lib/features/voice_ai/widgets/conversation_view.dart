import 'package:flutter/material.dart';
import 'package:gemma_poc/features/voice_ai/models/chat_message.dart';

class ConversationView extends StatelessWidget {
  const ConversationView({
    super.key,
    required this.messages,
    this.isProcessing = false,
  });

  final List<ChatMessage> messages;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (messages.isEmpty && !isProcessing) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 180),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Start a voice conversation.\nSpeak, then tap Stop & Reply.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: messages.length + (isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (isProcessing && index == messages.length) {
          return const _Bubble(
            isUser: false,
            text: 'Thinking on device…',
            muted: true,
          );
        }
        final message = messages[index];
        return _Bubble(
          isUser: message.role == ChatRole.user,
          text: message.text,
          isVoice: message.isVoice,
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.isUser,
    required this.text,
    this.isVoice = false,
    this.muted = false,
  });

  final bool isUser;
  final String text;
  final bool isVoice;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? (isVoice ? 'You (voice)' : 'You') : 'Gemma',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                color: muted ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            if (!isUser && !muted) ...[
              const SizedBox(height: 6),
              Text(
                'Text + spoken aloud',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
