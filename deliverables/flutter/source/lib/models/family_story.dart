import 'lesson_content.dart';

enum ReviewResult { pending, understood, almost, familyVersion }

extension ReviewResultLabel on ReviewResult {
  String get zhLabel => switch (this) {
        ReviewResult.pending => '等家人聽',
        ReviewResult.understood => '我聽懂了',
        ReviewResult.almost => '再試一次',
        ReviewResult.familyVersion => '我們家會這樣說',
      };
}

class FamilyStory {
  const FamilyStory({
    required this.id,
    required this.title,
    required this.objectName,
    required this.vietnamese,
    required this.chinese,
    required this.promptZh,
    required this.promptVi,
    required this.keyPhrases,
    required this.draftConfidence,
    required this.humanConfirmed,
    required this.createdAt,
    this.audioPath,
    this.photoPath,
    this.isSample = false,
    this.languageName = '越南語',
    this.languageTag,
    this.pronunciationGuide,
    this.pronunciationSystem = '羅馬字分詞',
    this.practiceChunks = const [],
    this.illustrationAsset,
    this.expectedDurationSeconds,
    this.lessonContent,
    this.familyChallenge,
    this.originStoryIdeaId,
    this.originStoryIdeaTitle,
  });

  final String id;
  final String title;
  final String objectName;
  final String vietnamese;
  final String chinese;
  final String promptZh;
  final String promptVi;
  final List<String> keyPhrases;
  final double draftConfidence;
  final bool humanConfirmed;
  final DateTime createdAt;
  final String? audioPath;
  final String? photoPath;
  final bool isSample;
  final String languageName;
  final String? languageTag;
  final String? pronunciationGuide;
  final String pronunciationSystem;
  final List<String> practiceChunks;
  final String? illustrationAsset;
  final double? expectedDurationSeconds;
  final LessonContent? lessonContent;
  final FamilyChallenge? familyChallenge;

  /// Optional provenance for a child-selected daily story seed.
  ///
  /// This lets the library show an honest, local-only story passport without
  /// treating a one-sentence family mission as a finished built-in episode.
  final String? originStoryIdeaId;
  final String? originStoryIdeaTitle;

  String get targetText => vietnamese;
  String get translationZh => chinese;
  String get effectiveLanguageTag =>
      lessonContent?.languageTag ??
      languageTag ??
      switch (languageName) {
        '越南語' => 'vi-VN',
        '臺灣台語' => 'nan-TW',
        '客語' => 'hak-TW',
        _ => 'und',
      };
  List<String> get effectivePracticeChunks =>
      lessonContent?.segments.map((segment) => segment.text).toList() ??
      (practiceChunks.isNotEmpty
          ? practiceChunks
          : keyPhrases.isNotEmpty
              ? keyPhrases
              : [vietnamese]);
  String? get effectivePronunciation =>
      lessonContent?.sentenceRomanization ?? pronunciationGuide;
  int? get effectiveTargetDurationMs =>
      lessonContent?.targetDurationMs ??
      (expectedDurationSeconds == null
          ? null
          : (expectedDurationSeconds! * 1000).round());

  bool get needsHumanReview => !humanConfirmed;
  String get shareCode => 'HT-${id.toUpperCase()}';
  String get deepLink => 'hometongue://story/$id';

