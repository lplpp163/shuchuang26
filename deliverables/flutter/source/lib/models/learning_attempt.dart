import 'family_story.dart';

class LearningAttempt {
  const LearningAttempt({
    required this.id,
    required this.storyId,
    required this.createdAt,
    required this.result,
    this.audioPath,
    this.childNote,
    this.familyCorrection,
    this.reviewedAt,
    this.recordingDurationMs,
    this.averageAmplitudeDb,
    this.coachSummary,
    this.coachMode,
  });

  final String id;
  final String storyId;
  final DateTime createdAt;
  final ReviewResult result;
  final String? audioPath;
  final String? childNote;
  final String? familyCorrection;
  final DateTime? reviewedAt;
  final int? recordingDurationMs;
  final double? averageAmplitudeDb;
  final String? coachSummary;
  final String? coachMode;

  LearningAttempt copyWith({
    ReviewResult? result,
    String? familyCorrection,
    DateTime? reviewedAt,
  }) {
    return LearningAttempt(
      id: id,
      storyId: storyId,
      createdAt: createdAt,
      result: result ?? this.result,
      audioPath: audioPath,
      childNote: childNote,
      familyCorrection: familyCorrection ?? this.familyCorrection,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      recordingDurationMs: recordingDurationMs,
      averageAmplitudeDb: averageAmplitudeDb,
      coachSummary: coachSummary,
      coachMode: coachMode,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'storyId': storyId,
        'createdAt': createdAt.toIso8601String(),
        'result': result.name,
        'audioPath': audioPath,
        'childNote': childNote,
        'familyCorrection': familyCorrection,
        'reviewedAt': reviewedAt?.toIso8601String(),
        'recordingDurationMs': recordingDurationMs,
        'averageAmplitudeDb': averageAmplitudeDb,
        'coachSummary': coachSummary,
        'coachMode': coachMode,
      };

  factory LearningAttempt.fromJson(Map<String, Object?> json) {
    return LearningAttempt(
      id: json['id']! as String,
      storyId: json['storyId']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      result: ReviewResult.values.byName(json['result']! as String),
      audioPath: json['audioPath'] as String?,
      childNote: json['childNote'] as String?,
      familyCorrection: json['familyCorrection'] as String?,
      reviewedAt: json['reviewedAt'] == null
          ? null
          : DateTime.parse(json['reviewedAt']! as String),
      recordingDurationMs: json['recordingDurationMs'] as int?,
      averageAmplitudeDb: (json['averageAmplitudeDb'] as num?)?.toDouble(),
      coachSummary: json['coachSummary'] as String?,
      coachMode: json['coachMode'] as String?,
    );
  }
}
