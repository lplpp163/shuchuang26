import 'package:flutter/material.dart';

import '../models/family_story.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import 'scene_game_screen.dart';
import 'story_detail_screen.dart';

enum LearningFlowMode {
  fullJourney,
  pictureMatch,
  listeningOrder,
  shadowReading,
  familyChallenge,
}

/// Opens either the full child journey or one focused practice activity.
///
/// The default keeps the home-screen loop unchanged: game first, then speaking.
Future<void> openLearningFlow({
  required BuildContext context,
  required FamilyStory story,
  required AppStore store,
  required LocalMediaService media,
  LearningFlowMode mode = LearningFlowMode.fullJourney,
}) async {
  final lesson = story.lessonContent;
  if (lesson == null || mode == LearningFlowMode.shadowReading) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            StoryDetailScreen(story: story, store: store, media: media),
      ),
    );
    return;
  }

  final sceneMode = switch (mode) {
    LearningFlowMode.fullJourney => SceneGameMode.fullJourney,
    LearningFlowMode.pictureMatch => SceneGameMode.pictureMatch,
    LearningFlowMode.listeningOrder => SceneGameMode.listeningOrder,
    LearningFlowMode.familyChallenge => SceneGameMode.familyChallenge,
    LearningFlowMode.shadowReading => SceneGameMode.fullJourney,
  };

  final stars = await Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (context) => SceneGameScreen(
        story: story,
        media: media,
        lessonContent: lesson,
        mode: sceneMode,
      ),
    ),
  );
  if (stars == null || !context.mounted) return;

  if (mode != LearningFlowMode.fullJourney) return;

  await store.completeSceneGame(story.id);
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) =>
          StoryDetailScreen(story: story, store: store, media: media),
    ),
  );
}
