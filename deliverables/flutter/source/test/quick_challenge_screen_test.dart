import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/education_opportunity.dart';
import 'package:hometongue_tags/models/family_relay.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/screens/quick_challenge_screen.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:hometongue_tags/services/local_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentMediaService extends LocalMediaService {
  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local generator turns a few natural lines into a reviewed scene',
      () async {
    const generator = LocalQuickChallengeDraftGenerator();

    final draft = await generator.generate(
      sourceText: '放學回家，想教孩子說「我回來了」\n希望一進門就跟家人說',
      languageName: '越南語',
    );

    expect(draft.targetText, 'Con về rồi ạ.');
    expect(draft.translationZh, '我回來了。');
    expect(draft.chunks, ['Con về', 'rồi ạ']);
    expect(draft.illustrationAsset, contains('homecoming'));
    expect(draft.familyChallenge!.hotspots, isNotEmpty);
    expect(draft.requiresTargetReview, isFalse);
    expect(generator.disclosure, contains('五張圖庫情境'));
    expect(generator.disclosure, isNot(contains('AI')));
  });

  test('unknown wording is kept for family review instead of fake translation',
      () async {
    const generator = LocalQuickChallengeDraftGenerator();

    final draft = await generator.generate(
      sourceText: '在陽台澆花時，想教孩子說「花今天長高了」',
      languageName: '客語',
    );

    expect(draft.targetText, '花今天長高了');
    expect(draft.requiresTargetReview, isTrue);
    expect(draft.generatorNote, contains('家裡真正的說法'));
  });

  test('unsupported scenes do not receive a mismatched picture game', () async {
    const generator = LocalQuickChallengeDraftGenerator();

    final draft = await generator.generate(
      sourceText: '在公園踢球時，想教孩子說「換你了」',
      languageName: '越南語',
    );

    expect(draft.requiresTargetReview, isTrue);
    expect(draft.familyChallenge, isNull);
  });

  test('garden description uses the matching balcony illustration', () async {
    const generator = LocalQuickChallengeDraftGenerator();

    final draft = await generator.generate(
      sourceText: '在陽台澆花，想教孩子說「我來澆花」',
      languageName: '越南語',
    );

    expect(draft.targetText, 'Cháu tưới cây ạ.');
    expect(draft.illustrationAsset, contains('garden-theater'));
    expect(draft.familyChallenge?.correctChoiceZh, '澆水壺');
  });

  test('school-life story seed stays untranslated until family review',
      () async {
    const generator = LocalQuickChallengeDraftGenerator();
    final clubIdea = StoryIdeaCatalog.next.singleWhere(
      (idea) => idea.id == 'club',
    );

    final draft = await generator.generate(
      sourceText: clubIdea.draftSource,
      languageName: '越南語',
    );

    expect(draft.targetText, '我今天參加社團……');
    expect(draft.requiresTargetReview, isTrue);
    expect(draft.illustrationAsset, contains('homecoming'));
    expect(draft.familyChallenge, isNotNull);
    expect(draft.familyChallenge?.cultureNoteZh, contains('社團裡哪一刻'));
    expect(draft.familyChallenge?.hotspots, isNotEmpty);
  });

  testWidgets('family can create the generated game without recording audio',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    FamilyStory? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickChallengeScreen(
            store: store,
            media: _SilentMediaService(),
            onCreated: (story) => created = story,
            initialSourceText: '早上起床看到外婆，想教孩子說「外婆早安」',
          ),
        ),
      ),
    );
    final sourceField = tester.widget<TextField>(
      find.byKey(const ValueKey('quick-challenge-source')),
    );
    expect(sourceField.controller?.text, contains('外婆早安'));
    await tester.tap(
      find.byKey(const ValueKey('generate-quick-challenge-draft')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cháu chào bà ạ.'), findsOneWidget);
    final confirmation = find.byType(CheckboxListTile);
    await tester.ensureVisible(confirmation);
    await tester.pumpAndSettle();
    await tester.tap(confirmation);
    await tester.pump();

    final save = find.byKey(const ValueKey('save-quick-challenge'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.audioPath, isNull);
    expect(created!.lessonContent?.languageTag, 'vi-VN');
    expect(created!.familyChallenge?.hotspots, isNotEmpty);
    expect(created!.illustrationAsset, contains('morning'));
  });

  testWidgets('untranslated school seed cannot be saved as Vietnamese',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    FamilyStory? created;
    final clubIdea = StoryIdeaCatalog.next.singleWhere(
      (idea) => idea.id == 'club',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickChallengeScreen(
            store: store,
            media: _SilentMediaService(),
            onCreated: (story) => created = story,
            initialSourceText: clubIdea.draftSource,
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('generate-quick-challenge-draft')),
    );
    await tester.pumpAndSettle();

    final confirmation = find.byType(CheckboxListTile);
    await tester.ensureVisible(confirmation);
    await tester.pumpAndSettle();
    await tester.tap(confirmation);
    await tester.pump();

    final save = find.byKey(const ValueKey('save-quick-challenge'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();

    expect(created, isNull);
    expect(find.textContaining('目前還是中文提示'), findsOneWidget);

    final target = find.byKey(const ValueKey('quick-challenge-target'));
    await tester.ensureVisible(target);
    await tester.enterText(target, 'Hôm nay con tham gia câu lạc bộ.');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(confirmation).value, isFalse);

    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(created?.vietnamese, 'Hôm nay con tham gia câu lạc bộ.');
  });

  testWidgets('story seed save keeps origin and hands the relay to the child',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final clubIdea = StoryIdeaCatalog.next.singleWhere(
      (idea) => idea.id == 'club',
    );
    final childChoice = clubIdea.choices.first;
    final relay = await store.startFamilyRelay(
      seedId: clubIdea.id,
      seedTitle: clubIdea.title,
      childIntentZh: childChoice.intentZh,
      childMemberId: 'child',
    );
    FamilyStory? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickChallengeScreen(
            store: store,
            media: _SilentMediaService(),
            onCreated: (story) => created = story,
            initialSourceText: childChoice.draftSource,
            originStoryIdeaId: clubIdea.id,
            originStoryIdeaTitle: clubIdea.title,
            relayId: relay.id,
            relayChildIntentZh: childChoice.intentZh,
            adultMemberId: 'grandma',
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('relay-child-first-baton')),
      findsOneWidget,
    );
    expect(find.text(childChoice.intentZh), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('generate-quick-challenge-draft')),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('quick-challenge-target'));
    await tester.ensureVisible(target);
    await tester.enterText(target, 'Hôm nay con tham gia câu lạc bộ.');
    await tester.pump();
    final confirmation = find.byType(CheckboxListTile);
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pump();
    final save = find.byKey(const ValueKey('save-quick-challenge'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created?.originStoryIdeaId, 'club');
    expect(created?.originStoryIdeaTitle, '社團');
    expect(created?.familyChallenge, isNotNull);
    final storedRelay = store.relayById(relay.id);
    expect(storedRelay?.stage, FamilyRelayStage.waitingForChild);
    expect(storedRelay?.familyStoryId, created?.id);
    expect(storedRelay?.adultMemberId, 'grandma');
  });
}
