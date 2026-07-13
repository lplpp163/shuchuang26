import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_relay.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/models/learning_attempt.dart';
import 'package:hometongue_tags/models/task_draft.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'ships five complete family scenes with fish sauce last',
    () async {
      final store = await AppStore.load();

      expect(
        store.stories.map((story) => story.id),
        [
          'family-greeting',
          'family-homecoming',
          'family-mealtime',
          'family-delicious',
          'nuoc-mam',
        ],
      );
      expect(store.stories.every((story) => story.isSample), isTrue);
      expect(
        store.stories.every(
          (story) =>
              story.audioPath != null &&
              story.lessonContent!.segments.every(
                (segment) => segment.audio?.path != null,
              ) &&
              story.lessonContent!.patterns.every(
                (pattern) => pattern.examples.every(
                  (example) => example.audio?.path != null,
                ),
              ),
        ),
        isTrue,
      );
      expect(
        store.stories.every(
          (story) =>
              story.lessonContent?.segments.isNotEmpty == true &&
              story.lessonContent?.patterns.isNotEmpty == true &&
              story.lessonContent!.patterns.every(
                (pattern) => pattern.examples.isNotEmpty,
              ) &&
              story.familyChallenge?.hotspots.isNotEmpty == true &&
              story.familyChallenge!.hotspots.any(
                (spot) =>
                    spot.labelZh == story.familyChallenge!.correctChoiceZh,
              ),
        ),
        isTrue,
      );
      expect(
        store.stories.map((story) => story.illustrationAsset).toSet(),
        containsAll([
          'assets/images/family-morning-game-v1.webp',
          'assets/images/family-homecoming-theater-v2.png',
          'assets/images/family-mealtime-theater-v2.png',
          'assets/images/family-kitchen-game-v2.webp',
        ]),
      );
      final fishSauce = store.stories.last;
      expect(
        fishSauce.audioPath,
        'asset://assets/audio/vietnamese_short_demo.mp3',
      );
      expect(fishSauce.title, startsWith('文化加分'));
      expect(fishSauce.vietnamese, 'Đây là nước mắm.');
      expect(fishSauce.pronunciationGuide, contains('nước'));
      expect(fishSauce.practiceChunks, hasLength(2));
      expect(fishSauce.lessonContent?.segments, hasLength(2));
      expect(fishSauce.lessonContent?.patterns, hasLength(1));
      expect(
        fishSauce.lessonContent?.segments.first.audio?.path,
        contains('vietnamese_chunk_day_la.mp3'),
      );
      expect(store.findStory('HT-NUOC-MAM')?.id, 'nuoc-mam');
      expect(store.findStory('hometongue://story/nuoc-mam')?.id, 'nuoc-mam');
      expect(store.findStory('unknown'), isNull);

      String normalized(String value) => value
          .toLowerCase()
          .replaceAll(RegExp(r'[·/,.!?，。！？“”]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      for (final story in store.stories) {
        final lesson = story.lessonContent!;
        expect(
          normalized(lesson.segments.map((segment) => segment.text).join(' ')),
          normalized(story.vietnamese),
          reason: '${story.id} segment text must rebuild the complete sentence',
        );
        expect(
          normalized(story.practiceChunks.join(' ')),
          normalized(story.vietnamese),
          reason: '${story.id} practice chunks must not drop a word',
        );
        expect(
          normalized(lesson.sentenceRomanization ?? ''),
          normalized(story.vietnamese),
          reason: '${story.id} reading guide must match the target text',
        );
        for (final segment in lesson.segments) {
          expect(
            normalized(segment.tokens.join(' ')),
            normalized(segment.text),
            reason: '${story.id}/${segment.id} token binding',
          );
        }
      }
    },
  );

  test('upserts legacy bundle while preserving user-created stories', () async {
    final oldSample = FamilyStory(
      id: 'nuoc-mam',
      title: '外婆的魚露',
      objectName: '廚房的魚露',
      vietnamese: 'Đây là nước mắm.',
      chinese: '這是魚露。',
      promptZh: '請回答',
      promptVi: 'Hãy trả lời',
      keyPhrases: const ['nước mắm'],
      draftConfidence: .9,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 12),
      isSample: true,
    );
    final familyMemory = FamilyStory(
      id: 'my-family-memory',
      title: '我們家的說法',
      objectName: '家人照片',
      vietnamese: 'Nhà mình.',
      chinese: '我們家。',
      promptZh: '跟家人說',
      promptVi: 'Hãy nói',
      keyPhrases: const ['Nhà mình'],
      draftConfidence: .8,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 12),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hometongue.initialized.v1': true,
      'hometongue.stories.v1': jsonEncode([
        oldSample.toJson(),
        familyMemory.toJson(),
      ]),
    });

    final store = await AppStore.load();

    expect(store.stories, hasLength(6));
    expect(store.stories.first.id, 'my-family-memory');
    expect(store.stories.first.title, '我們家的說法');
    expect(
      store.stories.where((story) => story.isSample).map((story) => story.id),
      [
        'family-greeting',
        'family-homecoming',
        'family-mealtime',
        'family-delicious',
        'nuoc-mam',
      ],
    );
    final upgradedFishSauce = store.storyById('nuoc-mam')!;
    expect(
      upgradedFishSauce.audioPath,
      'asset://assets/audio/vietnamese_short_demo.mp3',
    );
    expect(upgradedFishSauce.title, startsWith('文化加分'));
    expect(upgradedFishSauce.illustrationAsset, isNotNull);

    final reloaded = await AppStore.load();
    expect(
      reloaded.stories.map((story) => story.id),
      store.stories.map((story) => story.id),
    );
  });

  test('bundled upsert never overwrites a non-sample ID collision', () async {
    final oldSample = FamilyStory(
      id: 'nuoc-mam',
      title: '舊魚露示範',
      objectName: '魚露',
      vietnamese: 'nước mắm',
      chinese: '魚露',
      promptZh: '請回答',
      promptVi: 'Hãy trả lời',
      keyPhrases: const ['nước mắm'],
      draftConfidence: .9,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 12),
      isSample: true,
    );
    final collidingUserStory = FamilyStory(
      id: 'family-greeting',
      title: '使用者自己的問候',
      objectName: '自建內容',
      vietnamese: 'Chào bà.',
      chinese: '您好。',
      promptZh: '家人自己的版本',
      promptVi: 'Chào bà.',
      keyPhrases: const ['Chào bà'],
      draftConfidence: 1,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 12),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hometongue.initialized.v1': true,
      'hometongue.stories.v1': jsonEncode([
        oldSample.toJson(),
        collidingUserStory.toJson(),
      ]),
    });

    final store = await AppStore.load();

    expect(store.stories, hasLength(5));
    expect(store.storyById('family-greeting')?.title, '使用者自己的問候');
    expect(store.storyById('family-greeting')?.isSample, isFalse);
    expect(store.stories.last.id, 'nuoc-mam');
  });

  test(
    'JSON export is structured and states that media is not embedded',
    () async {
      final store = await AppStore.load();
      final decoded = jsonDecode(store.exportJson()) as Map<String, dynamic>;

      expect(decoded['schema'], 'hometongue-export-v1');
      expect(decoded['privacyNote'], contains('音檔、照片與本機路徑不會匯出'));
      expect(decoded['stories'], isNotEmpty);
      final firstStory =
          (decoded['stories'] as List<dynamic>).first as Map<String, dynamic>;
      expect(firstStory.containsKey('audioPath'), isFalse);
      expect(
          jsonEncode(firstStory), isNot(contains('vietnamese_chunk_day_la')));
    },
  );

  test(
    'new QR story identifiers use independent secure random hex values',
    () async {
      final store = await AppStore.load();
      const draft = TaskDraft(
        promptZh: '請回答',
        promptVi: 'Hãy trả lời',
        keyPhrases: ['mẹ'],
        confidence: .9,
        explanation: 'test',
      );

      final first = await store.addStory(
        title: '第一則',
        objectName: '照片',
        vietnamese: 'mẹ',
        chinese: '媽媽',
        draft: draft,
        humanConfirmed: true,
      );
      final second = await store.addStory(
        title: '第二則',
        objectName: '餐桌',
        vietnamese: 'ăn cơm',
        chinese: '吃飯',
        draft: draft,
        humanConfirmed: true,
      );

      expect(first.id, matches(RegExp(r'^[0-9a-f]{24}$')));
      expect(second.id, matches(RegExp(r'^[0-9a-f]{24}$')));
      expect(first.id, isNot(second.id));
    },
  );

  test('family story origin metadata survives JSON round-trip', () {
    final original = FamilyStory(
      id: 'story-club-origin',
      title: '把社團故事帶回家',
      objectName: '社團時間',
      vietnamese: 'Hôm nay con tham gia câu lạc bộ.',
      chinese: '我今天參加社團。',
      promptZh: '說給家人聽',
      promptVi: 'Hãy kể cho gia đình nghe.',
      keyPhrases: const ['Hôm nay', 'câu lạc bộ'],
      draftConfidence: .9,
      humanConfirmed: true,
      createdAt: DateTime.utc(2026, 7, 14),
      originStoryIdeaId: 'club',
      originStoryIdeaTitle: '社團',
    );

    final restored = FamilyStory.fromJson(original.toJson());

    expect(restored.originStoryIdeaId, 'club');
    expect(restored.originStoryIdeaTitle, '社團');
    expect(restored.vietnamese, original.vietnamese);

    final legacyJson = original.toJson()
      ..remove('originStoryIdeaId')
      ..remove('originStoryIdeaTitle');
    final legacy = FamilyStory.fromJson(legacyJson);
    expect(legacy.originStoryIdeaId, isNull);
    expect(legacy.originStoryIdeaTitle, isNull);
  });

  test('family relay is persistent and idempotent for the same baton',
      () async {
    final store = await AppStore.load();
    const draft = TaskDraft(
      promptZh: '說給家人聽',
      promptVi: 'Hãy kể cho gia đình nghe.',
      keyPhrases: ['Hôm nay', 'câu lạc bộ'],
      confidence: .9,
      explanation: 'test',
    );

    final first = await store.startFamilyRelay(
      seedId: 'club',
      seedTitle: '社團',
      childIntentZh: '我今天第一次參加社團。',
      childMemberId: 'child',
    );
    final duplicate = await store.startFamilyRelay(
      seedId: 'club',
      seedTitle: '社團',
      childIntentZh: '我今天第一次參加社團。',
      childMemberId: 'child',
    );
    expect(duplicate.id, first.id);
    expect(store.relays, hasLength(1));

    final story = await store.addStory(
      title: '把社團故事帶回家',
      objectName: '社團時間',
      vietnamese: 'Hôm nay con tham gia câu lạc bộ.',
      chinese: '我今天參加社團。',
      draft: draft,
      humanConfirmed: true,
      originStoryIdeaId: 'club',
      originStoryIdeaTitle: '社團',
    );
    final adultTurn = await store.completeAdultRelay(
      relayId: first.id,
      adultMemberId: 'grandma',
      storyId: story.id,
    );
    final repeatedAdultTurn = await store.completeAdultRelay(
      relayId: first.id,
      adultMemberId: 'grandma',
      storyId: story.id,
    );
    expect(adultTurn.stage, FamilyRelayStage.waitingForChild);
    expect(repeatedAdultTurn.familyStoryId, story.id);

    final attempt = await store.submitAttempt(
      storyId: story.id,
      childNote: 'Hôm nay con tham gia câu lạc bộ.',
    );
    final completed = await store.completeChildRelay(
      storyId: story.id,
      attemptId: attempt.id,
    );
    final repeatedCompletion = await store.completeChildRelay(
      storyId: story.id,
      attemptId: attempt.id,
    );
    expect(completed?.stage, FamilyRelayStage.completed);
    expect(repeatedCompletion?.childAttemptId, attempt.id);

    final otherAttempt = await store.submitAttempt(storyId: story.id);
    expect(
      store.completeChildRelay(
        storyId: story.id,
        attemptId: otherAttempt.id,
      ),
      throwsStateError,
    );

    final reloaded = await AppStore.load();
    final restored = reloaded.relayById(first.id);
    expect(restored?.stage, FamilyRelayStage.completed);
    expect(restored?.familyStoryId, story.id);
    expect(restored?.childAttemptId, attempt.id);
    expect(reloaded.storyById(story.id)?.originStoryIdeaId, 'club');
  });

  test('pilot summary aggregates stages and never exports family content',
      () async {
    final requestedAt = DateTime.utc(2024, 2, 3, 8);
    final stories = <FamilyStory>[
      for (final entry in const <(String, String?)>[
        ('SECRET_STORY_CLUB', 'media://SECRET_FAMILY_AUDIO_CLUB'),
        ('SECRET_STORY_LUNCH', null),
        ('SECRET_STORY_CLASS', 'C:/private/SECRET_FAMILY_AUDIO_CLASS.m4a'),
        ('SECRET_STORY_OTHER', 'blob:SECRET_FAMILY_AUDIO_OTHER'),
      ])
        FamilyStory(
          id: entry.$1,
          title: 'SECRET_FAMILY_TITLE_${entry.$1}',
          objectName: 'SECRET_PRIVATE_SCENE',
          vietnamese: 'SECRET_FAMILY_TARGET_${entry.$1}',
          chinese: 'SECRET_FAMILY_TRANSLATION_${entry.$1}',
          promptZh: 'SECRET_PRIVATE_PROMPT',
          promptVi: 'SECRET_PRIVATE_PROMPT_VI',
          keyPhrases: const ['SECRET_FAMILY_KEY_PHRASE'],
          draftConfidence: .9,
          humanConfirmed: true,
          createdAt: requestedAt,
          audioPath: entry.$2,
        ),
    ];
    final attempts = <LearningAttempt>[
      LearningAttempt(
        id: 'SECRET_ATTEMPT_LUNCH',
        storyId: 'SECRET_STORY_LUNCH',
        createdAt: requestedAt,
        result: ReviewResult.pending,
        audioPath: 'media://SECRET_CHILD_AUDIO_LUNCH',
        childNote: 'SECRET_CHILD_NOTE_LUNCH',
      ),
      LearningAttempt(
        id: 'SECRET_ATTEMPT_CLASS',
        storyId: 'SECRET_STORY_CLASS',
        createdAt: requestedAt,
        result: ReviewResult.pending,
        childNote: 'SECRET_CHILD_NOTE_CLASS',
      ),
      LearningAttempt(
        id: 'SECRET_ATTEMPT_OTHER',
        storyId: 'SECRET_STORY_OTHER',
        createdAt: requestedAt,
        result: ReviewResult.pending,
        audioPath: 'C:/private/SECRET_CHILD_AUDIO_OTHER.webm',
        childNote: 'SECRET_CHILD_NOTE_OTHER',
      ),
    ];
    final relays = <FamilyRelay>[
      FamilyRelay(
        id: 'SECRET_RELAY_FAMILY',
        seedId: 'family-sharing',
        seedTitle: 'SECRET_SEED_TITLE_FAMILY',
        childIntentZh: 'SECRET_CHILD_INTENT_FAMILY',
        childMemberId: 'SECRET_CHILD_MEMBER_FAMILY',
        requestedAt: requestedAt,
      ),
      FamilyRelay(
        id: 'SECRET_RELAY_CLUB',
        seedId: 'club',
        seedTitle: 'SECRET_SEED_TITLE_CLUB',
        childIntentZh: 'SECRET_CHILD_INTENT_CLUB',
        childMemberId: 'SECRET_CHILD_MEMBER_CLUB',
        requestedAt: requestedAt,
        adultMemberId: 'SECRET_ADULT_MEMBER_CLUB',
        familyStoryId: 'SECRET_STORY_CLUB',
        adultCompletedAt: requestedAt.add(const Duration(minutes: 2)),
      ),
      FamilyRelay(
        id: 'SECRET_RELAY_LUNCH',
        seedId: 'lunch',
        seedTitle: 'SECRET_SEED_TITLE_LUNCH',
        childIntentZh: 'SECRET_CHILD_INTENT_LUNCH',
        childMemberId: 'SECRET_CHILD_MEMBER_LUNCH',
        requestedAt: requestedAt,
        adultMemberId: 'SECRET_ADULT_MEMBER_LUNCH',
        familyStoryId: 'SECRET_STORY_LUNCH',
        adultCompletedAt: requestedAt.add(const Duration(minutes: 1)),
        childAttemptId: 'SECRET_ATTEMPT_LUNCH',
        completedAt: requestedAt.add(const Duration(minutes: 4)),
      ),
      FamilyRelay(
        id: 'SECRET_RELAY_CLASS',
        seedId: 'class',
        seedTitle: 'SECRET_SEED_TITLE_CLASS',
        childIntentZh: 'SECRET_CHILD_INTENT_CLASS',
        childMemberId: 'SECRET_CHILD_MEMBER_CLASS',
        requestedAt: requestedAt,
        adultMemberId: 'SECRET_ADULT_MEMBER_CLASS',
        familyStoryId: 'SECRET_STORY_CLASS',
        adultCompletedAt: requestedAt.add(const Duration(minutes: 3)),
        childAttemptId: 'SECRET_ATTEMPT_CLASS',
        completedAt: requestedAt.add(const Duration(minutes: 4)),
      ),
      FamilyRelay(
        id: 'SECRET_RELAY_FRIENDSHIP',
        seedId: 'friendship',
        seedTitle: 'SECRET_SEED_TITLE_FRIENDSHIP',
        childIntentZh: 'SECRET_CHILD_INTENT_FRIENDSHIP',
        childMemberId: 'SECRET_CHILD_MEMBER_FRIENDSHIP',
        requestedAt: requestedAt,
      ),
      FamilyRelay(
        id: 'SECRET_RELAY_OTHER',
        seedId: 'SECRET_FREE_TEXT_SEED',
        seedTitle: 'SECRET_SEED_TITLE_OTHER',
        childIntentZh: 'SECRET_CHILD_INTENT_OTHER',
        childMemberId: 'SECRET_CHILD_MEMBER_OTHER',
        requestedAt: requestedAt,
        adultMemberId: 'SECRET_ADULT_MEMBER_OTHER',
        familyStoryId: 'SECRET_STORY_OTHER',
        adultCompletedAt: requestedAt.add(const Duration(minutes: 4)),
        childAttemptId: 'SECRET_ATTEMPT_OTHER',
        completedAt: requestedAt.add(const Duration(minutes: 9)),
      ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hometongue.initialized.v1': true,
      'hometongue.stories.v1': jsonEncode(
        stories.map((story) => story.toJson()).toList(),
      ),
      'hometongue.attempts.v1': jsonEncode(
        attempts.map((attempt) => attempt.toJson()).toList(),
      ),
      'hometongue.family-relays.v1': jsonEncode(
        relays.map((relay) => relay.toJson()).toList(),
      ),
    });
    final store = await AppStore.load();

    final encoded = store.exportPilotSummaryJson();
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final totals = Map<String, dynamic>.from(decoded['totals'] as Map);
    final bySeed = <String, Map<String, dynamic>>{
      for (final value in decoded['bySeed'] as List<dynamic>)
        (value as Map<String, dynamic>)['seedId'] as String: value,
    };

    expect(decoded['schema'], 'hometongue-pilot-summary-v1');
    expect(decoded['privacyNote'], contains('只含彙總計數與平均時間'));
    expect(totals, {
      'started': 6,
      'adultCompleted': 4,
      'completed': 3,
      'familyAudioUsed': 3,
      'childAudioUsed': 2,
      'adultTurnAverageSeconds': 150.0,
      'childTurnAverageSeconds': 180.0,
    });
    expect(
      bySeed.keys,
      ['class', 'club', 'family-sharing', 'friendship', 'lunch', 'other'],
    );
    expect(bySeed['family-sharing'], {
      'seedId': 'family-sharing',
      'started': 1,
      'adultCompleted': 0,
      'completed': 0,
    });
    expect(bySeed['club'], {
      'seedId': 'club',
      'started': 1,
      'adultCompleted': 1,
      'completed': 0,
    });
    expect(bySeed['lunch'], {
      'seedId': 'lunch',
      'started': 1,
      'adultCompleted': 1,
      'completed': 1,
    });
    expect(bySeed['class'], {
      'seedId': 'class',
      'started': 1,
      'adultCompleted': 1,
      'completed': 1,
    });
    expect(bySeed['friendship'], {
      'seedId': 'friendship',
      'started': 1,
      'adultCompleted': 0,
      'completed': 0,
    });
    expect(bySeed['other'], {
      'seedId': 'other',
      'started': 1,
      'adultCompleted': 1,
      'completed': 1,
    });
    for (final bucket in bySeed.values) {
      expect(bucket['completed'] as int,
          lessThanOrEqualTo(bucket['adultCompleted'] as int));
      expect(bucket['adultCompleted'] as int,
          lessThanOrEqualTo(bucket['started'] as int));
    }

    for (final forbiddenKey in const [
      'childIntentZh',
      'childMemberId',
      'adultMemberId',
      'familyStoryId',
      'childAttemptId',
      'requestedAt',
      'adultCompletedAt',
      'completedAt',
      'audioPath',
    ]) {
      expect(encoded, isNot(contains('"$forbiddenKey"')));
    }
    for (final forbiddenValue in const [
      'SECRET_FREE_TEXT_SEED',
      'SECRET_CHILD_INTENT_',
      'SECRET_CHILD_MEMBER_',
      'SECRET_ADULT_MEMBER_',
      'SECRET_RELAY_',
      'SECRET_STORY_',
      'SECRET_ATTEMPT_',
      'SECRET_FAMILY_TARGET_',
      'SECRET_FAMILY_TRANSLATION_',
      'SECRET_FAMILY_AUDIO_',
      'SECRET_CHILD_AUDIO_',
      '2024-02-03T08:00:00.000Z',
      '2024-02-03T08:01:00.000Z',
      '2024-02-03T08:02:00.000Z',
      '2024-02-03T08:03:00.000Z',
      '2024-02-03T08:04:00.000Z',
      '2024-02-03T08:09:00.000Z',
    ]) {
      expect(encoded, isNot(contains(forbiddenValue)));
    }
  });

  test(
    'adult gate stores a salted verifier and rejects the wrong PIN',
    () async {
      final store = await AppStore.load();

      await store.acceptPrivacy(adultPin: '2468');

      expect(store.privacyConsent, isTrue);
      expect(await store.verifyAdultPin('2468'), isTrue);
      expect(await store.verifyAdultPin('1234'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hometongue.adult-pin-verifier.v2'),
        isNot('2468'),
      );
      expect(prefs.getString('hometongue.adult-pin-salt.v2'), isNotEmpty);
      expect(prefs.getString('hometongue.adult-pin-hash.v1'), isNull);
    },
  );

  test('adult gate pauses repeated guesses after five failures', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hometongue.privacy-consent.v1': true,
      // Structurally unreadable v2 values fail closed without spending five
      // more real KDF rounds; the KDF path is covered by the test above.
      'hometongue.adult-pin-verifier.v2': 'invalid',
      'hometongue.adult-pin-salt.v2': 'invalid',
    });
    final store = await AppStore.load();

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(await store.verifyAdultPin('0000'), isFalse);
    }

    expect(store.adultPinLocked, isTrue);
    expect(store.pinLockRemainingSeconds, greaterThan(0));
    expect(store.remainingPinAttempts, 0);
    expect(await store.verifyAdultPin('2468'), isFalse);

    final reloaded = await AppStore.load();
    expect(reloaded.adultPinLocked, isTrue);
    expect(reloaded.remainingPinAttempts, 0);
  });

  test('legacy fast PIN hash upgrades after one successful verification',
      () async {
    const salt = 'legacy-salt';
    final legacyHash = sha256.convert(utf8.encode('$salt:2468')).toString();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hometongue.privacy-consent.v1': true,
      'hometongue.adult-pin-hash.v1': legacyHash,
      'hometongue.adult-pin-salt.v1': salt,
    });
    final store = await AppStore.load();

    expect(await store.verifyAdultPin('2468'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('hometongue.adult-pin-verifier.v2'), isNotEmpty);
    expect(prefs.getString('hometongue.adult-pin-salt.v2'), isNotEmpty);
    expect(prefs.getString('hometongue.adult-pin-hash.v1'), isNull);
    expect(prefs.getString('hometongue.adult-pin-salt.v1'), isNull);
  });

  test('family review records when the reply was actually heard', () async {
    final store = await AppStore.load();
    final pending = await store.submitAttempt(
      storyId: 'nuoc-mam',
      childNote: 'Đây là nước mắm.',
    );
    final beforeReview = DateTime.now();

    await store.reviewAttempt(
      attemptId: pending.id,
      result: ReviewResult.understood,
    );

    final reviewed = store.attempts.firstWhere(
      (attempt) => attempt.id == pending.id,
    );
    expect(reviewed.reviewedAt, isNotNull);
    expect(reviewed.reviewedAt!.isBefore(beforeReview), isFalse);
  });

  test('scene game completions count per story and survive reload', () async {
    final store = await AppStore.load();

    await store.completeSceneGame('nuoc-mam');
    await store.completeSceneGame('nuoc-mam');
    await store.completeSceneGame('family-dinner');

    expect(store.scenePlayCount('nuoc-mam'), 2);
    expect(store.scenePlayCount('family-dinner'), 1);
    expect(store.scenePlayCount('not-played'), 0);
    expect(store.totalScenePlays, 3);
    expect(store.cultureCardCount, 2);

    final reloaded = await AppStore.load();

    expect(reloaded.scenePlayCount('nuoc-mam'), 2);
    expect(reloaded.scenePlayCount('family-dinner'), 1);
    expect(reloaded.totalScenePlays, 3);
    expect(reloaded.cultureCardCount, 2);
  });

  test('eraseEverything clears persisted scene games and family relays',
      () async {
    final store = await AppStore.load();
    await store.completeSceneGame('nuoc-mam');
    await store.completeSceneGame('nuoc-mam');
    await store.startFamilyRelay(
      seedId: 'lunch',
      seedTitle: '午餐',
      childIntentZh: '今天午餐有一道菜我很喜歡。',
      childMemberId: 'child',
    );

    await store.eraseEverything(() async {});

    expect(store.scenePlayCount('nuoc-mam'), 0);
    expect(store.totalScenePlays, 0);
    expect(store.cultureCardCount, 0);
    expect(store.relays, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('hometongue.scene-games.v1'), isFalse);
    expect(prefs.containsKey('hometongue.family-relays.v1'), isFalse);

    final reloaded = await AppStore.load();
    expect(reloaded.scenePlayCount('nuoc-mam'), 0);
    expect(reloaded.totalScenePlays, 0);
    expect(reloaded.cultureCardCount, 0);
    expect(reloaded.relays, isEmpty);
  });
}
