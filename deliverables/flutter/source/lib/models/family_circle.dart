import 'conversation_episode.dart' as theater;

enum FamilySticker { heart, clap, hug, laugh, proud }

extension FamilyStickerPresentation on FamilySticker {
  String get emoji => switch (this) {
        FamilySticker.heart => '❤️',
        FamilySticker.clap => '👏',
        FamilySticker.hug => '🫶',
        FamilySticker.laugh => '😄',
        FamilySticker.proud => '🌟',
      };

  String get zhLabel => switch (this) {
        FamilySticker.heart => '好喜歡',
        FamilySticker.clap => '拍拍手',
        FamilySticker.hug => '抱一個',
        FamilySticker.laugh => '好開心',
        FamilySticker.proud => '以你為榮',
      };
}

enum StoryContinuationKind { nextLine, familyNote }

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.relationship,
    required this.nickname,
    required this.isAdult,
    required this.avatarEmoji,
    required this.roleColorValue,
    required this.createdAt,
    this.approvedAt,
    this.approvedByMemberId,
  });

  final String id;

  /// 家庭關係稱謂，例如「外婆」、「孫女」。
  final String relationship;

  /// 孩子在場景中看到的稱呼，例如「阿嬤」。
  final String nickname;
  final bool isAdult;
  final String avatarEmoji;

  /// Flutter `Color` 可直接使用的 ARGB 整數，例如 `0xFFFF8A65`。
  final int roleColorValue;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedByMemberId;

  bool get isApproved => approvedAt != null;

  FamilyMember approve({
    required String approvedByMemberId,
    required DateTime approvedAt,
  }) {
    return FamilyMember(
      id: id,
      relationship: relationship,
      nickname: nickname,
      isAdult: isAdult,
      avatarEmoji: avatarEmoji,
      roleColorValue: roleColorValue,
      createdAt: createdAt,
      approvedAt: approvedAt,
      approvedByMemberId: approvedByMemberId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'relationship': relationship,
        'nickname': nickname,
        'isAdult': isAdult,
        'avatarEmoji': avatarEmoji,
        'roleColorValue': roleColorValue,
        'createdAt': createdAt.toIso8601String(),
        'approvedAt': approvedAt?.toIso8601String(),
        'approvedByMemberId': approvedByMemberId,
      };

  factory FamilyMember.fromJson(Map<String, Object?> json) {
    return FamilyMember(
      id: _requiredString(json, 'id'),
      relationship: _requiredString(json, 'relationship'),
      nickname: _requiredString(json, 'nickname'),
      isAdult: _requiredBool(json, 'isAdult'),
      avatarEmoji: _requiredString(json, 'avatarEmoji'),
      roleColorValue: _requiredInt(json, 'roleColorValue'),
      createdAt: _requiredDate(json, 'createdAt'),
      approvedAt: _optionalDate(json, 'approvedAt'),
      approvedByMemberId: _optionalString(json, 'approvedByMemberId'),
    );
  }
}

class FamilyStickerReaction {
  const FamilyStickerReaction({
    required this.memberId,
    required this.sticker,
    required this.createdAt,
  });

  final String memberId;
  final FamilySticker sticker;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'sticker': sticker.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FamilyStickerReaction.fromJson(Map<String, Object?> json) {
    return FamilyStickerReaction(
      memberId: _requiredString(json, 'memberId'),
      sticker: _enumByName(
        FamilySticker.values,
        _requiredString(json, 'sticker'),
        'sticker',
      ),
      createdAt: _requiredDate(json, 'createdAt'),
    );
  }
}

class AdultStoryContinuation {
  const AdultStoryContinuation({
    required this.id,
    required this.adultMemberId,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.localRecordingReference,
  });

  final String id;
  final String adultMemberId;
  final StoryContinuationKind kind;
  final String text;
  final DateTime createdAt;
  final String? localRecordingReference;

  Map<String, Object?> toJson({bool includeLocalRecordingReference = true}) => {
        'id': id,
        'adultMemberId': adultMemberId,
        'kind': kind.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'localRecordingReference':
            includeLocalRecordingReference ? localRecordingReference : null,
      };

  factory AdultStoryContinuation.fromJson(Map<String, Object?> json) {
    final storedKind = _requiredString(json, 'kind');
    return AdultStoryContinuation(
      id: _requiredString(json, 'id'),
      adultMemberId: _requiredString(json, 'adultMemberId'),
      // Older local prototypes called this a next-episode prompt even though
      // it was only a family note. Preserve those backups without repeating
      // that claim in the current model or UI.
      kind: storedKind == 'nextEpisodePrompt'
          ? StoryContinuationKind.familyNote
          : _enumByName(StoryContinuationKind.values, storedKind, 'kind'),
      text: _requiredString(json, 'text'),
      createdAt: _requiredDate(json, 'createdAt'),
      localRecordingReference: _optionalString(
        json,
        'localRecordingReference',
      ),
    );
  }
}

