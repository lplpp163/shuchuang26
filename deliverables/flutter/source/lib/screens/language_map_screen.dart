import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/family_story.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import '../widgets/story_tile.dart';
import 'story_detail_screen.dart';

class LanguageMapScreen extends StatelessWidget {
  const LanguageMapScreen({
    required this.store,
    required this.media,
    super.key,
  });

  final AppStore store;
  final LocalMediaService media;

  Future<void> _openStory(BuildContext context, FamilyStory story) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            StoryDetailScreen(story: story, store: store, media: media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final repliedStoryIds =
            store.attempts.map((attempt) => attempt.storyId).toSet();
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
          children: [
            Text('我們家的故事卡', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 7),
            const Text(
              '不是考試成績，是三次選擇共同長成的一段家庭故事。',
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 20),
            _MemoryHero(
              voiceCount: store.stories.length,
              replyCount: repliedStoryIds.length,
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '打開一段回憶',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Icon(Icons.auto_awesome_rounded, color: AppColors.sun),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '可以重聽，也可以再回一句。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 13),
            if (store.stories.isEmpty)
              const _EmptyBook()
            else
              ...store.stories.map(
                (story) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StoryTile(
                    story: story,
                    attempts: store.attemptsFor(story.id),
                    onTap: () => _openStory(context, story),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              '我們家的詞語泡泡',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              '每一個詞，都連著家裡的一段故事。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            if (store.stories.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var storyIndex = 0;
                      storyIndex < store.stories.length;
                      storyIndex++)
                    for (var phraseIndex = 0;
                        phraseIndex <
                            store.stories[storyIndex].keyPhrases.length;
                        phraseIndex++)
                      _PhraseBubble(
                        phrase:
                            store.stories[storyIndex].keyPhrases[phraseIndex],
                        colorIndex: storyIndex + phraseIndex,
                      ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _MemoryHero extends StatelessWidget {
  const _MemoryHero({required this.voiceCount, required this.replyCount});

  final int voiceCount;
  final int replyCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C9BE8), Color(0xFF7656C5)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -18,
            top: -22,
            child: Icon(
              Icons.bubble_chart_rounded,
              color: Color(0x26FFFFFF),
              size: 128,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.collections_bookmark_rounded,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(height: 12),
              const Text(
                '我們的聲音正在慢慢長大',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _HeroNumber(value: voiceCount, label: '家人留下'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HeroNumber(value: replyCount, label: '我回過'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroNumber extends StatelessWidget {
  const _HeroNumber({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value 段',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _PhraseBubble extends StatelessWidget {
  const _PhraseBubble({required this.phrase, required this.colorIndex});

  final String phrase;
  final int colorIndex;

  static const _backgrounds = [
    AppColors.sunSoft,
    AppColors.skySoft,
    AppColors.coralSoft,
    AppColors.berrySoft,
    AppColors.jadeSoft,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: _backgrounds[colorIndex % _backgrounds.length],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.volume_up_rounded, size: 17),
          const SizedBox(width: 6),
          Text(phrase, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmptyBook extends StatelessWidget {
  const _EmptyBook();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          Icon(Icons.menu_book_rounded, size: 44, color: AppColors.coral),
          SizedBox(height: 8),
          Text('還沒有聲音回憶，請家人先留一句。'),
        ],
      ),
    );
  }
}
