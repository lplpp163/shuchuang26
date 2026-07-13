class TaskDraft {
  const TaskDraft({
    required this.promptZh,
    required this.promptVi,
    required this.keyPhrases,
    required this.confidence,
    required this.explanation,
  });

  final String promptZh;
  final String promptVi;
  final List<String> keyPhrases;
  final double confidence;
  final String explanation;

  bool get requiresHumanReview => confidence < 0.78;
}
