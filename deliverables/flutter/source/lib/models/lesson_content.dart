class LessonAudio {
  const LessonAudio({
    this.path,
    this.startMs,
    this.endMs,
  });

  final String? path;
  final int? startMs;
  final int? endMs;

  bool get hasValidRange =>
      startMs != null && endMs != null && startMs! >= 0 && endMs! > startMs!;

  Map<String, Object?> toJson({bool includePath = true}) => {
        if (includePath) 'path': path,
        'startMs': startMs,
        'endMs': endMs,
      };

  factory LessonAudio.fromJson(Map<String, Object?> json) => LessonAudio(
        path: json['path'] as String?,
        startMs: (json['startMs'] as num?)?.round(),
        endMs: (json['endMs'] as num?)?.round(),
      );
}

class LessonSegment {
  const LessonSegment({
    required this.id,
    required this.text,
    required this.tokens,
    required this.translationZh,
    required this.romanization,
    this.wordBreakdownZh,
    this.pronunciationTipsZh = const [],
    this.audio,
  });

  final String id;
  final String text;
  final List<String> tokens;
  final String translationZh;
  final String romanization;
  final String? wordBreakdownZh;
  final List<String> pronunciationTipsZh;
  final LessonAudio? audio;

  Map<String, Object?> toJson({bool includeAudioPaths = true}) => {
        'id': id,
        'text': text,
        'tokens': tokens,
        'translationZh': translationZh,
        'romanization': romanization,
        'wordBreakdownZh': wordBreakdownZh,
        'pronunciationTipsZh': pronunciationTipsZh,
        'audio': audio?.toJson(includePath: includeAudioPaths),
      };

