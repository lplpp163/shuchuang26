import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/services/transcript_coach.dart';

void main() {
  const coach = TranscriptCoach();
  final story = FamilyStory(
    id: 'speech-check',
    title: '魚露',
    objectName: '餐桌',
    vietnamese: 'Đây là nước mắm.',
    chinese: '這是魚露。',
    promptZh: '跟著說',
    promptVi: 'Hãy nói',
    keyPhrases: const ['nước mắm'],
    practiceChunks: const ['Đây là', 'nước mắm'],
    draftConfidence: .9,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 12),
  );

  test('exact transcript is reported as system dictation, not AI judgment', () {
    final result = coach.analyze(
      story: story,
      transcript: 'Đây là nước mắm',
      recognitionConfidence: .93,
    );

    expect(result.level, TranscriptMatchLevel.understood);
    expect(result.matchPercent, 100);
    expect(result.headline, '系統聽寫到完整短句');
    expect(result.headline, isNot(contains('AI')));
    expect(result.headline, isNot(contains('聽懂')));
    expect(result.headline, isNot(contains('發音正確')));
  });

  test('partial transcript points to the selected missing chunk', () {
    final result = coach.analyze(
      story: story,
      transcript: 'Đây là',
      focusText: 'nước mắm',
    );

    expect(result.level, TranscriptMatchLevel.partial);
    expect(result.headline, '系統只聽寫到一部分');
    expect(result.nextTip, contains('nước mắm'));
  });
}
