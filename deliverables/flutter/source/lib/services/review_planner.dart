import '../models/family_story.dart';
import '../models/learning_attempt.dart';

class ReviewSuggestion {
  const ReviewSuggestion({
    required this.story,
    required this.dueAt,
    required this.priority,
    required this.reason,
    required this.waitingForFamily,
  });

  final FamilyStory story;
  final DateTime dueAt;
  final int priority;
  final String reason;
  final bool waitingForFamily;
}

class CoverageSummary {
  const CoverageSummary({required this.total, required this.covered});

  final int total;
  final int covered;

  double get ratio => total == 0 ? 0 : covered / total;
}

/// Transparent spaced-review rules for the MVP. This is not an AI model.
/// Inputs and ranking reasons are deliberately inspectable and unit-testable.
class ReviewPlanner {
  const ReviewPlanner();

  List<ReviewSuggestion> plan({
    required List<FamilyStory> stories,
    required List<LearningAttempt> attempts,
    required DateTime now,
  }) {
    final suggestions = stories.map((story) {
      final history = attempts
          .where((attempt) => attempt.storyId == story.id)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (history.isEmpty) {
        return ReviewSuggestion(
          story: story,
          dueAt: now,
          priority: 100,
          reason: '這則故事還沒有練習紀錄',
          waitingForFamily: false,
        );
      }

      final latest = history.first;
      if (latest.result == ReviewResult.pending) {
        return ReviewSuggestion(
          story: story,
          dueAt: now.add(const Duration(days: 365)),
          priority: -100,
          reason: '先等家人聽完這次回答',
          waitingForFamily: true,
        );
      }
      if (latest.result == ReviewResult.almost ||
          latest.result == ReviewResult.familyVersion) {
        final reviewedAt = latest.reviewedAt ?? latest.createdAt;
        final reason = latest.result == ReviewResult.familyVersion
            ? '家人留下自己的文字提示，隔天再打開原本的家人錄音練一次'
            : '上次想再試一次，隔天再用家人的說法練一次';
        return ReviewSuggestion(
          story: story,
          dueAt: reviewedAt.add(const Duration(days: 1)),
          priority: 90,
          reason: reason,
          waitingForFamily: false,
        );
      }

      var understoodStreak = 0;
      for (final attempt in history) {
        if (attempt.result != ReviewResult.understood) break;
        understoodStreak += 1;
      }
      final cappedStreak = understoodStreak > 10 ? 10 : understoodStreak;
      final days = switch (understoodStreak) {
        <= 1 => 1,
        2 => 3,
        3 => 7,
        _ => 14,
      };
      final reviewedAt = latest.reviewedAt ?? latest.createdAt;
      return ReviewSuggestion(
        story: story,
        dueAt: reviewedAt.add(Duration(days: days)),
        priority: 60 - cappedStreak,
        reason: '已連續聽懂 $understoodStreak 次，$days 天後再複習',
        waitingForFamily: false,
      );
    }).toList();

    suggestions.sort((a, b) {
      if (a.waitingForFamily != b.waitingForFamily) {
        return a.waitingForFamily ? 1 : -1;
      }
      final dueComparison = a.dueAt.compareTo(b.dueAt);
      if (dueComparison != 0) return dueComparison;
      return b.priority.compareTo(a.priority);
    });
    return suggestions;
  }

  CoverageSummary coverage({
    required List<FamilyStory> stories,
    required List<LearningAttempt> attempts,
  }) {
    final allPhrases = <String>{};
    final coveredPhrases = <String>{};
    for (final story in stories) {
      allPhrases.addAll(story.keyPhrases);
      final understood = attempts.any(
        (attempt) =>
            attempt.storyId == story.id &&
            attempt.result == ReviewResult.understood,
      );
      if (understood) coveredPhrases.addAll(story.keyPhrases);
    }
    return CoverageSummary(
      total: allPhrases.length,
      covered: coveredPhrases.length,
    );
  }
}
