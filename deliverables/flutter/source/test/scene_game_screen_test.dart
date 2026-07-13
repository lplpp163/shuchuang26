import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/lesson_content.dart';
import 'package:hometongue_tags/screens/scene_game_screen.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:hometongue_tags/services/local_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentMediaService extends LocalMediaService {
  final List<String> playedPaths = [];

  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    playedPaths.add(path);
  }

  @override
  Future<void> stopPlayback() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('child completes four stages without losing stars on mistakes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final story = store.storyById('family-greeting')!;
    var completedStars = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SceneGameScreen(
          story: story,
          media: _SilentMediaService(),
          lessonContent: story.lessonContent!,
          onCompleted: (stars) => completedStars = stars,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0/4'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('鬧鐘'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('鬧鐘'));
    await tester.pump();
    expect(find.text('0/4'), findsOneWidget);
    expect(find.textContaining('看看右邊正在拉開窗簾的家人'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('外婆'));
    await tester.pump();
    expect(find.text('1/4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-0')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('點一下聽'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('外婆'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('next-1')));
    await tester.pumpAndSettle();

    for (final token in ['Cháu', 'chào', 'bà', 'ạ']) {
      await tester.tap(find.text(token));
      await tester.pump();
    }
    expect(find.text('3/4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(story.vietnamese));
    await tester.pump();
    expect(find.text('4/4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-3')));
    await tester.pumpAndSettle();

    expect(find.text('不等家人，星星現在就拿到；接著跟著說一句。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finish-scene-game')));
    await tester.pump();
    expect(completedStars, 4);
  });

  testWidgets('family-selected table object changes the child mission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final original = store.storyById('nuoc-mam')!;
    final story = original.copyWith(
      objectName: '白飯',
      familyChallenge: const FamilyChallenge(
        promptZh: '找到白飯',
        correctChoiceZh: '白飯',
        distractorsZh: ['魚露', '筷子'],
        successMessageZh: '找到了',
        cultureNoteZh: '問問家人怎麼煮飯。',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SceneGameScreen(
          story: story,
          media: _SilentMediaService(),
          lessonContent: story.lessonContent!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('找到白飯'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('白飯'));
    await tester.pump();
    expect(find.textContaining('找到了'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
  });

  testWidgets('focused practice modes open genuinely different activities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    final story = store.storyById('family-greeting')!;

    Future<void> show(SceneGameMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SceneGameScreen(
            key: ValueKey(mode),
            story: story,
            media: _SilentMediaService(),
            lessonContent: story.lessonContent!,
            mode: mode,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(SceneGameMode.pictureMatch);
    expect(find.text('在場景裡找線索'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    expect(find.text('先看懂，再用耳朵找'), findsNothing);

    await show(SceneGameMode.listeningOrder);
    expect(find.text('先看懂，再用耳朵找'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('在場景裡找線索'), findsNothing);

    await show(SceneGameMode.familyChallenge);
    expect(find.text('幫角色回答'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    expect(find.text('排好句子'), findsNothing);
  });

  testWidgets('the listening ear plays the complete sentence in every lesson',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();

    for (final story in store.stories.where((story) => story.isSample)) {
      final lesson = story.lessonContent;
      expect(lesson, isNotNull, reason: story.id);
      final media = _SilentMediaService();
      await tester.pumpWidget(
        MaterialApp(
          home: SceneGameScreen(
            key: ValueKey('listen-${story.id}'),
            story: story,
            media: media,
            lessonContent: lesson!,
            mode: SceneGameMode.listeningOrder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('點一下聽'));
      await tester.pumpAndSettle();

      expect(media.playedPaths, [story.audioPath], reason: story.id);
      expect(
        lesson.segments
            .map((segment) => segment.audio?.path)
            .where((path) => path != story.audioPath),
        isNot(contains(media.playedPaths.single)),
        reason: '${story.id} must not substitute a word or phrase clip',
      );
    }
  });
}
