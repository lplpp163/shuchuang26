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
    expect(result.headline, '系統寫下的文字接近整句');
    expect(result.headline, isNot(contains('AI')));
    expect(result.headline, isNot(contains('聽懂')));
    expect(result.headline, isNot(contains('發音正確')));

    final accentless = coach.analyze(
      story: story,
      transcript: 'Day la nuoc mam',
      recognitionConfidence: 0,
    );
    expect(accentless.level, TranscriptMatchLevel.understood);
    expect(accentless.matchPercent, 100);
    expect(accentless.nextTip, contains('聲調'));
  });

  test('partial transcript points to the selected missing chunk', () {
    final result = coach.analyze(
      story: story,
      transcript: 'Đây là',
      focusText: 'nước mắm',
    );

    expect(result.level, TranscriptMatchLevel.partial);
    expect(result.headline, '系統只寫下一部分');
    expect(result.nextTip, contains('nước mắm'));
    expect(result.nextTip, contains('不代表念錯'));
  });
}
