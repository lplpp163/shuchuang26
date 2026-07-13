import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/family_story.dart';
import '../models/learning_attempt.dart';

class StoryTile extends StatelessWidget {
  const StoryTile({
    required this.story,
    required this.onTap,
    this.attempts = const [],
    super.key,
  });

  final FamilyStory story;
  final List<LearningAttempt> attempts;
  final VoidCallback onTap;

  Widget _photo(FamilyStory story) {
    final asset = story.illustrationAsset;
    if (asset != null) return Image.asset(asset, fit: BoxFit.cover);
    final path = story.photoPath;
    if (path == null) return const _PhotoFallback();
    if (kIsWeb) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _PhotoFallback(),
      );
    }
    return File(path).existsSync()
        ? Image.file(File(path), fit: BoxFit.cover)
        : const _PhotoFallback();
  }

  ({String label, Color background, Color foreground}) get _status {
    if (attempts.any((attempt) => attempt.result == ReviewResult.pending)) {
      return (
        label: '等家人打開',
        background: AppColors.sunSoft,
        foreground: const Color(0xFF805D00),
      );
    }
    if (attempts.any((attempt) => attempt.result == ReviewResult.understood)) {
      return (
        label: '家人聽懂了',
        background: AppColors.jadeSoft,
        foreground: AppColors.jade,
      );
    }
    if (attempts.isNotEmpty) {
      return (
        label: '我回過這句',
        background: AppColors.skySoft,
        foreground: const Color(0xFF276AAB),
      );
    }
    return (
      label: story.isSample ? '有聲操作示範' : '打開來聽',
      background: AppColors.berrySoft,
      foreground: AppColors.berry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: _photo(story),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${story.languageName} · ${story.chinese}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: status.background,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          color: status.foreground,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.berrySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.berry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.sunSoft, AppColors.coralSoft],
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.ramen_dining_rounded,
        color: AppColors.coral,
        size: 38,
      ),
    );
  }
}
