import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/screens/story_detail_screen.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:hometongue_tags/services/local_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMediaService extends LocalMediaService {
  int playCount = 0;
  final List<String> playedPaths = [];

  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    playCount += 1;
    playedPaths.add(path);
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'beginner aids appear before listening and recording follows audio', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final media = _FakeMediaService();
    final story = FamilyStory(
      id: 'hidden-source-test',
      title: '媽媽的家鄉話',
      objectName: '家庭照片',
      vietnamese: 'Đây là quê hương của mẹ.',
      chinese: '這是媽媽的家鄉。',
      promptZh: '請用越南語說一句話。',
      promptVi: 'Hãy nói một câu bằng tiếng Việt.',
      keyPhrases: const ['quê hương', 'mẹ'],
      draftConfidence: .9,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 12),
      audioPath: 'asset://assets/audio/test.mp3',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StoryDetailScreen(story: story, store: store, media: media),
      ),
    );

    expect(find.text(story.vietnamese), findsOneWidget);
    expect(find.text(story.chinese), findsOneWidget);
    expect(find.text(story.promptZh), findsNothing);
    expect(find.byKey(const ValueKey('pronunciation-guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-toggle')), findsNothing);

    expect(find.text('家人原音'), findsOneWidget);
    expect(find.textContaining('家庭版本未錄'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '聽家人原音'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '聽家人原音'));
    await tester.pumpAndSettle();

    expect(media.playCount, 1);
    expect(media.playedPaths, [story.audioPath]);
    expect(find.text(story.vietnamese), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('record-toggle')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-toggle')), findsOneWidget);
  });

  testWidgets(
      'sample lessons label synthetic audio without inventing a family speaker',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final media = _FakeMediaService();
    final cases = <String, List<String>>{
      'family-greeting': ['Con chào mẹ ạ.', 'Em chào chị ạ.'],
      'family-homecoming': ['Mẹ về rồi.', 'Bố về rồi.'],
    };

    for (final entry in cases.entries) {
      final story = store.storyById(entry.key)!;
      await tester.pumpWidget(
        MaterialApp(
          home: StoryDetailScreen(
            key: ValueKey(story.id),
            story: story,
            store: store,
            media: media,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('合成示範音｜家庭版本未錄'), findsOneWidget);
      expect(find.text('聽合成示範音'), findsOneWidget);
      expect(find.text('聽外婆說'), findsNothing);

      final listen = find.byKey(const ValueKey('play-family-voice'));
      await tester.ensureVisible(listen);
      await tester.pumpAndSettle();
      await tester.tap(listen);
      await tester.pumpAndSettle();
      expect(media.playedPaths.last, story.audioPath);

      final pattern = find.byKey(const ValueKey('sentence-pattern'));
      await tester.scrollUntilVisible(
        pattern,
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      for (final example in entry.value) {
        expect(find.text(example), findsOneWidget);
      }
      expect(find.text('再聽外婆說'), findsNothing);
    }
  });

  testWidgets('an unrecorded family card labels device narration honestly',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final media = _FakeMediaService();
    final story = FamilyStory(
      id: 'unrecorded-family-version',
      title: '家裡的一句話',
      objectName: '家庭照片',
      vietnamese: 'Con về rồi.',
      chinese: '我回來了。',
      promptZh: '請說一句話。',
      promptVi: 'Hãy nói một câu.',
      keyPhrases: const ['Con về rồi'],
      draftConfidence: .9,
      humanConfirmed: true,
      createdAt: DateTime(2026, 7, 13),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StoryDetailScreen(story: story, store: store, media: media),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭版本未錄｜裝置示範音'), findsOneWidget);
    expect(find.text('聽裝置示範音'), findsOneWidget);
    expect(find.text('聽家人原音'), findsNothing);
    expect(find.text('聽家人說'), findsNothing);
  });

  testWidgets(
      'structured chunks play separately and explain a reusable pattern', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final media = _FakeMediaService();
    final story = store.storyById('nuoc-mam')!;

    await tester.pumpWidget(
      MaterialApp(
        home: StoryDetailScreen(story: story, store: store, media: media),
      ),
    );
    await tester.pumpAndSettle();

    final firstChunk = find.byKey(const ValueKey('play-segment-day-la'));
    await tester.scrollUntilVisible(
      firstChunk,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('分詞解釋'), findsOneWidget);
    expect(find.textContaining('Đây＝這'), findsOneWidget);
    await tester.tap(firstChunk);
    await tester.pumpAndSettle();

    expect(media.playedPaths.last, contains('vietnamese_chunk_day_la.mp3'));
    expect(find.byKey(const ValueKey('record-toggle')), findsNothing);

    final secondChunk = find.widgetWithText(ChoiceChip, 'nước mắm');
    await tester.ensureVisible(secondChunk);
    await tester.pumpAndSettle();
    await tester.tap(secondChunk);
    await tester.pumpAndSettle();
    expect(find.textContaining('nước＝水'), findsOneWidget);
    expect(find.textContaining('尾端再多加一個母音'), findsOneWidget);

    final fullSentence = find.byKey(const ValueKey('play-family-voice'));
    await tester.ensureVisible(fullSentence);
    await tester.pumpAndSettle();
    await tester.tap(fullSentence);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sentence-pattern')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Đây là +［人或東西］.'), findsOneWidget);
    expect(find.text('Đây là mẹ.'), findsOneWidget);
    expect(find.text('這是飯。'), findsOneWidget);
  });

  testWidgets('text fallback is never presented as a recording or inbox send',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final media = _FakeMediaService();
    final story = store.storyById('nuoc-mam')!;

    await tester.pumpWidget(
      MaterialApp(
        home: StoryDetailScreen(story: story, store: store, media: media),
      ),
    );
    await tester.pumpAndSettle();

    final listen = find.byKey(const ValueKey('play-family-voice'));
    await tester.scrollUntilVisible(
      listen,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(listen);
    await tester.pumpAndSettle();

    final fallback = find.text('麥克風不能用？');
    await tester.scrollUntilVisible(
      fallback,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '寫下自己想說的話'),
      '我先寫下來',
    );
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('send-to-family'));
    await tester.scrollUntilVisible(
      save,
      340,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('短句挑戰完成！'), findsOneWidget);
    expect(find.textContaining('這次沒有錄音'), findsOneWidget);
    expect(find.text('文字紀錄 +1'), findsOneWidget);
    expect(find.textContaining('聲音已放進'), findsNothing);
    expect(find.textContaining('聲音卡'), findsNothing);
    expect(find.textContaining('家人晚點'), findsNothing);
  });
}