  factory LessonSegment.fromJson(Map<String, Object?> json) => LessonSegment(
        id: json['id']! as String,
        text: json['text']! as String,
        tokens: (json['tokens'] as List<Object?>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        translationZh: json['translationZh']! as String,
        romanization: json['romanization']! as String,
        wordBreakdownZh: json['wordBreakdownZh'] as String?,
        pronunciationTipsZh: (json['pronunciationTipsZh'] as List<Object?>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        audio: json['audio'] is Map
            ? LessonAudio.fromJson(
                Map<String, Object?>.from(
                  json['audio']! as Map<Object?, Object?>,
                ),
              )
            : null,
      );
}

class LessonExample {
  const LessonExample({
    required this.targetText,
    required this.translationZh,
    this.romanization,
    this.emoji,
    this.audio,
  });

  final String targetText;
  final String translationZh;
  final String? romanization;
  final String? emoji;
  final LessonAudio? audio;

  Map<String, Object?> toJson({bool includeAudioPaths = true}) => {
        'targetText': targetText,
        'translationZh': translationZh,
        'romanization': romanization,
        'emoji': emoji,
        'audio': audio?.toJson(includePath: includeAudioPaths),
      };

  factory LessonExample.fromJson(Map<String, Object?> json) => LessonExample(
        targetText: json['targetText']! as String,
        translationZh: json['translationZh']! as String,
        romanization: json['romanization'] as String?,
        emoji: json['emoji'] as String?,
        audio: json['audio'] is Map
            ? LessonAudio.fromJson(
                Map<String, Object?>.from(
                  json['audio']! as Map<Object?, Object?>,
                ),
              )
            : null,
      );
}

class SentencePattern {
  const SentencePattern({
    required this.id,
    required this.template,
    required this.meaningZh,
    required this.examples,
    this.usageTipZh,
  });

  final String id;
  final String template;
  final String meaningZh;
  final String? usageTipZh;
  final List<LessonExample> examples;

  Map<String, Object?> toJson({bool includeAudioPaths = true}) => {
        'id': id,
        'template': template,
        'meaningZh': meaningZh,
        'usageTipZh': usageTipZh,
        'examples': examples
            .map((example) => example.toJson(
                  includeAudioPaths: includeAudioPaths,
                ))
            .toList(growable: false),
      };

  factory SentencePattern.fromJson(Map<String, Object?> json) =>
      SentencePattern(
        id: json['id']! as String,
        template: json['template']! as String,
        meaningZh: json['meaningZh']! as String,
        usageTipZh: json['usageTipZh'] as String?,
        examples: (json['examples'] as List<Object?>?)
                ?.whereType<Map>()
                .map(
                  (value) => LessonExample.fromJson(
                    Map<String, Object?>.from(value),
                  ),
                )
                .toList(growable: false) ??
            const [],
      );
}

class LessonContent {
  const LessonContent({
    required this.schemaVersion,
    required this.languageTag,
    required this.romanizationSystem,
    required this.segments,
    required this.patterns,
    this.sentenceRomanization,
    this.coachIntroZh,
    this.memoryTipZh,
    this.targetDurationMs,
  });

  final int schemaVersion;
  final String languageTag;
  final String romanizationSystem;
  final String? sentenceRomanization;
  final String? coachIntroZh;
  final String? memoryTipZh;
  final int? targetDurationMs;
  final List<LessonSegment> segments;
  final List<SentencePattern> patterns;

  Map<String, Object?> toJson({bool includeAudioPaths = true}) => {
        'schemaVersion': schemaVersion,
        'languageTag': languageTag,
        'romanizationSystem': romanizationSystem,
        'sentenceRomanization': sentenceRomanization,
        'coachIntroZh': coachIntroZh,
        'memoryTipZh': memoryTipZh,
        'targetDurationMs': targetDurationMs,
        'segments': segments
            .map((segment) => segment.toJson(
                  includeAudioPaths: includeAudioPaths,
                ))
            .toList(growable: false),
        'patterns': patterns
            .map((pattern) => pattern.toJson(
                  includeAudioPaths: includeAudioPaths,
                ))
            .toList(growable: false),
      };

  factory LessonContent.fromJson(Map<String, Object?> json) => LessonContent(
        schemaVersion: (json['schemaVersion'] as num?)?.round() ?? 1,
        languageTag: json['languageTag']! as String,
        romanizationSystem: json['romanizationSystem']! as String,
        sentenceRomanization: json['sentenceRomanization'] as String?,
        coachIntroZh: json['coachIntroZh'] as String?,
        memoryTipZh: json['memoryTipZh'] as String?,
        targetDurationMs: (json['targetDurationMs'] as num?)?.round(),
        segments: (json['segments'] as List<Object?>?)
                ?.whereType<Map>()
                .map(
                  (value) => LessonSegment.fromJson(
                    Map<String, Object?>.from(value),
                  ),
                )
                .toList(growable: false) ??
            const [],
        patterns: (json['patterns'] as List<Object?>?)
                ?.whereType<Map>()
                .map(
                  (value) => SentencePattern.fromJson(
                    Map<String, Object?>.from(value),
                  ),
                )
                .toList(growable: false) ??
            const [],
      );
}

class FamilyChallenge {
  const FamilyChallenge({
    required this.promptZh,
    required this.correctChoiceZh,
    required this.distractorsZh,
    required this.successMessageZh,
    required this.cultureNoteZh,
    this.sceneTitleZh = '生活任務',
    this.listeningPromptZh,
    this.dialoguePromptZh,
    this.correctEmoji = '✨',
    this.distractorEmojis = const [],
    this.hotspots = const [],
  });

  final String promptZh;
  final String correctChoiceZh;
  final List<String> distractorsZh;
  final String successMessageZh;
  final String cultureNoteZh;
  final String sceneTitleZh;
  final String? listeningPromptZh;
  final String? dialoguePromptZh;
  final String correctEmoji;
  final List<String> distractorEmojis;
  final List<ChallengeHotspot> hotspots;

  List<String> get choices => [correctChoiceZh, ...distractorsZh];

  String emojiForChoice(String choice) {
    if (choice == correctChoiceZh) return correctEmoji;
    final index = distractorsZh.indexOf(choice);
    if (index >= 0 && index < distractorEmojis.length) {
      return distractorEmojis[index];
    }
    return '❓';
  }

  Map<String, Object?> toJson() => {
        'promptZh': promptZh,
        'correctChoiceZh': correctChoiceZh,
        'distractorsZh': distractorsZh,
        'successMessageZh': successMessageZh,
        'cultureNoteZh': cultureNoteZh,
        'sceneTitleZh': sceneTitleZh,
        'listeningPromptZh': listeningPromptZh,
        'dialoguePromptZh': dialoguePromptZh,
        'correctEmoji': correctEmoji,
        'distractorEmojis': distractorEmojis,
        'hotspots': hotspots.map((spot) => spot.toJson()).toList(),
      };

  factory FamilyChallenge.fromJson(Map<String, Object?> json) =>
      FamilyChallenge(
        promptZh: json['promptZh']! as String,
        correctChoiceZh: json['correctChoiceZh']! as String,
        distractorsZh: (json['distractorsZh'] as List<Object?>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        successMessageZh: json['successMessageZh']! as String,
        cultureNoteZh: json['cultureNoteZh']! as String,
        sceneTitleZh: json['sceneTitleZh'] as String? ?? '生活任務',
        listeningPromptZh: json['listeningPromptZh'] as String?,
        dialoguePromptZh: json['dialoguePromptZh'] as String?,
        correctEmoji: json['correctEmoji'] as String? ?? '✨',
        distractorEmojis: (json['distractorEmojis'] as List<Object?>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        hotspots: (json['hotspots'] as List<Object?>?)
                ?.whereType<Map>()
                .map(
                  (value) => ChallengeHotspot.fromJson(
                    Map<String, Object?>.from(value),
                  ),
                )
                .toList(growable: false) ??
            const [],
      );
}

class ChallengeHotspot {
  const ChallengeHotspot({
    required this.labelZh,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.hintZh,
  });

  final String labelZh;
  final double left;
  final double top;
  final double width;
  final double height;
  final String hintZh;

  Map<String, Object?> toJson() => {
        'labelZh': labelZh,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'hintZh': hintZh,
      };

  factory ChallengeHotspot.fromJson(Map<String, Object?> json) =>
      ChallengeHotspot(
        labelZh: json['labelZh']! as String,
        left: (json['left']! as num).toDouble(),
        top: (json['top']! as num).toDouble(),
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
        hintZh: json['hintZh']! as String,
      );
}