  FamilyStory copyWith({
    String? title,
    String? objectName,
    String? vietnamese,
    String? chinese,
    String? promptZh,
    String? promptVi,
    List<String>? keyPhrases,
    double? draftConfidence,
    bool? humanConfirmed,
    String? audioPath,
    String? photoPath,
    String? languageName,
    String? languageTag,
    String? pronunciationGuide,
    String? pronunciationSystem,
    List<String>? practiceChunks,
    String? illustrationAsset,
    double? expectedDurationSeconds,
    LessonContent? lessonContent,
    FamilyChallenge? familyChallenge,
    String? originStoryIdeaId,
    String? originStoryIdeaTitle,
  }) {
    return FamilyStory(
      id: id,
      title: title ?? this.title,
      objectName: objectName ?? this.objectName,
      vietnamese: vietnamese ?? this.vietnamese,
      chinese: chinese ?? this.chinese,
      promptZh: promptZh ?? this.promptZh,
      promptVi: promptVi ?? this.promptVi,
      keyPhrases: keyPhrases ?? this.keyPhrases,
      draftConfidence: draftConfidence ?? this.draftConfidence,
      humanConfirmed: humanConfirmed ?? this.humanConfirmed,
      createdAt: createdAt,
      audioPath: audioPath ?? this.audioPath,
      photoPath: photoPath ?? this.photoPath,
      isSample: isSample,
      languageName: languageName ?? this.languageName,
      languageTag: languageTag ?? this.languageTag,
      pronunciationGuide: pronunciationGuide ?? this.pronunciationGuide,
      pronunciationSystem: pronunciationSystem ?? this.pronunciationSystem,
      practiceChunks: practiceChunks ?? this.practiceChunks,
      illustrationAsset: illustrationAsset ?? this.illustrationAsset,
      expectedDurationSeconds:
          expectedDurationSeconds ?? this.expectedDurationSeconds,
      lessonContent: lessonContent ?? this.lessonContent,
      familyChallenge: familyChallenge ?? this.familyChallenge,
      originStoryIdeaId: originStoryIdeaId ?? this.originStoryIdeaId,
      originStoryIdeaTitle: originStoryIdeaTitle ?? this.originStoryIdeaTitle,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'objectName': objectName,
        'vietnamese': vietnamese,
        'chinese': chinese,
        'promptZh': promptZh,
        'promptVi': promptVi,
        'keyPhrases': keyPhrases,
        'draftConfidence': draftConfidence,
        'humanConfirmed': humanConfirmed,
        'createdAt': createdAt.toIso8601String(),
        'audioPath': audioPath,
        'photoPath': photoPath,
        'isSample': isSample,
        'languageName': languageName,
        'languageTag': languageTag,
        'pronunciationGuide': pronunciationGuide,
        'pronunciationSystem': pronunciationSystem,
        'practiceChunks': practiceChunks,
        'illustrationAsset': illustrationAsset,
        'expectedDurationSeconds': expectedDurationSeconds,
        'lessonContent': lessonContent?.toJson(),
        'familyChallenge': familyChallenge?.toJson(),
        'originStoryIdeaId': originStoryIdeaId,
        'originStoryIdeaTitle': originStoryIdeaTitle,
      };

  factory FamilyStory.fromJson(Map<String, Object?> json) {
    return FamilyStory(
      id: json['id']! as String,
      title: json['title']! as String,
      objectName: json['objectName']! as String,
      vietnamese: json['vietnamese']! as String,
      chinese: json['chinese']! as String,
      promptZh: json['promptZh']! as String,
      promptVi: json['promptVi']! as String,
      keyPhrases: (json['keyPhrases']! as List<Object?>).cast<String>(),
      draftConfidence: (json['draftConfidence']! as num).toDouble(),
      humanConfirmed: json['humanConfirmed']! as bool,
      createdAt: DateTime.parse(json['createdAt']! as String),
      audioPath: json['audioPath'] as String?,
      photoPath: json['photoPath'] as String?,
      isSample: json['isSample'] as bool? ?? false,
      languageName: json['languageName'] as String? ?? '越南語',
      languageTag: json['languageTag'] as String?,
      pronunciationGuide: json['pronunciationGuide'] as String?,
      pronunciationSystem: json['pronunciationSystem'] as String? ?? '羅馬字分詞',
      practiceChunks: (json['practiceChunks'] as List<Object?>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      illustrationAsset: json['illustrationAsset'] as String?,
      expectedDurationSeconds:
          (json['expectedDurationSeconds'] as num?)?.toDouble(),
      lessonContent: _readLessonContent(json['lessonContent']),
      familyChallenge: _readFamilyChallenge(json['familyChallenge']),
      originStoryIdeaId: json['originStoryIdeaId'] as String?,
      originStoryIdeaTitle: json['originStoryIdeaTitle'] as String?,
    );
  }
}

FamilyChallenge? _readFamilyChallenge(Object? value) {
  if (value is! Map) return null;
  try {
    return FamilyChallenge.fromJson(Map<String, Object?>.from(value));
  } on Object {
    return null;
  }
}

LessonContent? _readLessonContent(Object? value) {
  if (value is! Map) return null;
  try {
    return LessonContent.fromJson(Map<String, Object?>.from(value));
  } on Object {
    // A damaged optional lesson must not make the family story disappear.
    return null;
  }
}
