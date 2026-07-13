import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as secure_crypto;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_story.dart';
import '../models/family_relay.dart';
import '../models/learning_attempt.dart';
import '../models/lesson_content.dart';
import '../models/task_draft.dart';

typedef AdultPinKdf = Future<List<int>> Function(String pin, List<int> salt);

class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this._adultPinKdf);

  static const _storiesKey = 'hometongue.stories.v1';
  static const _attemptsKey = 'hometongue.attempts.v1';
  static const _relaysKey = 'hometongue.family-relays.v1';
  static const _sceneGamesKey = 'hometongue.scene-games.v1';
  static const _consentKey = 'hometongue.privacy-consent.v1';
  static const _initializedKey = 'hometongue.initialized.v1';
  static const _adultPinHashKey = 'hometongue.adult-pin-hash.v1';
  static const _adultPinSaltKey = 'hometongue.adult-pin-salt.v1';
  static const _adultPinVerifierKey = 'hometongue.adult-pin-verifier.v2';
  static const _adultPinSaltV2Key = 'hometongue.adult-pin-salt.v2';
  static const _adultPinFailedAttemptsKey =
      'hometongue.adult-pin-failed-attempts.v1';
  static const _adultPinLockedUntilKey = 'hometongue.adult-pin-locked-until.v1';
  static const _adultPinIterations = 600000;

  final SharedPreferences _prefs;
  final AdultPinKdf _adultPinKdf;
  final List<FamilyStory> _stories = [];
  final List<LearningAttempt> _attempts = [];
  final List<FamilyRelay> _relays = [];
  final Map<String, int> _scenePlays = {};
  bool _privacyConsent = false;
  String? _adultPinHash;
  String? _adultPinSalt;
  bool _adultPinUsesLegacyHash = false;
  int _failedPinAttempts = 0;
  DateTime? _pinLockedUntil;

  List<FamilyStory> get stories => List.unmodifiable(_stories);
  List<LearningAttempt> get attempts => List.unmodifiable(_attempts);
  List<FamilyRelay> get relays => List.unmodifiable(_relays);
  bool get privacyConsent => _privacyConsent;
  bool get adultPinLocked {
    final until = _pinLockedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _pinLockedUntil = null;
    _failedPinAttempts = 0;
    return false;
  }

  int get remainingPinAttempts => (5 - _failedPinAttempts).clamp(0, 5);

  int get pinLockRemainingSeconds {
    final until = _pinLockedUntil;
    if (until == null) return 0;
    final seconds = until.difference(DateTime.now()).inSeconds + 1;
    return seconds.clamp(0, 30);
  }

  List<LearningAttempt> get pendingAttempts => _attempts
      .where((attempt) => attempt.result == ReviewResult.pending)
      .toList(growable: false);

  int get understoodCount => _attempts
      .where((attempt) => attempt.result == ReviewResult.understood)
      .length;

  int get practicedStoryCount =>
      _attempts.map((attempt) => attempt.storyId).toSet().length;

  int get familyPhraseCount =>
      _stories.expand((story) => story.keyPhrases).toSet().length;

  int get totalXp => _attempts.length * 20 + understoodCount * 5;
  int get totalScenePlays =>
      _scenePlays.values.fold(0, (total, count) => total + count);
  int get cultureCardCount =>
      _scenePlays.values.where((count) => count > 0).length;
  int scenePlayCount(String storyId) => _scenePlays[storyId] ?? 0;

  int get todayXp {
    final now = DateTime.now();
    return _attempts
            .where((attempt) => _sameDay(attempt.createdAt, now))
            .length *
        20;
  }

  int get weeklyPracticeDays {
    final today = _dayOnly(DateTime.now());
    final start = today.subtract(Duration(days: today.weekday - 1));
    return _attempts
        .map((attempt) => _dayOnly(attempt.createdAt))
        .where((day) => !day.isBefore(start) && !day.isAfter(today))
        .toSet()
        .length;
  }

  int get streakDays {
    final practiced =
        _attempts.map((attempt) => _dayOnly(attempt.createdAt)).toSet();
    if (practiced.isEmpty) return 0;
    var cursor = _dayOnly(DateTime.now());
    if (!practiced.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (practiced.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static Future<AppStore> load({AdultPinKdf? adultPinKdf}) async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore._(prefs, adultPinKdf ?? _deriveAdultPinWithPbkdf2);
    store._adultPinHash = prefs.getString(_adultPinVerifierKey);
    store._adultPinSalt = prefs.getString(_adultPinSaltV2Key);
    if (store._adultPinHash == null || store._adultPinSalt == null) {
      store._adultPinHash = prefs.getString(_adultPinHashKey);
      store._adultPinSalt = prefs.getString(_adultPinSaltKey);
      store._adultPinUsesLegacyHash =
          store._adultPinHash != null && store._adultPinSalt != null;
    }
    store._failedPinAttempts =
        prefs.getInt(_adultPinFailedAttemptsKey)?.clamp(0, 5) ?? 0;
    final lockedUntil = prefs.getString(_adultPinLockedUntilKey);
    store._pinLockedUntil =
        lockedUntil == null ? null : DateTime.tryParse(lockedUntil);
    store._privacyConsent = (prefs.getBool(_consentKey) ?? false) &&
        store._adultPinHash != null &&
        store._adultPinSalt != null;
    store._loadJson();
    store._loadRelays();
    store._loadSceneGames();
    var shouldPersist = false;
    final initialized = prefs.getBool(_initializedKey) ?? false;
    final hasBundledSample = store._stories.any(
      (story) => story.isSample && _bundledStoryIds.contains(story.id),
    );
    if (!initialized || hasBundledSample) {
      shouldPersist = store._upsertBundledStories();
    }
    if (!initialized) {
      await prefs.setBool(_initializedKey, true);
    }
    if (shouldPersist) await store._persist();
    return store;
  }

  bool _upsertBundledStories() {
    final before = jsonEncode(
      _stories.map((story) => story.toJson()).toList(growable: false),
    );
    final protectedIds = _stories
        .where(
          (story) => _bundledStoryIds.contains(story.id) && !story.isSample,
        )
        .map((story) => story.id)
        .toSet();
    final next = <FamilyStory>[
      ..._stories.where(
        (story) => !_bundledStoryIds.contains(story.id) || !story.isSample,
      ),
      ..._bundledStories.where(
        (story) => !protectedIds.contains(story.id),
      ),
    ];
    final after = jsonEncode(
      next.map((story) => story.toJson()).toList(growable: false),
    );
    if (before == after) return false;
    _stories
      ..clear()
      ..addAll(next);
    return true;
  }

  void _loadJson() {
    final storyText = _prefs.getString(_storiesKey);
    final attemptText = _prefs.getString(_attemptsKey);
    try {
      if (storyText != null) {
        final decoded = jsonDecode(storyText) as List<Object?>;
        _stories.addAll(
          decoded.map(
            (value) => FamilyStory.fromJson(
              Map<String, Object?>.from(value! as Map<Object?, Object?>),
            ),
          ),
        );
      }
      if (attemptText != null) {
        final decoded = jsonDecode(attemptText) as List<Object?>;
        _attempts.addAll(
          decoded.map(
            (value) => LearningAttempt.fromJson(
              Map<String, Object?>.from(value! as Map<Object?, Object?>),
            ),
          ),
        );
      }
    } on FormatException {
      _stories.clear();
      _attempts.clear();
    } on TypeError {
      _stories.clear();
      _attempts.clear();
    }
  }

  void _loadSceneGames() {
    final text = _prefs.getString(_sceneGamesKey);
    if (text == null) return;
    try {
      final decoded = Map<String, Object?>.from(jsonDecode(text) as Map);
      for (final entry in decoded.entries) {
        final count = entry.value;
        if (count is num && count > 0) {
          _scenePlays[entry.key] = count.round();
        }
      }
    } on Object {
      _scenePlays.clear();
    }
  }

  void _loadRelays() {
    final text = _prefs.getString(_relaysKey);
    if (text == null) return;
    try {
      final decoded = jsonDecode(text) as List<Object?>;
      _relays.addAll(
        decoded.map(
          (value) => FamilyRelay.fromJson(
            Map<String, Object?>.from(value! as Map<Object?, Object?>),
          ),
        ),
      );
    } on FormatException {
      _relays.clear();
    } on TypeError {
      _relays.clear();
    }
  }

  Future<void> completeSceneGame(String storyId) async {
    _scenePlays[storyId] = scenePlayCount(storyId) + 1;
    await _prefs.setString(_sceneGamesKey, jsonEncode(_scenePlays));
    notifyListeners();
  }

  Future<void> acceptPrivacy({required String adultPin}) async {
    if (!RegExp(r'^\d{4}$').hasMatch(adultPin)) {
      throw ArgumentError('家長碼必須是四位數');
    }
    await _setAdultPinVerifier(adultPin);
    _failedPinAttempts = 0;
    _pinLockedUntil = null;
    _privacyConsent = true;
    await _persistAdultPinAttemptState();
    await _prefs.setBool(_consentKey, true);
    notifyListeners();
  }

  Future<bool> verifyAdultPin(String pin) async {
    if (adultPinLocked) return false;
    final salt = _adultPinSalt;
    final expected = _adultPinHash;
    if (salt == null || expected == null) return false;
    final matches = _adultPinUsesLegacyHash
        ? _constantTimeEquals(
            utf8.encode(_hashPin(pin, salt)),
            utf8.encode(expected),
          )
        : await _verifyAdultPinV2(pin, salt, expected);
    if (matches) {
      _failedPinAttempts = 0;
      _pinLockedUntil = null;
      if (_adultPinUsesLegacyHash) await _setAdultPinVerifier(pin);
      await _persistAdultPinAttemptState();
      return true;
    }
    _failedPinAttempts += 1;
    if (_failedPinAttempts >= 5) {
      _pinLockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    await _persistAdultPinAttemptState();
    return false;
  }

  Future<FamilyRelay> startFamilyRelay({
    required String seedId,
    required String seedTitle,
    required String childIntentZh,
    required String childMemberId,
  }) async {
    final normalizedSeedId = seedId.trim();
    final normalizedTitle = seedTitle.trim();
    final normalizedIntent = childIntentZh.trim();
    final normalizedChildId = childMemberId.trim();
    if ([
      normalizedSeedId,
      normalizedTitle,
      normalizedIntent,
      normalizedChildId,
    ].any((value) => value.isEmpty)) {
      throw ArgumentError('家庭接力的題材、孩子意圖與成員不得空白。');
    }
    for (final relay in _relays) {
      if (relay.stage == FamilyRelayStage.waitingForAdult &&
          relay.seedId == normalizedSeedId &&
          relay.childIntentZh == normalizedIntent &&
          relay.childMemberId == normalizedChildId) {
        return relay;
      }
    }
    final relay = FamilyRelay(
      id: _randomHex(12),
      seedId: normalizedSeedId,
      seedTitle: normalizedTitle,
      childIntentZh: normalizedIntent,
      childMemberId: normalizedChildId,
      requestedAt: DateTime.now(),
    );
    _relays.insert(0, relay);
    await _persist();
    notifyListeners();
    return relay;
  }

  Future<FamilyRelay> completeAdultRelay({
    required String relayId,
    required String adultMemberId,
    required String storyId,
  }) async {
    final relayIndex = _relays.indexWhere((relay) => relay.id == relayId);
    if (relayIndex < 0) throw StateError('找不到要接續的家庭接力。');
    final story = storyById(storyId);
    if (story == null) throw StateError('家庭短句尚未成功儲存。');
    final current = _relays[relayIndex];
    if (current.stage != FamilyRelayStage.waitingForAdult) {
      if (current.familyStoryId == storyId) return current;
      throw StateError('這個家庭接力已綁定另一張故事。');
    }
    final next = current.completeAdultTurn(
      memberId: adultMemberId,
      storyId: storyId,
      at: DateTime.now(),
    );
    _relays[relayIndex] = next;
    await _persist();
    notifyListeners();
    return next;
  }

  Future<FamilyRelay?> completeChildRelay({
    required String storyId,
    required String attemptId,
  }) async {
    final relayIndex = _relays.indexWhere(
      (relay) => relay.familyStoryId == storyId,
    );
    if (relayIndex < 0) return null;
    final attemptIndex = _attempts.indexWhere(
      (attempt) => attempt.id == attemptId && attempt.storyId == storyId,
    );
    if (attemptIndex < 0) {
      throw StateError('孩子這一棒尚未成功儲存。');
    }
    final current = _relays[relayIndex];
    if (current.stage == FamilyRelayStage.completed) {
      if (current.childAttemptId == attemptId) return current;
      throw StateError('這個家庭接力已由另一筆孩子紀錄完成。');
    }
    final next = current.completeChildTurn(
      attemptId: attemptId,
      at: DateTime.now(),
    );
    _relays[relayIndex] = next;
    await _persist();
    notifyListeners();
    return next;
  }

  FamilyRelay? relayById(String relayId) {
    for (final relay in _relays) {
      if (relay.id == relayId) return relay;
    }
    return null;
  }

  FamilyRelay? relayForStory(String storyId) {
    for (final relay in _relays) {
      if (relay.familyStoryId == storyId) return relay;
    }
    return null;
  }

  Future<FamilyStory> addStory({
    required String title,
    required String objectName,
    required String vietnamese,
    required String chinese,
    required TaskDraft draft,
    required bool humanConfirmed,
    String? audioPath,
    String? photoPath,
    String? pronunciationGuide,
    String pronunciationSystem = '羅馬字分詞',
    List<String> practiceChunks = const [],
    String languageName = '越南語',
    String? languageTag,
    LessonContent? lessonContent,
    FamilyChallenge? familyChallenge,
    String? illustrationAsset,
    String? originStoryIdeaId,
    String? originStoryIdeaTitle,
  }) async {
    final id = _randomStoryId();
    final story = FamilyStory(
      id: id,
      title: title.trim(),
      objectName: objectName.trim(),
      vietnamese: vietnamese.trim(),
      chinese: chinese.trim(),
      promptZh: draft.promptZh,
      promptVi: draft.promptVi,
      keyPhrases: draft.keyPhrases,
      draftConfidence: draft.confidence,
      humanConfirmed: humanConfirmed,
      createdAt: DateTime.now(),
      audioPath: audioPath,
      photoPath: photoPath,
      pronunciationGuide: pronunciationGuide?.trim(),
      pronunciationSystem: pronunciationSystem,
      practiceChunks: practiceChunks,
      languageName: languageName,
      languageTag: languageTag,
      lessonContent: lessonContent,
      familyChallenge: familyChallenge,
      illustrationAsset: illustrationAsset,
      originStoryIdeaId: originStoryIdeaId,
      originStoryIdeaTitle: originStoryIdeaTitle,
    );
    _stories.insert(0, story);
    await _persist();
    notifyListeners();
    return story;
  }

  Future<void> confirmStory(String storyId) async {
    final index = _stories.indexWhere((story) => story.id == storyId);
    if (index < 0) return;
    _stories[index] = _stories[index].copyWith(humanConfirmed: true);
    await _persist();
    notifyListeners();
  }

  Future<LearningAttempt> submitAttempt({
    required String storyId,
    String? audioPath,
    String? childNote,
    int? recordingDurationMs,
    double? averageAmplitudeDb,
    String? coachSummary,
    String? coachMode,
  }) async {
    final normalizedNote = childNote?.trim();
    final attempt = LearningAttempt(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      storyId: storyId,
      createdAt: DateTime.now(),
      result: ReviewResult.pending,
      audioPath: audioPath,
      childNote: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
      recordingDurationMs: recordingDurationMs,
      averageAmplitudeDb: averageAmplitudeDb,
      coachSummary: coachSummary,
      coachMode: coachMode,
    );
    _attempts.insert(0, attempt);
    await _persist();
    notifyListeners();
    return attempt;
  }

  Future<void> reviewAttempt({
    required String attemptId,
    required ReviewResult result,
    String? correction,
  }) async {
    final index = _attempts.indexWhere((attempt) => attempt.id == attemptId);
    if (index < 0) return;
    final normalizedCorrection = correction?.trim();
    _attempts[index] = _attempts[index].copyWith(
      result: result,
      familyCorrection:
          normalizedCorrection == null || normalizedCorrection.isEmpty
              ? null
              : normalizedCorrection,
      reviewedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  FamilyStory? findStory(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    String candidate = trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'hometongue' && uri.host == 'story') {
      candidate = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    }
    candidate = candidate.replaceFirst(
      RegExp(r'^HT-', caseSensitive: false),
      '',
    );
    for (final story in _stories) {
      if (story.id.toLowerCase() == candidate.toLowerCase() ||
          story.shareCode.toLowerCase() == trimmed.toLowerCase()) {
        return story;
      }
    }
    return null;
  }

  FamilyStory? storyById(String id) {
    for (final story in _stories) {
      if (story.id == id) return story;
    }
    return null;
  }

  List<LearningAttempt> attemptsFor(String storyId) => _attempts
      .where((attempt) => attempt.storyId == storyId)
      .toList(growable: false);

  Future<void> deleteStory(String storyId) async {
    _stories.removeWhere((story) => story.id == storyId);
    _attempts.removeWhere((attempt) => attempt.storyId == storyId);
    _relays.removeWhere((relay) => relay.familyStoryId == storyId);
    await _persist();
    notifyListeners();
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'hometongue-export-v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'privacyNote': '音檔、照片與本機路徑不會匯出；本檔只含文字與學習紀錄。',
      'stories': _stories.map((story) {
        final data = story.toJson()
          ..remove('audioPath')
          ..remove('photoPath');
        if (story.lessonContent != null) {
          data['lessonContent'] = story.lessonContent!.toJson(
            includeAudioPaths: false,
          );
        }
        data['hasFamilyAudio'] = story.audioPath != null;
        data['hasPhoto'] = story.photoPath != null;
        return data;
      }).toList(),
      'attempts': _attempts.map((attempt) {
        final data = attempt.toJson()..remove('audioPath');
        data['hasChildAudio'] = attempt.audioPath != null;
        return data;
      }).toList(),
      'familyRelays': _relays.map((relay) => relay.toJson()).toList(),
      'sceneGames': _scenePlays,
    });
  }

  /// Exports aggregate pilot evidence without family content or identifiers.
  ///
  /// Only the five built-in theme IDs are retained. Unknown IDs collapse into
  /// `other`, so an accidental free-text seed can never enter the report.
  String exportPilotSummaryJson() {
    const knownSeedIds = <String>{
      'family-sharing',
      'club',
      'lunch',
      'class',
      'friendship',
    };
    final buckets = <String, Map<String, int>>{};
    var adultCompleted = 0;
    var completed = 0;
    var familyAudio = 0;
    var childAudio = 0;
    final adultDurations = <Duration>[];
    final childDurations = <Duration>[];

    for (final relay in _relays) {
      final seedId =
          knownSeedIds.contains(relay.seedId) ? relay.seedId : 'other';
      final bucket = buckets.putIfAbsent(
        seedId,
        () => {'started': 0, 'adultCompleted': 0, 'completed': 0},
      );
      bucket['started'] = bucket['started']! + 1;
      if (relay.adultCompletedAt case final at?) {
        adultCompleted += 1;
        bucket['adultCompleted'] = bucket['adultCompleted']! + 1;
        final duration = at.difference(relay.requestedAt);
        if (!duration.isNegative) adultDurations.add(duration);
      }
      if (relay.completedAt case final at?) {
        completed += 1;
        bucket['completed'] = bucket['completed']! + 1;
        final adultAt = relay.adultCompletedAt;
        if (adultAt != null) {
          final duration = at.difference(adultAt);
          if (!duration.isNegative) childDurations.add(duration);
        }
      }
      final storyId = relay.familyStoryId;
      if (storyId != null && storyById(storyId)?.audioPath != null) {
        familyAudio += 1;
      }
      final attemptId = relay.childAttemptId;
      if (attemptId != null &&
          _attempts.any(
            (attempt) => attempt.id == attemptId && attempt.audioPath != null,
          )) {
        childAudio += 1;
      }
    }

    double? averageSeconds(List<Duration> values) {
      if (values.isEmpty) return null;
      final total = values.fold<int>(
        0,
        (sum, value) => sum + value.inMilliseconds,
      );
      return double.parse((total / values.length / 1000).toStringAsFixed(1));
    }

    final bySeed = buckets.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'hometongue-pilot-summary-v1',
      'privacyNote': '只含彙總計數與平均時間；不含姓名、家庭短句、成員／故事／作答識別、時間戳或媒體路徑。',
      'totals': {
        'started': _relays.length,
        'adultCompleted': adultCompleted,
        'completed': completed,
        'familyAudioUsed': familyAudio,
        'childAudioUsed': childAudio,
        'adultTurnAverageSeconds': averageSeconds(adultDurations),
        'childTurnAverageSeconds': averageSeconds(childDurations),
      },
      'bySeed': [
        for (final entry in bySeed) {'seedId': entry.key, ...entry.value},
      ],
    });
  }

  Future<String> writeExportFile() async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File(
      '${documents.path}${Platform.pathSeparator}'
      '傳家話_家庭資料_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(exportJson(), flush: true);
    return file.path;
  }

  Future<void> eraseEverything(Future<void> Function() eraseMedia) async {
    await eraseMedia();
    _stories.clear();
    _attempts.clear();
    _relays.clear();
    _scenePlays.clear();
    _privacyConsent = false;
    await _prefs.remove(_storiesKey);
    await _prefs.remove(_attemptsKey);
    await _prefs.remove(_relaysKey);
    await _prefs.remove(_sceneGamesKey);
    await _prefs.remove(_consentKey);
    await _prefs.remove(_adultPinHashKey);
    await _prefs.remove(_adultPinSaltKey);
    await _prefs.remove(_adultPinVerifierKey);
    await _prefs.remove(_adultPinSaltV2Key);
    await _prefs.remove(_adultPinFailedAttemptsKey);
    await _prefs.remove(_adultPinLockedUntilKey);
    _adultPinHash = null;
    _adultPinSalt = null;
    _adultPinUsesLegacyHash = false;
    _failedPinAttempts = 0;
    _pinLockedUntil = null;
    await _prefs.setBool(_initializedKey, true);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _storiesKey,
      jsonEncode(_stories.map((story) => story.toJson()).toList()),
    );
    await _prefs.setString(
      _attemptsKey,
      jsonEncode(_attempts.map((attempt) => attempt.toJson()).toList()),
    );
    await _prefs.setString(
      _relaysKey,
      jsonEncode(_relays.map((relay) => relay.toJson()).toList()),
    );
  }

  String _randomStoryId() {
    return _randomHex(12);
  }

  String _randomHex(int bytesLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(bytesLength, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> _setAdultPinVerifier(String pin) async {
    final saltBytes = _randomBytes(16);
    final salt = base64UrlEncode(saltBytes);
    final verifier = base64UrlEncode(await _adultPinKdf(pin, saltBytes));
    _adultPinSalt = salt;
    _adultPinHash = verifier;
    _adultPinUsesLegacyHash = false;
    await _prefs.setString(_adultPinSaltV2Key, salt);
    await _prefs.setString(_adultPinVerifierKey, verifier);
    await _prefs.remove(_adultPinSaltKey);
    await _prefs.remove(_adultPinHashKey);
  }

  Future<bool> _verifyAdultPinV2(
    String pin,
    String saltBase64,
    String expectedBase64,
  ) async {
    try {
      final salt = base64Url.decode(saltBase64);
      final expected = base64Url.decode(expectedBase64);
      if (salt.length != 16 || expected.length != 32) return false;
      final actual = await _adultPinKdf(pin, salt);
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  Future<void> _persistAdultPinAttemptState() async {
    await _prefs.setInt(_adultPinFailedAttemptsKey, _failedPinAttempts);
    final lockedUntil = _pinLockedUntil;
    if (lockedUntil == null) {
      await _prefs.remove(_adultPinLockedUntilKey);
    } else {
      await _prefs.setString(
        _adultPinLockedUntilKey,
        lockedUntil.toIso8601String(),
      );
    }
  }

  List<int> _randomBytes(int bytesLength) {
    final random = Random.secure();
    return List<int>.generate(bytesLength, (_) => random.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      final leftByte = index < left.length ? left[index] : 0;
      final rightByte = index < right.length ? right[index] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }

  static Future<List<int>> _deriveAdultPinWithPbkdf2(
    String pin,
    List<int> salt,
  ) async {
    final key = await secure_crypto.Pbkdf2.hmacSha256(
      iterations: _adultPinIterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static final FamilyStory _greetingStory = FamilyStory(
    id: 'family-greeting',
    title: '早安，外婆',
    objectName: '早晨問候',
    vietnamese: 'Cháu chào bà ạ.',
    chinese: '外婆／奶奶您好。',
    promptZh: '早上看到外婆，先說一句：「外婆您好。」',
    promptVi: 'Hãy nói: “Cháu chào bà ạ.”',
    keyPhrases: const ['Cháu chào', 'bà ạ'],
    draftConfidence: 0.95,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 13),
    audioPath: 'asset://assets/audio/vietnamese_greeting_full.mp3',
    isSample: true,
    languageName: '越南語',
    pronunciationGuide: 'Cháu · chào · bà · ạ',
    pronunciationSystem: '越文 Quốc ngữ',
    practiceChunks: const ['Cháu chào', 'bà ạ'],
    illustrationAsset: 'assets/images/family-morning-game-v1.webp',
    expectedDurationSeconds: 1.2,
    lessonContent: const LessonContent(
      schemaVersion: 3,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Cháu · chào · bà · ạ',
      coachIntroZh: '先看著外婆說「Cháu chào」，最後加上「bà ạ」表達尊敬。',
      memoryTipZh: '每天第一次見到家人時說一次，會比只背單字更容易記住。',
      targetDurationMs: 1200,
      segments: [
        LessonSegment(
          id: 'chau-chao',
          text: 'Cháu chào',
          tokens: ['Cháu', 'chào'],
          translationZh: '我向……問好',
          romanization: 'Cháu · chào',
          wordBreakdownZh: 'cháu＝孫子女對祖父母的自稱；chào＝問候。',
          pronunciationTipsZh: [
            'Cháu 的 dấu sắc 聲調往上；chào 的 dấu huyền 聲調自然往下。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_greeting_chau_chao.mp3',
          ),
        ),
        LessonSegment(
          id: 'ba-a',
          text: 'bà ạ',
          tokens: ['bà', 'ạ'],
          translationZh: '外婆／奶奶（禮貌語氣）',
          romanization: 'bà · ạ',
          wordBreakdownZh: 'bà＝祖母或年長女性；ạ＝晚輩對長輩常用的禮貌詞。',
          pronunciationTipsZh: [
            'bà 與 ạ 都不要拉長；保留字上的聲調符號。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_greeting_ba_a.mp3',
          ),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'family-greeting-pattern',
          template: '［自稱］＋ chào ＋［家人］＋ ạ.',
          meaningZh: '我向某位家人問好。',
          usageTipZh: '對父母常自稱 con，對祖父母常自稱 cháu；稱謂要跟家庭關係一起換。',
          examples: [
            LessonExample(
              targetText: 'Cháu chào ông ạ.',
              translationZh: '爺爺／外公您好。',
              romanization: 'Cháu · chào · ông · ạ',
              emoji: '👴',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_greeting_example_ong.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Con chào mẹ ạ.',
              translationZh: '媽媽您好。',
              romanization: 'Con · chào · mẹ · ạ',
              emoji: '👩',
              audio: LessonAudio(
                path: 'asset://assets/audio/vietnamese_greeting_example_me.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Em chào chị ạ.',
              translationZh: '姊姊您好。',
              romanization: 'Em · chào · chị · ạ',
              emoji: '👧',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_greeting_example_chi.mp3',
              ),
            ),
          ],
        ),
      ],
    ),
    familyChallenge: const FamilyChallenge(
      sceneTitleZh: '早晨問候',
      promptZh: '早上起床，孩子要先向誰問好？',
      listeningPromptZh: '聽到「Cháu chào bà ạ」，找出孩子正在問候的人。',
      dialoguePromptZh: '點到外婆後，看著她說一次：「Cháu chào bà ạ。」',
      correctChoiceZh: '外婆',
      distractorsZh: ['鬧鐘', '拖鞋'],
      correctEmoji: '👵',
      distractorEmojis: ['⏰', '🥿'],
      successMessageZh: '早安問候成功！',
      cultureNoteZh: '越南語會用家庭關係選擇自稱：孩子對父母常說 con，對祖父母常說 cháu。',
      hotspots: [
        ChallengeHotspot(
          labelZh: '外婆',
          left: 0.62,
          top: 0.10,
          width: 0.23,
          height: 0.61,
          hintZh: '看看右邊正在拉開窗簾的家人。',
        ),
        ChallengeHotspot(
          labelZh: '鬧鐘',
          left: 0.86,
          top: 0.04,
          width: 0.12,
          height: 0.22,
          hintZh: '這是牆上的鬧鐘。',
        ),
        ChallengeHotspot(
          labelZh: '拖鞋',
          left: 0.02,
          top: 0.82,
          width: 0.19,
          height: 0.13,
          hintZh: '這是床邊的拖鞋。',
        ),
      ],
    ),
  );

  static final FamilyStory _homecomingStory = FamilyStory(
    id: 'family-homecoming',
    title: '我回來了',
    objectName: '放學回家',
    vietnamese: 'Cháu về rồi ạ.',
    chinese: '外婆／奶奶，我回來了。',
    promptZh: '放學進門時，跟外婆說：「我回來了。」',
    promptVi: 'Hãy nói: “Cháu về rồi ạ.”',
    keyPhrases: const ['Cháu về', 'rồi ạ'],
    draftConfidence: 0.94,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 13),
    audioPath: 'asset://assets/audio/vietnamese_homecoming_full.mp3',
    isSample: true,
    languageName: '越南語',
    pronunciationGuide: 'Cháu · về · rồi · ạ',
    pronunciationSystem: '越文 Quốc ngữ',
    practiceChunks: const ['Cháu về', 'rồi ạ'],
    illustrationAsset: 'assets/images/family-homecoming-theater-v2.png',
    expectedDurationSeconds: 1.1,
    lessonContent: const LessonContent(
      schemaVersion: 3,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Cháu · về · rồi · ạ',
      coachIntroZh: '先說「Cháu về」，再用「rồi ạ」告訴外婆：現在已經回到家了。',
      memoryTipZh: '每次進家門都能真的說一次，動作和句子會一起被記住。',
      targetDurationMs: 1100,
      segments: [
        LessonSegment(
          id: 'chau-ve',
          text: 'Cháu về',
          tokens: ['Cháu', 'về'],
          translationZh: '我回來',
          romanization: 'Cháu · về',
          wordBreakdownZh: 'cháu＝孫子女的自稱；về＝回去／回來。',
          pronunciationTipsZh: [
            'về 帶 dấu huyền 聲調，音高自然往下。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_homecoming_chau_ve.mp3',
          ),
        ),
        LessonSegment(
          id: 'roi-a',
          text: 'rồi ạ',
          tokens: ['rồi', 'ạ'],
          translationZh: '已經了（禮貌語氣）',
          romanization: 'rồi · ạ',
          wordBreakdownZh: 'rồi＝已經、狀態改變；ạ＝對長輩的禮貌詞。',
          pronunciationTipsZh: [
            'rồi 的 dấu huyền 不要念成平音；最後的 ạ 要短。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_homecoming_roi_a.mp3',
          ),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'family-return-pattern',
          template: '［自稱］＋ về rồi ạ.',
          meaningZh: '我已經回來了。',
          usageTipZh: '對父母把 cháu 換成 con；rồi 放在動作後面，表示事情已經發生。',
          examples: [
            LessonExample(
              targetText: 'Con về rồi ạ.',
              translationZh: '爸爸媽媽，我回來了。',
              romanization: 'Con · về · rồi · ạ',
              emoji: '🏠',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_homecoming_example_con.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Mẹ về rồi.',
              translationZh: '媽媽回來了。',
              romanization: 'Mẹ · về · rồi',
              emoji: '👩',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_homecoming_example_me.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Bố về rồi.',
              translationZh: '爸爸回來了。',
              romanization: 'Bố · về · rồi',
              emoji: '👨',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_homecoming_example_bo.mp3',
              ),
            ),
          ],
        ),
      ],
    ),
    familyChallenge: const FamilyChallenge(
      sceneTitleZh: '放學回家',
      promptZh: '圖裡誰剛剛放學回到家？',
      listeningPromptZh: '聽到「Cháu về rồi ạ」，找出背著書包進門的人。',
      dialoguePromptZh: '找到孩子後，幫他對外婆說：「Cháu về rồi ạ。」',
      correctChoiceZh: '回家的孩子',
      distractorsZh: ['爸爸', '外婆'],
      correctEmoji: '🎒',
      distractorEmojis: ['👨', '👵'],
      successMessageZh: '找到剛回家的孩子了！',
      cultureNoteZh: '進門先向家人報到，是一句每天都能使用的家庭短句。',
      hotspots: [
        ChallengeHotspot(
          labelZh: '回家的孩子',
          left: 0.13,
          top: 0.25,
          width: 0.33,
          height: 0.61,
          hintZh: '找找背著綠色書包、正在揮手的人。',
        ),
        ChallengeHotspot(
          labelZh: '爸爸',
          left: 0.42,
          top: 0.24,
          width: 0.39,
          height: 0.72,
          hintZh: '這是蹲下來迎接孩子的爸爸。',
        ),
        ChallengeHotspot(
          labelZh: '外婆',
          left: 0.75,
          top: 0.10,
          width: 0.22,
          height: 0.82,
          hintZh: '這是站在右邊迎接孩子的外婆。',
        ),
      ],
    ),
  );

  static final FamilyStory _mealtimeStory = FamilyStory(
    id: 'family-mealtime',
    title: '開飯前先邀請',
    objectName: '全家吃飯',
    vietnamese: 'Cháu mời bà ăn cơm ạ.',
    chinese: '外婆／奶奶，請吃飯。',
    promptZh: '開飯前，先對外婆說：「請吃飯。」',
    promptVi: 'Hãy nói: “Cháu mời bà ăn cơm ạ.”',
    keyPhrases: const ['Cháu mời bà', 'ăn cơm ạ'],
    draftConfidence: 0.96,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 13),
    audioPath: 'asset://assets/audio/vietnamese_mealtime_full.mp3',
    isSample: true,
    languageName: '越南語',
    pronunciationGuide: 'Cháu · mời · bà · ăn · cơm · ạ',
    pronunciationSystem: '越文 Quốc ngữ',
    practiceChunks: const ['Cháu mời bà', 'ăn cơm ạ'],
    illustrationAsset: 'assets/images/family-mealtime-theater-v2.png',
    expectedDurationSeconds: 1.5,
    lessonContent: const LessonContent(
      schemaVersion: 3,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Cháu · mời · bà · ăn · cơm · ạ',
      coachIntroZh: '這句分成「邀請外婆」和「吃飯」兩塊；先慢慢說，再把兩塊接起來。',
      memoryTipZh: '真的坐到餐桌前再說一次，會把禮貌、人物和情境一起記住。',
      targetDurationMs: 1500,
      segments: [
        LessonSegment(
          id: 'chau-moi-ba',
          text: 'Cháu mời bà',
          tokens: ['Cháu', 'mời', 'bà'],
          translationZh: '我邀請外婆／奶奶',
          romanization: 'Cháu · mời · bà',
          wordBreakdownZh: 'cháu＝孫子女的自稱；mời＝邀請／請；bà＝祖母。',
          pronunciationTipsZh: [
            'mời 與 bà 都帶往下的聲調，保持自然，不用刻意壓低。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_mealtime_chau_moi_ba.mp3',
          ),
        ),
        LessonSegment(
          id: 'an-com-a',
          text: 'ăn cơm ạ',
          tokens: ['ăn', 'cơm', 'ạ'],
          translationZh: '吃飯（禮貌語氣）',
          romanization: 'ăn · cơm · ạ',
          wordBreakdownZh: 'ăn＝吃；cơm＝飯／一餐；ạ＝對長輩的禮貌詞。',
          pronunciationTipsZh: [
            'ăn 的尾音要收住；cơm 不要照英文字母逐個念。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_mealtime_an_com_a.mp3',
          ),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'invite-family-to-eat-pattern',
          template: '［自稱］＋ mời ＋［家人］＋ ăn cơm ạ.',
          meaningZh: '請某位家人吃飯。',
          usageTipZh: '換掉自稱和家人稱謂，就能對不同家人自然地說。',
          examples: [
            LessonExample(
              targetText: 'Con mời bố mẹ ăn cơm ạ.',
              translationZh: '爸爸媽媽，請吃飯。',
              romanization: 'Con · mời · bố · mẹ · ăn · cơm · ạ',
              emoji: '👨‍👩‍👧',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_mealtime_example_bo_me.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Cháu mời ông ăn cơm ạ.',
              translationZh: '爺爺／外公，請吃飯。',
              romanization: 'Cháu · mời · ông · ăn · cơm · ạ',
              emoji: '👴',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_mealtime_example_ong.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Mời cả nhà ăn cơm ạ.',
              translationZh: '請大家吃飯。',
              romanization: 'Mời · cả · nhà · ăn · cơm · ạ',
              emoji: '🍚',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_mealtime_example_ca_nha.mp3',
              ),
            ),
          ],
        ),
      ],
    ),
    familyChallenge: const FamilyChallenge(
      sceneTitleZh: '開飯前的禮貌',
      promptZh: '飯前，孩子要先邀請誰一起吃飯？',
      listeningPromptZh: '聽到「Cháu mời bà ăn cơm ạ」，在餐桌旁找出外婆。',
      dialoguePromptZh: '點到外婆後，對她說一次：「Cháu mời bà ăn cơm ạ。」',
      correctChoiceZh: '外婆',
      distractorsZh: ['白飯', '筷子'],
      correctEmoji: '👵',
      distractorEmojis: ['🍚', '🥢'],
      successMessageZh: '有禮貌地邀請外婆吃飯了！',
      cultureNoteZh: '飯前邀請長輩吃飯，是許多越南家庭熟悉的日常禮貌；每個家庭稱謂可能不同。',
      hotspots: [
        ChallengeHotspot(
          labelZh: '外婆',
          left: 0.79,
          top: 0.23,
          width: 0.21,
          height: 0.57,
          hintZh: '看看餐桌最右邊的長輩。',
        ),
        ChallengeHotspot(
          labelZh: '白飯',
          left: 0.39,
          top: 0.56,
          width: 0.26,
          height: 0.25,
          hintZh: '這是桌子中央的飯鍋。',
        ),
        ChallengeHotspot(
          labelZh: '筷子',
          left: 0.17,
          top: 0.78,
          width: 0.25,
          height: 0.19,
          hintZh: '這是桌子左下方的筷子。',
        ),
      ],
    ),
  );

  static final FamilyStory _deliciousStory = FamilyStory(
    id: 'family-delicious',
    title: '外婆煮得真好吃',
    objectName: '稱讚家常菜',
    vietnamese: 'Ngon quá ạ!',
    chinese: '太好吃了！',
    promptZh: '吃到外婆做的菜，笑著說：「太好吃了！」',
    promptVi: 'Hãy nói: “Ngon quá ạ!”',
    keyPhrases: const ['Ngon quá', 'ạ'],
    draftConfidence: 0.97,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 13),
    audioPath: 'asset://assets/audio/vietnamese_delicious_full.mp3',
    isSample: true,
    languageName: '越南語',
    pronunciationGuide: 'Ngon · quá · ạ',
    pronunciationSystem: '越文 Quốc ngữ',
    // This sentence is only three syllables. Isolating "ạ" gives it a
    // dictionary-like pronunciation that does not match natural polite speech.
    practiceChunks: const ['Ngon quá ạ'],
    illustrationAsset: 'assets/images/family-mealtime-theater-v2.png',
    expectedDurationSeconds: 0.9,
    lessonContent: const LessonContent(
      schemaVersion: 3,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Ngon · quá · ạ',
      coachIntroZh: '先說清楚「Ngon quá」，最後輕輕加上禮貌詞「ạ」。',
      memoryTipZh: '下一次吃到喜歡的家庭料理，立刻把這句送給做飯的人。',
      targetDurationMs: 900,
      segments: [
        LessonSegment(
          id: 'ngon-qua-a',
          text: 'Ngon quá ạ',
          tokens: ['Ngon', 'quá', 'ạ'],
          translationZh: '太好吃了（對長輩的禮貌說法）',
          romanization: 'Ngon · quá · ạ',
          wordBreakdownZh: 'ngon＝好吃；quá＝太……、非常；ạ＝晚輩對長輩說話時常用的禮貌詞。',
          pronunciationTipsZh: [
            'ngon 的尾音要收住；quá 的 dấu sắc 聲調往上。',
            'ạ 要短，但要接在整句後面聽，不把它拆成孤立單字。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_delicious_full.mp3',
          ),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'food-is-delicious-pattern',
          template: '［食物］＋ ngon quá ạ!',
          meaningZh: '某樣食物太好吃了！',
          usageTipZh: '只說 Ngon quá ạ 也很自然；知道食物名稱時，可以放在句首。',
          examples: [
            LessonExample(
              targetText: 'Canh ngon quá ạ!',
              translationZh: '湯太好喝了！',
              romanization: 'Canh · ngon · quá · ạ',
              emoji: '🥣',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_delicious_example_canh.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Cơm ngon quá ạ!',
              translationZh: '飯太好吃了！',
              romanization: 'Cơm · ngon · quá · ạ',
              emoji: '🍚',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_delicious_example_com.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Rau ngon quá ạ!',
              translationZh: '青菜太好吃了！',
              romanization: 'Rau · ngon · quá · ạ',
              emoji: '🥬',
              audio: LessonAudio(
                path:
                    'asset://assets/audio/vietnamese_delicious_example_rau.mp3',
              ),
            ),
          ],
        ),
      ],
    ),
    familyChallenge: const FamilyChallenge(
      sceneTitleZh: '稱讚家常菜',
      promptZh: '孩子想說「Ngon quá ạ!」，圖裡哪一道是青菜？',
      listeningPromptZh: '聽到「Ngon quá ạ」，找出桌上的一道菜。',
      dialoguePromptZh: '點到青菜後，笑著說一次：「Ngon quá ạ！」',
      correctChoiceZh: '青菜',
      distractorsZh: ['白飯', '檯燈'],
      correctEmoji: '🥬',
      distractorEmojis: ['🍚', '💡'],
      successMessageZh: '找到青菜，也把稱讚送給家人了！',
      cultureNoteZh: '共享餐食也是家庭表達關心的時刻；一句真心的 Ngon quá ạ 很短又實用。',
      hotspots: [
        ChallengeHotspot(
          labelZh: '青菜',
          left: 0.62,
          top: 0.74,
          width: 0.27,
          height: 0.24,
          hintZh: '看看桌子右下方的大碗。',
        ),
        ChallengeHotspot(
          labelZh: '白飯',
          left: 0.39,
          top: 0.56,
          width: 0.26,
          height: 0.25,
          hintZh: '這是桌子中央的飯鍋。',
        ),
        ChallengeHotspot(
          labelZh: '檯燈',
          left: 0.64,
          top: 0.03,
          width: 0.14,
          height: 0.24,
          hintZh: '這是後方亮著的檯燈。',
        ),
      ],
    ),
  );

  static final FamilyStory _fishSauceStory = FamilyStory(
    id: 'nuoc-mam',
    title: '文化加分：外婆的魚露',
    objectName: '餐桌上的魚露',
    vietnamese: 'Đây là nước mắm.',
    chinese: '這是魚露。',
    promptZh: '完成生活短句後，再來認識餐桌上的文化加分題：「這是魚露。」',
    promptVi: 'Hãy nói: “Đây là nước mắm.”',
    keyPhrases: const ['Đây là', 'nước mắm'],
    draftConfidence: 0.91,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 12),
    audioPath: 'asset://assets/audio/vietnamese_short_demo.mp3',
    isSample: true,
    languageName: '越南語',
    pronunciationGuide: 'Đây · là · nước · mắm',
    pronunciationSystem: '越文 Quốc ngữ',
    practiceChunks: const ['Đây là', 'nước mắm'],
    illustrationAsset: 'assets/images/family-kitchen-game-v2.webp',
    expectedDurationSeconds: 1.0,
    lessonContent: LessonContent(
      schemaVersion: 3,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Đây · là · nước · mắm',
      coachIntroZh: '把這句想成兩塊積木：「這是」＋「魚露」。先各自聽清楚，再把兩塊接起來。',
      memoryTipZh: '指著餐桌上的魚露說一次；換一樣東西，就能立刻造出新句子。',
      targetDurationMs: 1000,
      segments: [
        LessonSegment(
          id: 'day-la',
          text: 'Đây là',
          tokens: ['Đây', 'là'],
          translationZh: '這是……',
          romanization: 'Đây · là',
          wordBreakdownZh: 'Đây＝這／這個；là＝是。兩個詞連起來就是「這是」。',
          pronunciationTipsZh: [
            'Đây 的「ây」要快速滑過，不要拆成兩個很長的音。',
            'là 帶低降的 huyền 聲調，音高自然往下，不用用力壓。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_chunk_day_la.mp3',
          ),
        ),
        LessonSegment(
          id: 'nuoc-mam',
          text: 'nước mắm',
          tokens: ['nước', 'mắm'],
          translationZh: '魚露',
          romanization: 'nước · mắm',
          wordBreakdownZh: 'nước＝水／液體；mắm＝發酵醬。合在一起是「魚露」。',
          pronunciationTipsZh: [
            'nước 的 ươ 是一個連續母音，句中不要照英文字母逐個念。',
            '最後的 -c 與 -m 要收住，不要在尾端再多加一個母音。',
          ],
          audio: LessonAudio(
            path: 'asset://assets/audio/vietnamese_chunk_nuoc_mam.mp3',
          ),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'day-la-noun',
          template: 'Đây là +［人或東西］.',
          meaningZh: '這是＋人或東西。',
          usageTipZh: '指著眼前的人或物介紹時很好用；只要替換最後一格。',
          examples: [
            LessonExample(
              targetText: 'Đây là mẹ.',
              translationZh: '這是媽媽。',
              romanization: 'Đây · là · mẹ',
              emoji: '👩',
              audio: LessonAudio(
                path: 'asset://assets/audio/vietnamese_example_me.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Đây là nhà.',
              translationZh: '這是家／房子。',
              romanization: 'Đây · là · nhà',
              emoji: '🏠',
              audio: LessonAudio(
                path: 'asset://assets/audio/vietnamese_example_nha.mp3',
              ),
            ),
            LessonExample(
              targetText: 'Đây là cơm.',
              translationZh: '這是飯。',
              romanization: 'Đây · là · cơm',
              emoji: '🍚',
              audio: LessonAudio(
                path: 'asset://assets/audio/vietnamese_example_com.mp3',
              ),
            ),
          ],
        ),
      ],
    ),
    familyChallenge: FamilyChallenge(
      sceneTitleZh: '文化加分：魚露',
      promptZh: '外婆做菜時，要找哪一樣？',
      listeningPromptZh: '聽到「Đây là nước mắm」，找出裝著魚露的瓶子。',
      dialoguePromptZh: '點到魚露後，指著它說一次：「Đây là nước mắm。」',
      correctChoiceZh: '魚露',
      distractorsZh: ['白飯', '筷子'],
      correctEmoji: '🫙',
      distractorEmojis: ['🍚', '🥢'],
      successMessageZh: '找到我們家的味道了！',
      cultureNoteZh: '每個家庭調魚露的方法都不一樣。下次問外婆：「我們家怎麼調？」',
      hotspots: const [
        ChallengeHotspot(
          labelZh: '魚露',
          left: 0.79,
          top: 0.51,
          width: 0.14,
          height: 0.42,
          hintZh: '看看料理台右邊裝著琥珀色液體的瓶子。',
        ),
        ChallengeHotspot(
          labelZh: '白飯',
          left: 0.39,
          top: 0.66,
          width: 0.25,
          height: 0.27,
          hintZh: '這是料理台中央的白飯。',
        ),
        ChallengeHotspot(
          labelZh: '筷子',
          left: 0.05,
          top: 0.79,
          width: 0.29,
          height: 0.19,
          hintZh: '這是料理台左下方的筷子。',
        ),
      ],
    ),
  );

  static final List<FamilyStory> _bundledStories = [
    _greetingStory,
    _homecomingStory,
    _mealtimeStory,
    _deliciousStory,
    _fishSauceStory,
  ];

  static final Set<String> _bundledStoryIds =
      _bundledStories.map((story) => story.id).toSet();
}
