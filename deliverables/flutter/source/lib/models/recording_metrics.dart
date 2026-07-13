class RecordingMetrics {
  const RecordingMetrics({
    required this.duration,
    this.averageDb,
    this.peakDb,
  });

  final Duration duration;
  final double? averageDb;
  final double? peakDb;

  bool get hasVolumeData =>
      averageDb != null && averageDb!.isFinite && averageDb! > -120;
}
