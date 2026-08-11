class TranscriptModel {
  const TranscriptModel({
    required this.text,
    required this.isFinal,
    required this.timestamp,
    this.chunkIndex,
  });

  final String text;
  final bool isFinal;
  final DateTime timestamp;
  final int? chunkIndex;

  TranscriptModel copyWith({
    String? text,
    bool? isFinal,
    DateTime? timestamp,
    int? chunkIndex,
  }) {
    return TranscriptModel(
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      timestamp: timestamp ?? this.timestamp,
      chunkIndex: chunkIndex ?? this.chunkIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'isFinal': isFinal,
        'timestamp': timestamp.toIso8601String(),
        'chunkIndex': chunkIndex,
      };

  factory TranscriptModel.fromJson(Map<String, dynamic> json) {
    return TranscriptModel(
      text: json['text'] as String? ?? '',
      isFinal: json['isFinal'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      chunkIndex: json['chunkIndex'] as int?,
    );
  }

  @override
  String toString() =>
      'TranscriptModel(text: $text, isFinal: $isFinal, chunkIndex: $chunkIndex)';
}