/// A reviewed elder prompt a family wants to use in one built-in episode.
///
/// The text remains portable, while [localRecordingReference] points only to
/// media stored on this device. When no recording is present the theater may
/// still use the reviewed text with the platform TTS, but must label it as
/// device narration rather than family audio.
class FamilyEpisodeVoice {
  const FamilyEpisodeVoice({
    required this.episodeId,
    required this.adultMemberId,
    required this.targetText,
    required this.translationZh,
    required this.romanization,
    required this.updatedAt,
    this.promptId,
    this.localRecordingReference,
  });

  final String episodeId;

  /// The prompt node this voice replaces. `null` is the legacy/opening slot,
  /// preserving backups created before per-prompt family voices existed.
  final String? promptId;
  final String adultMemberId;
  final String targetText;
  final String translationZh;
  final String romanization;
  final DateTime updatedAt;
  final String? localRecordingReference;

  bool get hasFamilyRecording =>
      localRecordingReference != null && localRecordingReference!.isNotEmpty;

  Map<String, Object?> toJson({bool includeLocalRecordingReference = true}) => {
        'episodeId': episodeId,
        'promptId': promptId,
        'adultMemberId': adultMemberId,
        'targetText': targetText,
        'translationZh': translationZh,
        'romanization': romanization,
        'updatedAt': updatedAt.toIso8601String(),
        'localRecordingReference':
            includeLocalRecordingReference ? localRecordingReference : null,
      };

  factory FamilyEpisodeVoice.fromJson(Map<String, Object?> json) {
    return FamilyEpisodeVoice(
      episodeId: _requiredString(json, 'episodeId'),
      promptId: _optionalString(json, 'promptId'),
      adultMemberId: _requiredString(json, 'adultMemberId'),
      targetText: _requiredString(json, 'targetText'),
      translationZh: _requiredString(json, 'translationZh'),
      romanization: _requiredString(json, 'romanization'),
      updatedAt: _requiredDate(json, 'updatedAt'),
      localRecordingReference: _optionalString(
        json,
        'localRecordingReference',
      ),
    );
  }
}

class FamilyCircleStoryCard {
  FamilyCircleStoryCard({
    required this.id,
    required this.episode,
    required this.createdByMemberId,
    required this.childMemberId,
    required this.sceneOutcome,
    required this.createdAt,
    this.childChoice,
    this.childUtterance,
    this.localRecordingReference,
    this.relayId,
    this.familyRecordingReference,
    this.sourceConversationCard,
    List<FamilyStickerReaction> reactions = const [],
    List<AdultStoryContinuation> continuations = const [],
    Set<String> readByMemberIds = const {},
  })  : reactions = List.unmodifiable(reactions),
        continuations = List.unmodifiable(continuations),
        readByMemberIds = Set.unmodifiable(readByMemberIds) {
    if (_blank(childChoice) && _blank(childUtterance)) {
      throw ArgumentError(
        '家庭故事卡至少需要孩子選擇或說出的短句。',
      );
    }
  }

  final String id;

  /// 劇集或小故事的穩定識別/名稱。
  final String episode;
  final String createdByMemberId;
  final String childMemberId;
  final String? childChoice;
  final String? childUtterance;
  final String sceneOutcome;
  final DateTime createdAt;

  /// 僅保存本機媒體的 reference，JSON 不包含音檔本體。
  final String? localRecordingReference;

  /// Marks a child → adult → child daily-story relay card.
  final String? relayId;

  /// Optional local reference for the adult's family-language baton.
  final String? familyRecordingReference;

  /// Full theater result when this card was produced by the conversation UI.
  /// Keeping it typed preserves the whole choice path instead of flattening a
  /// three-turn story into a single display sentence.
  final theater.ConversationStoryCard? sourceConversationCard;
  final List<FamilyStickerReaction> reactions;
  final List<AdultStoryContinuation> continuations;
  final Set<String> readByMemberIds;

  bool isUnreadFor(String memberId) => !readByMemberIds.contains(memberId);

  FamilyCircleStoryCard copyWith({
    List<FamilyStickerReaction>? reactions,
    List<AdultStoryContinuation>? continuations,
    Set<String>? readByMemberIds,
  }) {
    return FamilyCircleStoryCard(
      id: id,
      episode: episode,
      createdByMemberId: createdByMemberId,
      childMemberId: childMemberId,
      childChoice: childChoice,
      childUtterance: childUtterance,
      sceneOutcome: sceneOutcome,
      createdAt: createdAt,
      localRecordingReference: localRecordingReference,
      relayId: relayId,
      familyRecordingReference: familyRecordingReference,
      sourceConversationCard: sourceConversationCard,
      reactions: reactions ?? this.reactions,
      continuations: continuations ?? this.continuations,
      readByMemberIds: readByMemberIds ?? this.readByMemberIds,
    );
  }

