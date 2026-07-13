enum FamilyRelayStage { waitingForAdult, waitingForChild, completed }

/// A local-only, three-step handoff that binds a child's daily intent, the
/// family's reviewed phrase, and the child's completed practice attempt.
///
/// Media remains in [FamilyStory] and [LearningAttempt]; this record stores
/// only stable references so retries never duplicate recordings.
class FamilyRelay {
  const FamilyRelay({
    required this.id,
    required this.seedId,
    required this.seedTitle,
    required this.childIntentZh,
    required this.childMemberId,
    required this.requestedAt,
    this.adultMemberId,
    this.familyStoryId,
    this.adultCompletedAt,
    this.childAttemptId,
    this.completedAt,
  });

  final String id;
  final String seedId;
  final String seedTitle;
  final String childIntentZh;
  final String childMemberId;
  final DateTime requestedAt;
  final String? adultMemberId;
  final String? familyStoryId;
  final DateTime? adultCompletedAt;
  final String? childAttemptId;
  final DateTime? completedAt;

  FamilyRelayStage get stage {
    if (childAttemptId != null && completedAt != null) {
      return FamilyRelayStage.completed;
    }
    if (familyStoryId != null && adultCompletedAt != null) {
      return FamilyRelayStage.waitingForChild;
    }
    return FamilyRelayStage.waitingForAdult;
  }

  FamilyRelay completeAdultTurn({
    required String memberId,
    required String storyId,
    required DateTime at,
  }) {
    if (stage != FamilyRelayStage.waitingForAdult) {
      throw StateError('家庭接力已經完成家人這一棒。');
    }
    if (memberId.trim().isEmpty || storyId.trim().isEmpty) {
      throw ArgumentError('家人與故事識別不得空白。');
    }
    return FamilyRelay(
      id: id,
      seedId: seedId,
      seedTitle: seedTitle,
      childIntentZh: childIntentZh,
      childMemberId: childMemberId,
      requestedAt: requestedAt,
      adultMemberId: memberId,
      familyStoryId: storyId,
      adultCompletedAt: at,
    );
  }

  FamilyRelay completeChildTurn({
    required String attemptId,
    required DateTime at,
  }) {
    if (stage != FamilyRelayStage.waitingForChild) {
      throw StateError('家庭接力尚未輪到孩子接棒。');
    }
    if (attemptId.trim().isEmpty) {
      throw ArgumentError('孩子練習識別不得空白。');
    }
    return FamilyRelay(
      id: id,
      seedId: seedId,
      seedTitle: seedTitle,
      childIntentZh: childIntentZh,
      childMemberId: childMemberId,
      requestedAt: requestedAt,
      adultMemberId: adultMemberId,
      familyStoryId: familyStoryId,
      adultCompletedAt: adultCompletedAt,
      childAttemptId: attemptId,
      completedAt: at,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'seedId': seedId,
        'seedTitle': seedTitle,
        'childIntentZh': childIntentZh,
        'childMemberId': childMemberId,
        'requestedAt': requestedAt.toIso8601String(),
        'adultMemberId': adultMemberId,
        'familyStoryId': familyStoryId,
        'adultCompletedAt': adultCompletedAt?.toIso8601String(),
        'childAttemptId': childAttemptId,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory FamilyRelay.fromJson(Map<String, Object?> json) {
    final relay = FamilyRelay(
      id: _requiredString(json, 'id'),
      seedId: _requiredString(json, 'seedId'),
      seedTitle: _requiredString(json, 'seedTitle'),
      childIntentZh: _requiredString(json, 'childIntentZh'),
      childMemberId: _requiredString(json, 'childMemberId'),
      requestedAt: _requiredDate(json, 'requestedAt'),
      adultMemberId: _optionalString(json, 'adultMemberId'),
      familyStoryId: _optionalString(json, 'familyStoryId'),
      adultCompletedAt: _optionalDate(json, 'adultCompletedAt'),
      childAttemptId: _optionalString(json, 'childAttemptId'),
      completedAt: _optionalDate(json, 'completedAt'),
    );
    final valid = switch (relay.stage) {
      FamilyRelayStage.waitingForAdult => relay.adultMemberId == null &&
          relay.familyStoryId == null &&
          relay.adultCompletedAt == null &&
          relay.childAttemptId == null &&
          relay.completedAt == null,
      FamilyRelayStage.waitingForChild => relay.adultMemberId != null &&
          relay.familyStoryId != null &&
          relay.adultCompletedAt != null &&
          relay.childAttemptId == null &&
          relay.completedAt == null,
      FamilyRelayStage.completed => relay.adultMemberId != null &&
          relay.familyStoryId != null &&
          relay.adultCompletedAt != null &&
          relay.childAttemptId != null &&
          relay.completedAt != null,
    };
    if (!valid) throw const FormatException('家庭接力狀態欄位不一致。');
    return relay;
  }
}

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
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必須是非空白字串或 null。');
  }
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是ISO-8601時間。');
  return parsed;
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key 必須是時間字串或null。');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是ISO-8601時間。');
  return parsed;
}
