enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.isVoice = false,
  });

  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final bool isVoice;

  ChatMessage copyWith({String? text}) {
    return ChatMessage(
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      isVoice: isVoice,
    );
  }
}
