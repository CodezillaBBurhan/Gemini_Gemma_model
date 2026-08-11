class BenchmarkMetrics {
  const BenchmarkMetrics({
    this.modelId = '',
    this.backend = '',
    this.modelLoadMs,
    this.audioProcessingMs,
    this.firstTranscriptMs,
    this.averageInferenceMs,
    this.ramMb,
    this.cpuPercent,
    this.chunkCount = 0,
  });

  final String modelId;
  final String backend;
  final int? modelLoadMs;
  final int? audioProcessingMs;
  final int? firstTranscriptMs;
  final int? averageInferenceMs;
  final double? ramMb;
  final double? cpuPercent;
  final int chunkCount;

  BenchmarkMetrics copyWith({
    String? modelId,
    String? backend,
    int? modelLoadMs,
    int? audioProcessingMs,
    int? firstTranscriptMs,
    int? averageInferenceMs,
    double? ramMb,
    double? cpuPercent,
    int? chunkCount,
  }) {
    return BenchmarkMetrics(
      modelId: modelId ?? this.modelId,
      backend: backend ?? this.backend,
      modelLoadMs: modelLoadMs ?? this.modelLoadMs,
      audioProcessingMs: audioProcessingMs ?? this.audioProcessingMs,
      firstTranscriptMs: firstTranscriptMs ?? this.firstTranscriptMs,
      averageInferenceMs: averageInferenceMs ?? this.averageInferenceMs,
      ramMb: ramMb ?? this.ramMb,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      chunkCount: chunkCount ?? this.chunkCount,
    );
  }

  factory BenchmarkMetrics.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const BenchmarkMetrics();
    return BenchmarkMetrics(
      modelId: map['modelId'] as String? ?? '',
      backend: map['backend'] as String? ?? '',
      modelLoadMs: (map['modelLoadMs'] as num?)?.toInt(),
      audioProcessingMs: (map['audioProcessingMs'] as num?)?.toInt(),
      firstTranscriptMs: (map['firstTranscriptMs'] as num?)?.toInt(),
      averageInferenceMs: (map['averageInferenceMs'] as num?)?.toInt(),
      ramMb: (map['ramMb'] as num?)?.toDouble(),
      cpuPercent: (map['cpuPercent'] as num?)?.toDouble(),
      chunkCount: (map['chunkCount'] as num?)?.toInt() ?? 0,
    );
  }
}
