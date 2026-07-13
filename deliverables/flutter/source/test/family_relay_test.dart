import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_relay.dart';

void main() {
  final requestedAt = DateTime.utc(2026, 7, 14, 8);
  final adultCompletedAt = DateTime.utc(2026, 7, 14, 8, 5);
  final childCompletedAt = DateTime.utc(2026, 7, 14, 8, 10);

  FamilyRelay waitingForAdult() => FamilyRelay(
        id: 'relay-club-1',
        seedId: 'club',
        seedTitle: '社團',
        childIntentZh: '我今天第一次參加社團。',
        childMemberId: 'child',
        requestedAt: requestedAt,
      );

  test('family relay only moves child to adult to child', () {
    final initial = waitingForAdult();

    expect(initial.stage, FamilyRelayStage.waitingForAdult);
    expect(
      () => initial.completeChildTurn(
        attemptId: 'attempt-too-soon',
        at: childCompletedAt,
      ),
      throwsStateError,
    );

    final adultTurn = initial.completeAdultTurn(
      memberId: 'grandma',
      storyId: 'story-club-1',
      at: adultCompletedAt,
    );
    expect(adultTurn.stage, FamilyRelayStage.waitingForChild);
    expect(adultTurn.adultMemberId, 'grandma');
    expect(adultTurn.familyStoryId, 'story-club-1');
    expect(
      () => adultTurn.completeAdultTurn(
        memberId: 'grandma',
        storyId: 'story-club-1',
        at: adultCompletedAt,
      ),
      throwsStateError,
    );

    final completed = adultTurn.completeChildTurn(
      attemptId: 'attempt-club-1',
      at: childCompletedAt,
    );
    expect(completed.stage, FamilyRelayStage.completed);
    expect(completed.childAttemptId, 'attempt-club-1');
    expect(
      () => completed.completeChildTurn(
        attemptId: 'attempt-club-2',
        at: childCompletedAt,
      ),
      throwsStateError,
    );
  });

  test('family relay JSON round-trip preserves a complete handoff', () {
    final completed = waitingForAdult()
        .completeAdultTurn(
          memberId: 'grandma',
          storyId: 'story-club-1',
          at: adultCompletedAt,
        )
        .completeChildTurn(
          attemptId: 'attempt-club-1',
          at: childCompletedAt,
        );

    final restored = FamilyRelay.fromJson(completed.toJson());

    expect(restored.stage, FamilyRelayStage.completed);
    expect(restored.id, completed.id);
    expect(restored.seedId, 'club');
    expect(restored.seedTitle, '社團');
    expect(restored.childIntentZh, '我今天第一次參加社團。');
    expect(restored.requestedAt, requestedAt);
    expect(restored.adultCompletedAt, adultCompletedAt);
    expect(restored.completedAt, childCompletedAt);
  });

  test('family relay JSON rejects partial or contradictory stages', () {
    expect(
      () => FamilyRelay.fromJson({
        ...waitingForAdult().toJson(),
        'adultMemberId': 'grandma',
      }),
      throwsFormatException,
    );

    final waitingForChild = waitingForAdult().completeAdultTurn(
      memberId: 'grandma',
      storyId: 'story-club-1',
      at: adultCompletedAt,
    );
    expect(
      () => FamilyRelay.fromJson({
        ...waitingForChild.toJson(),
        'childAttemptId': 'attempt-without-completion-time',
      }),
      throwsFormatException,
    );
    expect(
      () => FamilyRelay.fromJson({
        ...waitingForAdult().toJson(),
        'requestedAt': 'not-a-date',
      }),
      throwsFormatException,
    );
  });
}
