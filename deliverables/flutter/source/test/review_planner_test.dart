import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/models/learning_attempt.dart';
import 'package:hometongue_tags/services/review_planner.dart';

void main() {
  const planner = ReviewPlanner();
  final now = DateTime(2026, 7, 12, 12);

  FamilyStory story(String id, List<String> phrases) => FamilyStory(
        id: id,
        title: '故事 $id',
        objectName: '物件',
        vietnamese: 'nước mắm',
        chinese: '魚露',
        promptZh: '請回答',
        promptVi: 'Hãy trả lời',
        keyPhrases: phrases,
        draftConfidence: .9,
        humanConfirmed: true,
        createdAt: now,
      );

  LearningAttempt attempt({
    required String id,
    required String storyId,
    required ReviewResult result,
    required DateTime at,
    DateTime? reviewedAt,
  }) =>
      LearningAttempt(
        id: id,
        storyId: storyId,
        createdAt: at,
        result: result,
        reviewedAt: reviewedAt,
      );

  test('puts an unpractised story ahead of one waiting for family', () {
    final stories = [
      story('new', const ['mẹ']),
      story('waiting', const ['bà ngoại']),
    ];
    final attempts = [
      attempt(
        id: 'a1',
        storyId: 'waiting',
        result: ReviewResult.pending,
        at: now,
      ),
    ];

    final plan = planner.plan(stories: stories, attempts: attempts, now: now);

    expect(plan.first.story.id, 'new');
    expect(plan.last.waitingForFamily, isTrue);
  });

  test('schedules almost for the next day', () {
    final item = story('almost', const ['nước mắm']);
    final plan = planner.plan(
      stories: [item],
      attempts: [
        attempt(
          id: 'a1',
          storyId: item.id,
          result: ReviewResult.almost,
          at: now,
        ),
      ],
      now: now,
    );

    expect(plan.single.dueAt, now.add(const Duration(days: 1)));
    expect(plan.single.reason, contains('隔天'));
  });

  test('schedules a family-provided version for the next day', () {
    final item = story('family-version', const ['quê hương']);
    final plan = planner.plan(
      stories: [item],
      attempts: [
        attempt(
          id: 'a1',
          storyId: item.id,
          result: ReviewResult.familyVersion,
          at: now,
        ),
      ],
      now: now,
    );

    expect(plan.single.dueAt, now.add(const Duration(days: 1)));
    expect(plan.single.reason, contains('家人留下自己的文字提示'));
  });

  test('starts the interval when family reviews a delayed reply', () {
    final item = story('delayed-review', const ['mẹ']);
    final reviewedAt = now;
    final plan = planner.plan(
      stories: [item],
      attempts: [
        attempt(
          id: 'a1',
          storyId: item.id,
          result: ReviewResult.understood,
          at: now.subtract(const Duration(days: 5)),
          reviewedAt: reviewedAt,
        ),
      ],
      now: now,
    );

    expect(plan.single.dueAt, reviewedAt.add(const Duration(days: 1)));
  });

  test('uses 1, 3, 7 and 14 day intervals after understood streaks', () {
    final item = story('spaced', const ['gia đình']);

    int intervalFor(int streak) {
      final attempts = List.generate(
        streak,
        (index) => attempt(
          id: 'a$index',
          storyId: item.id,
          result: ReviewResult.understood,
          at: now.subtract(Duration(hours: index)),
        ),
      );
      final suggestion =
          planner.plan(stories: [item], attempts: attempts, now: now).single;
      return suggestion.dueAt.difference(now).inDays;
    }

    expect(intervalFor(1), 1);
    expect(intervalFor(2), 3);
    expect(intervalFor(3), 7);
    expect(intervalFor(4), 14);
  });

  test('coverage only counts phrases from human-understood attempts', () {
    final first = story('one', const ['nước mắm', 'bà ngoại']);
    final second = story('two', const ['bà ngoại', 'mẹ']);
    final summary = planner.coverage(
      stories: [first, second],
      attempts: [
        attempt(
          id: 'a1',
          storyId: first.id,
          result: ReviewResult.understood,
          at: now,
        ),
        attempt(
          id: 'a2',
          storyId: second.id,
          result: ReviewResult.pending,
          at: now,
        ),
      ],
    );

    expect(summary.total, 3);
    expect(summary.covered, 2);
    expect(summary.ratio, closeTo(2 / 3, .0001));
  });
}