  Map<String, Object?> toJson({bool includeLocalRecordingReferences = true}) =>
      {
        'id': id,
        'episode': episode,
        'createdByMemberId': createdByMemberId,
        'childMemberId': childMemberId,
        'childChoice': childChoice,
        'childUtterance': childUtterance,
        'sceneOutcome': sceneOutcome,
        'createdAt': createdAt.toIso8601String(),
        'localRecordingReference':
            includeLocalRecordingReferences ? localRecordingReference : null,
        'relayId': relayId,
        'familyRecordingReference':
            includeLocalRecordingReferences ? familyRecordingReference : null,
        'sourceConversationCard': sourceConversationCard?.toJson(),
        'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
        'continuations': continuations
            .map(
              (continuation) => continuation.toJson(
                includeLocalRecordingReference: includeLocalRecordingReferences,
              ),
            )
            .toList(),
        'readByMemberIds': readByMemberIds.toList()..sort(),
      };

  factory FamilyCircleStoryCard.fromJson(Map<String, Object?> json) {
    return FamilyCircleStoryCard(
      id: _requiredString(json, 'id'),
      episode: _requiredString(json, 'episode'),
      createdByMemberId: _requiredString(json, 'createdByMemberId'),
      childMemberId: _requiredString(json, 'childMemberId'),
      childChoice: _optionalString(json, 'childChoice'),
      childUtterance: _optionalString(json, 'childUtterance'),
      sceneOutcome: _requiredString(json, 'sceneOutcome'),
      createdAt: _requiredDate(json, 'createdAt'),
      localRecordingReference: _optionalString(json, 'localRecordingReference'),
      relayId: _optionalString(json, 'relayId'),
      familyRecordingReference:
          _optionalString(json, 'familyRecordingReference'),
      sourceConversationCard:
          _optionalConversationCard(json['sourceConversationCard']),
      reactions: _objectList(json, 'reactions')
          .map(FamilyStickerReaction.fromJson)
          .toList(growable: false),
      continuations: _objectList(json, 'continuations')
          .map(AdultStoryContinuation.fromJson)
          .toList(growable: false),
      readByMemberIds: _stringList(json, 'readByMemberIds').toSet(),
    );
  }

  factory FamilyCircleStoryCard.fromConversationCard(
    theater.ConversationStoryCard card, {
    required String createdByMemberId,
    required String childMemberId,
    String? localRecordingReference,
  }) {
    final lastMoment = card.moments.isEmpty ? null : card.moments.last;
    return FamilyCircleStoryCard(
      id: card.id,
      episode: card.episodeId,
      createdByMemberId: createdByMemberId,
      childMemberId: childMemberId,
      childChoice: lastMoment?.translationZh ?? card.endingTitleZh,
      childUtterance: lastMoment?.childLine,
      sceneOutcome: card.endingTitleZh,
      createdAt: card.completedAt,
      localRecordingReference: localRecordingReference,
      sourceConversationCard: card,
    );
  }
}

theater.ConversationStoryCard? _optionalConversationCard(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const FormatException('sourceConversationCard 必須是 JSON 物件。');
  }
  final json = Map<String, Object?>.from(value);
  final moments = _objectList(json, 'moments')
      .map(
        (moment) => theater.ConversationStoryMoment(
          choiceId: _requiredString(moment, 'choiceId'),
          emoji: _requiredString(moment, 'emoji'),
          childLine: _requiredString(moment, 'childLine'),
          translationZh: _requiredString(moment, 'translationZh'),
          storyBeatZh: _requiredString(moment, 'storyBeatZh'),
          transcript: _optionalString(moment, 'transcript'),
        ),
      )
      .toList(growable: false);
  return theater.ConversationStoryCard(
    id: _requiredString(json, 'id'),
    episodeId: _requiredString(json, 'episodeId'),
    title: _requiredString(json, 'title'),
    elderName: _requiredString(json, 'elderName'),
    completedAt: _requiredDate(json, 'completedAt'),
    endingTitleZh: _requiredString(json, 'endingTitleZh'),
    endingEmoji: _requiredString(json, 'endingEmoji'),
    moments: moments,
  );
}

bool _blank(String? value) => value == null || value.trim().isEmpty;

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必須是非空白字串。');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key 必須是字串或 null。');
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key 必須是布林值。');
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key 必須是整數。');
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是 ISO-8601 時間。');
  return parsed;
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key 必須是時間字串或 null。');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是 ISO-8601 時間。');
  return parsed;
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key] ?? const <Object?>[];
  if (value is! List) throw FormatException('$key 必須是陣列。');
  return value.map((item) {
    if (item is! Map) throw FormatException('$key 的項目必須是 JSON 物件。');
    return Map<String, Object?>.from(item);
  }).toList(growable: false);
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key] ?? const <Object?>[];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key 必須是字串陣列。');
  }
  return value.cast<String>().toList(growable: false);
}

T _enumByName<T extends Enum>(List<T> values, String name, String key) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$key 含有不支援的值：$name。');
}
