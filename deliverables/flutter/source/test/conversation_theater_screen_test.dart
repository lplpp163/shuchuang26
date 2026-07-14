import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/core/app_theme.dart';
import 'package:hometongue_tags/models/conversation_episode.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/screens/conversation_theater_screen.dart';
import 'package:hometongue_tags/services/local_media_service.dart';

class _SilentMediaService extends LocalMediaService {
  final List<String> spoken = [];
  final List<double> spokenRates = [];
  final List<String> played = [];
  final List<double> playedSpeeds = [];

  @override
  Future<void> speakText(
    String text, {
    String languageTag = 'vi-VN',
    double rate = LocalMediaService.normalSpeechRate,
  }) async {
    spoken.add(text);
    spokenRates.add(rate);
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    played.add(path);
    playedSpeeds.add(speed);
  }

  @override
  Future<void> dispose() async {}
}

class _MissingFamilyRecordingMediaService extends _SilentMediaService {
  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    played.add(path);
    throw StateError('recording was cleared');
  }
}

class _FakeSpeechRecognizer implements ConversationSpeechRecognizer {
  _FakeSpeechRecognizer(this.results);

  final List<ConversationSpeechResult> results;
  int listenCount = 0;

  @override
  Future<ConversationSpeechResult> listen({
    required String languageTag,
    required Duration listenFor,
  }) async {
    final result = results[listenCount];
    listenCount += 1;
    return result;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // A phone-sized viewport catches the child flow's real scrolling behavior.
    TestWidgetsFlutterBinding
        .instance.platformDispatcher.textScaleFactorTestValue = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearTextScaleFactorTestValue();
  });

  test('catalog contains five playable 60–90 second branching episodes', () {
    expect(ConversationEpisodeCatalog.defaults, hasLength(5));
    expect(
      ConversationEpisodeCatalog.defaults.map((episode) => episode.id).toSet(),
      hasLength(5),
    );
    for (final episode in ConversationEpisodeCatalog.defaults) {
      expect(episode.isPlayable, isTrue, reason: episode.title);
      expect(episode.estimatedDurationSeconds, inInclusiveRange(60, 90));
      expect(episode.totalTurns, 3);
    }
  });

  test('choices remain visible in distinct second and third story beats', () {
    for (final episode in ConversationEpisodeCatalog.defaults) {
      final opening = episode.promptById(episode.openingPromptId);
      final branchIds = opening.choices
          .map((choice) => choice.nextPromptId)
          .whereType<String>()
          .toList(growable: false);

      expect(branchIds, hasLength(opening.choices.length), reason: episode.id);
      expect(branchIds.toSet(), hasLength(opening.choices.length),
          reason: '${episode.id} should not merge immediately after turn one');

      final branchA = episode.promptById(branchIds[0]);
      final branchB = episode.promptById(branchIds[1]);
      expect(branchA.step, 2, reason: episode.id);
      expect(branchB.step, 2, reason: episode.id);
      expect(branchA.elderLine.targetText, isNot(branchB.elderLine.targetText),
          reason: '${episode.id} elder dialogue should remember the choice');
      expect(branchA.stageDirectionZh, isNot(branchB.stageDirectionZh),
          reason: '${episode.id} stage direction should remember the choice');

      final thirdBranchIds = <String>[];
      final thirdBranchSignatures = <String>[];
      for (final branch in [branchA, branchB]) {
        expect(branch.choices, hasLength(greaterThanOrEqualTo(2)),
            reason: branch.id);
        for (final choice in branch.choices) {
          final thirdId = choice.nextPromptId!;
          final thirdPrompt = episode.promptById(thirdId);
          thirdBranchIds.add(thirdId);
          thirdBranchSignatures.add(
            '${thirdPrompt.elderLine.targetText}|${thirdPrompt.stageDirectionZh}',
          );
          expect(thirdPrompt.step, 3, reason: branch.id);
          expect(thirdPrompt.choices, hasLength(greaterThanOrEqualTo(2)),
              reason: thirdPrompt.id);
        }
      }
      expect(thirdBranchIds.toSet(), hasLength(thirdBranchIds.length),
          reason: '${episode.id} should preserve the whole two-choice path');
      expect(
        thirdBranchSignatures.toSet(),
        hasLength(thirdBranchSignatures.length),
        reason: '${episode.id} third act should remember both earlier beats',
      );
    }
  });

  test('keyword matching rejects fragments and transcripts with two intents',
      () {
    final prompt =
        ConversationEpisodeCatalog.homecoming.promptById('home-door');

    expect(prompt.choiceForTranscript('Cháu về rồi ạ')?.id, 'came-home');
    expect(prompt.choiceForTranscript('Chau ve roi a')?.id, 'came-home');
    expect(prompt.choiceForTranscript('我今天回來了')?.id, 'came-home');
    expect(prompt.choiceForTranscript('về'), isNull);
    expect(prompt.choiceForTranscript('cháu'), isNull);
    expect(prompt.choiceForTranscript('Cháu về rồi nhưng hơi mệt'), isNull);
    expect(
      prompt
          .matchingChoicesForTranscript('我回來了，可是也有點累')
          .map((choice) => choice.id),
      containsAll(<String>['came-home', 'a-bit-tired']),
    );
  });

  testWidgets(
      'manual elder line waits for a tap, then plays and retires the listen CTA',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _SilentMediaService();
    final opening =
        ConversationEpisodeCatalog.homecoming.promptById('home-door').elderLine;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listen = find.byKey(const ValueKey('listen-elder-line'));
    expect(media.played, isEmpty);
    expect(listen, findsOneWidget);
    expect(
      tester.getSize(listen).height,
      greaterThanOrEqualTo(60),
      reason: 'The explicit first-line control must be easy to tap.',
    );
    expect(
      find.byKey(const ValueKey('replay-elder-line')),
      findsNothing,
      reason: 'Do not show two controls for the same first playback.',
    );
    final romanization = tester.widget<Text>(
      find.byKey(const ValueKey('elder-line-romanization')),
    );
    expect(romanization.style?.fontSize, greaterThanOrEqualTo(14));

    await tester.ensureVisible(listen);
    await tester.tap(listen);
    await tester.pumpAndSettle();

    expect(media.played, [opening.audioPath]);
    expect(media.spoken, isEmpty);
    expect(listen, findsNothing);
    final replay = find.byKey(const ValueKey('replay-elder-line'));
    expect(replay, findsOneWidget);
    expect(tester.getSize(replay).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(replay).height, greaterThanOrEqualTo(48));
  });

  testWidgets(
      'Pixel 7 keeps the microphone visible and every listening segment plays independently',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _SilentMediaService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prepare-came-home')));
    await tester.pumpAndSettle();

    const disclosure = '系統只幫你把聲音寫成字；你想說什麼由你確認，家裡怎麼說由家人確認。聽寫不準也不會卡住故事。';
    final microphone = find.byKey(const ValueKey('theater-microphone'));
    expect(
      tester.getRect(find.text(disclosure)).bottom,
      lessThan(tester.getRect(microphone).top),
    );

    final cameHomeAudio = ConversationEpisodeCatalog.homecoming
        .promptById('home-door')
        .choices
        .first
        .line
        .audioPath!;
    expect(media.played, [cameHomeAudio]);
    expect(media.playedSpeeds, [1]);
    expect(media.spoken, isEmpty);
    final microphoneRect = tester.getRect(microphone);
    expect(microphoneRect.top, greaterThanOrEqualTo(0));
    expect(microphoneRect.bottom, lessThanOrEqualTo(915));
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('practice-listening-tools-came-home')),
          )
          .bottom,
      lessThanOrEqualTo(915),
    );

    await tester.tap(
      find.byKey(const ValueKey('practice-listening-tools-came-home')),
    );
    await tester.pumpAndSettle();
    expect(find.text('慢慢聽這一句'), findsOneWidget);
    expect(find.textContaining('不是發音評分'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('practice-slow-came-home')));
    await tester.pumpAndSettle();
    expect(media.played.last, cameHomeAudio);
    expect(
      media.playedSpeeds.last,
      LocalMediaService.slowedRecordingSpeed,
    );
    expect(media.playedSpeeds.last, isNot(media.playedSpeeds.first));

    for (var index = 0; index < 2; index++) {
      await tester.tap(
        find.byKey(ValueKey('practice-segment-came-home-$index')),
      );
      await tester.pumpAndSettle();
    }
    expect(
      media.spoken.skip(media.spoken.length - 2),
      ['cháu', 'về rồi ạ'],
    );
    expect(
      media.spokenRates.skip(media.spokenRates.length - 2),
      [
        LocalMediaService.segmentSpeechRate,
        LocalMediaService.segmentSpeechRate,
      ],
    );
  });

  testWidgets(
      'voice intent changes the scene, branches the story, and creates one card',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _SilentMediaService();
    final speech = _FakeSpeechRecognizer([
      const ConversationSpeechResult.heard(
        'Cháu về rồi ạ',
        confidence: .91,
      ),
      const ConversationSpeechResult.heard(
        'Cháu ôm bà trước ạ',
        confidence: .9,
      ),
    ]);
    final delivered = <ConversationStoryCard>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          speechRecognizer: speech,
          autoPlayElderVoice: false,
          onStoryCardCreated: delivered.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cháu về rồi à?'), findsOneWidget);
    expect(find.text('你回來啦？'), findsOneWidget);
    expect(find.text('cháu / về rồi / à'), findsOneWidget);
    expect(find.textContaining('門裡傳來外婆的聲音'), findsOneWidget);
    expect(find.byKey(const ValueKey('intent-came-home')), findsNothing);
    expect(
        find.byKey(const ValueKey('practice-coach-came-home')), findsNothing);

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-came-home')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('practice-coach-came-home')), findsOneWidget);
    expect(find.text('Cháu về rồi ạ.'), findsOneWidget);
    expect(find.text('cháu / về rồi / ạ'), findsOneWidget);
    expect(find.text('Bà nhớ cháu quá!'), findsNothing);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('practice-listen-came-home')),
    );
    await tester.pumpAndSettle();
    expect(
      media.played,
      contains(
        ConversationEpisodeCatalog.homecoming
            .promptById('home-door')
            .choices
            .first
            .line
            .audioPath,
      ),
    );

    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();

    expect(speech.listenCount, 1);
    expect(find.text('Bà nhớ cháu quá!'), findsOneWidget);
    expect(find.textContaining('聽寫文字：Cháu về rồi ạ'), findsOneWidget);
    expect(find.textContaining('故事依你確認的「我回來了。」'), findsOneWidget);
    expect(find.textContaining('門打開了'), findsWidgets);
    expect(find.textContaining('我回來了'), findsWidgets);
    final outcomeCharacterArt =
        tester.widgetList<Image>(find.byType(Image)).where(
              (image) =>
                  image.image is AssetImage &&
                  (image.image as AssetImage).assetName ==
                      'assets/images/family-homecoming-theater-v2.png',
            );
    expect(outcomeCharacterArt, isNotEmpty);
    expect(
      find.byKey(const ValueKey('elder-action-came-home')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-theater-story')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay vui không?'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-new-friend')));
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-with-scene-choice')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('故事多了一位新朋友'), findsWidgets);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-theater-story')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Mình rửa tay rồi ăn cơm nhé?'),
      findsOneWidget,
    );

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-hug-first')));
    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();
    expect(find.textContaining('先送外婆一個大抱抱'), findsWidgets);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-theater-story')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('theater-celebration')), findsOneWidget);
    expect(find.byKey(const ValueKey('generated-story-card')), findsOneWidget);
    expect(find.text('我們把故事演完了！'), findsOneWidget);
    expect(find.textContaining('沒有分數'), findsOneWidget);
    expect(delivered, hasLength(1));
    expect(delivered.single.moments, hasLength(3));
    expect(delivered.single.moments.first.transcript, 'Cháu về rồi ạ');
    expect(delivered.single.moments[1].choiceId, 'new-friend');
    expect(delivered.single.endingTitleZh, '先送外婆一個大抱抱');

    // Rebuilding the completion state never emits the family artifact twice.
    await tester.pumpWidget(Container());
    await tester.pump();
    expect(delivered, hasLength(1));
  });

  testWidgets('family opening recording replaces TTS and is clearly labelled',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = _SilentMediaService();
    final familyVoice = FamilyEpisodeVoice(
      episodeId: ConversationEpisodeCatalog.homecoming.id,
      adultMemberId: 'grandma',
      targetText: 'Con về rồi nè.',
      translationZh: '我回來囉。',
      romanization: 'con / về rồi / nè',
      updatedAt: DateTime.utc(2026, 7, 13),
      localRecordingReference: 'media://grandma-homecoming',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          familyEpisodeVoice: familyVoice,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Con về rồi nè.'), findsOneWidget);
    expect(find.text('我回來囉。'), findsOneWidget);
    expect(find.text('con / về rồi / nè'), findsOneWidget);
    expect(find.text('家人原音'), findsOneWidget);
    expect(find.text('Cháu về rồi à?'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('listen-elder-line')));
    await tester.pumpAndSettle();
    expect(media.played, ['media://grandma-homecoming']);
    expect(media.spoken, isEmpty);
  });

  testWidgets('a branch prompt uses its own reviewed family recording',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = _SilentMediaService();
    const branchRecording = 'media://grandma-homecoming-happy';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          familyEpisodeVoices: [
            FamilyEpisodeVoice(
              episodeId: 'theater-homecoming',
              promptId: 'home-happy-day',
              adultMemberId: 'grandma',
              targetText: 'Hôm nay ở trường vui không con?',
              translationZh: '今天在學校開心嗎？',
              romanization: 'hôm nay / ở trường / vui không con',
              updatedAt: DateTime.utc(2026, 7, 13),
              localRecordingReference: branchRecording,
            ),
          ],
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-came-home')));
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-with-scene-choice')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-theater-story')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hôm nay ở trường vui không con?'), findsOneWidget);
    expect(find.text('今天在學校開心嗎？'), findsOneWidget);
    expect(find.text('家人原音'), findsOneWidget);
    expect(find.text('Hôm nay vui không?'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('listen-elder-line')));
    await tester.pumpAndSettle();
    expect(media.played.last, branchRecording);
  });

  testWidgets('reviewed family wording without audio uses labelled device TTS',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = _SilentMediaService();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.garden,
          media: media,
          familyEpisodeVoice: FamilyEpisodeVoice(
            episodeId: ConversationEpisodeCatalog.garden.id,
            adultMemberId: 'grandma',
            targetText: 'Mình tưới cây nha.',
            translationZh: '我們來澆花喔。',
            romanization: 'mình / tưới cây / nha',
            updatedAt: DateTime.utc(2026, 7, 13),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('裝置朗讀 · 家庭說法'), findsOneWidget);
    expect(media.spoken, contains('Mình tưới cây nha.'));
    expect(media.played, isEmpty);
  });

  testWidgets('missing bundled theater audio falls back to labelled device TTS',
      (tester) async {
    final media = _MissingFamilyRecordingMediaService();
    final opening =
        ConversationEpisodeCatalog.homecoming.promptById('home-door').elderLine;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('listen-elder-line')));
    await tester.pumpAndSettle();

    expect(media.played, [opening.audioPath]);
    expect(media.spoken, [opening.targetText]);
    expect(find.text('預錄示範暫不可用 · 裝置朗讀'), findsOneWidget);
    expect(find.textContaining('已改用裝置朗讀'), findsOneWidget);
  });

  testWidgets(
      'missing family recording falls back to labelled device narration',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = _MissingFamilyRecordingMediaService();
    const familyLine = 'Mình tưới cây nha.';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.garden,
          media: media,
          familyEpisodeVoice: FamilyEpisodeVoice(
            episodeId: ConversationEpisodeCatalog.garden.id,
            adultMemberId: 'grandma',
            targetText: familyLine,
            translationZh: '我們來澆花喔。',
            romanization: 'mình / tưới cây / nha',
            updatedAt: DateTime.utc(2026, 7, 13),
            localRecordingReference: 'media://missing-family-recording',
          ),
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('listen-elder-line')));
    await tester.pumpAndSettle();

    expect(media.played, ['media://missing-family-recording']);
    expect(media.spoken, [familyLine]);
    expect(find.text('家人原音暫不可用 · 裝置朗讀'), findsOneWidget);
    expect(find.textContaining('已改用裝置朗讀家庭說法'), findsOneWidget);
  });

  testWidgets(
      'unsupported speech offers coaching and lets the child confirm the selected intent',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speech = _FakeSpeechRecognizer([
      const ConversationSpeechResult.unavailable(
        ConversationSpeechStatus.unsupported,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: _SilentMediaService(),
          speechRecognizer: speech,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-came-home')));
    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('speech-repair')), findsOneWidget);
    expect(find.textContaining('故事不用卡住'), findsOneWidget);
    expect(find.byKey(const ValueKey('speech-pronunciation-help')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('speech-self-confirm')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('scene-choice-came-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scene-choice-a-bit-tired')),
      findsOneWidget,
    );
    expect(find.textContaining('答錯'), findsNothing);
    expect(find.textContaining('發音分數'), findsNothing);
    final firstFallbackRect = tester.getRect(
      find.byKey(const ValueKey('scene-choice-came-home')),
    );
    expect(firstFallbackRect.top, greaterThanOrEqualTo(0));
    expect(firstFallbackRect.bottom, lessThanOrEqualTo(900));

    await _tapVisible(
        tester, find.byKey(const ValueKey('speech-self-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('門打開了'), findsWidgets);
    expect(find.textContaining('你用圖卡選了「我回來了。」'), findsOneWidget);
    expect(find.textContaining('系統聽成'), findsNothing);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('continue-theater-story')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay vui không?'), findsOneWidget);
    expect(find.text('Cháu muốn nghỉ hay uống nước?'), findsNothing);
  });

  testWidgets(
      'vendor confidence is not a pronunciation gate when the selected phrase matches',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = _SilentMediaService();
    final speech = _FakeSpeechRecognizer([
      const ConversationSpeechResult.heard(
        'Cháu về rồi ạ',
        confidence: .18,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: media,
          speechRecognizer: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      media.played.first,
      ConversationEpisodeCatalog.homecoming
          .promptById('home-door')
          .elderLine
          .audioPath,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('prepare-came-home')));
    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('speech-repair')), findsNothing);
    expect(find.textContaining('聽寫文字：Cháu về rồi ạ'), findsOneWidget);
    expect(find.textContaining('故事依你確認的「我回來了。」'), findsOneWidget);
    expect(find.text('Bà nhớ cháu quá!'), findsOneWidget);
    expect(find.textContaining('發音正確'), findsNothing);
  });

  testWidgets('common words and multiple matches both ask the child to clarify',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speech = _FakeSpeechRecognizer([
      const ConversationSpeechResult.heard('cháu', confidence: .9),
      const ConversationSpeechResult.heard(
        'Cháu về rồi nhưng hơi mệt',
        confidence: .9,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ConversationTheaterScreen(
          episode: ConversationEpisodeCatalog.homecoming,
          media: _SilentMediaService(),
          speechRecognizer: speech,
          autoPlayElderVoice: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('prepare-came-home')));
    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒找到完整關鍵詞'), findsOneWidget);
    expect(find.text('Bà nhớ cháu quá!'), findsNothing);

    await _tapVisible(tester, find.byKey(const ValueKey('theater-microphone')));
    await tester.pumpAndSettle();
    expect(find.textContaining('像有兩個意思'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('scene-choice-came-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scene-choice-a-bit-tired')),
      findsOneWidget,
    );
    expect(find.text('Bà nhớ cháu quá!'), findsNothing);
    expect(find.textContaining('門打開了'), findsNothing);
  });

  testWidgets(
      'auto reply advances after playback and keeps the changed world on the next prompt',
      (tester) async {
    await _pumpAutoAdvanceTheater(tester);
    await _chooseAutoAdvanceCameHome(tester);

    expect(
      find.byKey(const ValueKey('story-consequence-home-door-open')),
      findsOneWidget,
    );
    expect(find.text('外婆已在圖上回話'), findsOneWidget);
    expect(find.text('門打開了！'), findsWidgets);
    expect(
      find.byKey(const ValueKey('elder-action-came-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scene-state-home-door-open')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('story-auto-advance-progress')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();

    expect(find.text('Hôm nay vui không?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scene-state-home-door-open')),
      findsOneWidget,
    );
  });

  testWidgets('child can pause auto reply and continue only when ready',
      (tester) async {
    await _pumpAutoAdvanceTheater(tester);
    await _chooseAutoAdvanceCameHome(tester);

    final pause = find.byKey(const ValueKey('pause-story-auto-advance'));
    await tester.ensureVisible(pause);
    await tester.tap(pause);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Bà nhớ cháu quá!'), findsOneWidget);
    expect(find.text('Hôm nay vui không?'), findsNothing);
    expect(find.text('我看完了，接著演'), findsOneWidget);

    final continueButton = find.byKey(const ValueKey('continue-theater-story'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();
    expect(find.text('Hôm nay vui không?'), findsOneWidget);
  });

  testWidgets('reduced motion and accessible navigation always stay manual',
      (tester) async {
    await _pumpAutoAdvanceTheater(
      tester,
      mediaQueryData: const MediaQueryData(
        size: Size(430, 900),
        disableAnimations: true,
        accessibleNavigation: true,
      ),
    );
    await _chooseAutoAdvanceCameHome(tester);

    expect(
      find.byKey(const ValueKey('story-auto-advance-progress')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Bà nhớ cháu quá!'), findsOneWidget);
    expect(find.text('Hôm nay vui không?'), findsNothing);
    expect(
      find.byKey(const ValueKey('continue-theater-story')),
      findsOneWidget,
    );
  });

  testWidgets('manual continue invalidates the old auto timer', (tester) async {
    await _pumpAutoAdvanceTheater(tester);
    await _chooseAutoAdvanceCameHome(tester);

    final continueButton = find.byKey(const ValueKey('continue-theater-story'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();
    expect(find.text('Hôm nay vui không?'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Hôm nay vui không?'), findsOneWidget);
    expect(find.text('Mình rửa tay rồi ăn cơm nhé?'), findsNothing);
  });

  testWidgets('replaying the elder line cancels automatic continuation',
      (tester) async {
    await _pumpAutoAdvanceTheater(tester);
    await _chooseAutoAdvanceCameHome(tester);

    final replay = find.byKey(const ValueKey('replay-elder-line'));
    await tester.ensureVisible(replay);
    await tester.pump();
    await tester.tap(replay);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Bà nhớ cháu quá!'), findsOneWidget);
    expect(find.text('Hôm nay vui không?'), findsNothing);
    expect(find.text('我看完了，接著演'), findsOneWidget);
  });

  test('confirmed family nickname personalizes the reviewed script', () {
    final episode =
        ConversationEpisodeCatalog.homecoming.withElderDisplayName('玲玲阿嬤');

    expect(episode.elderName, '玲玲阿嬤');
    expect(episode.subtitle, contains('玲玲阿嬤'));
    expect(episode.subtitle, isNot(contains('外婆')));
    expect(
      episode.prompts
          .expand((prompt) => prompt.choices)
          .any((choice) => choice.storyBeatZh.contains('玲玲阿嬤')),
      isTrue,
    );
    expect(
      episode.prompts.first.choices.first.line.targetText,
      ConversationEpisodeCatalog
          .homecoming.prompts.first.choices.first.line.targetText,
    );
  });
}

Future<void> _pumpAutoAdvanceTheater(
  WidgetTester tester, {
  MediaQueryData? mediaQueryData,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theater = ConversationTheaterScreen(
    episode: ConversationEpisodeCatalog.homecoming,
    media: _SilentMediaService(),
    autoPlayElderVoice: false,
    autoAdvanceReplies: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: mediaQueryData == null
          ? theater
          : MediaQuery(data: mediaQueryData, child: theater),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseAutoAdvanceCameHome(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('prepare-came-home')),
  );
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('continue-with-scene-choice')),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
