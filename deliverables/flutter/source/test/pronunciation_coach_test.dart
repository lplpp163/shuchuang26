import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/models/recording_metrics.dart';
import 'package:hometongue_tags/services/pronunciation_coach.dart';

void main() {
  const coach = LocalPracticeCoach();
  final story = FamilyStory(
    id: 'short-lesson',
    title: '短句',
    objectName: '餐桌',
    vietnamese: 'Đây là nước mắm.',
    chinese: '這是魚露。',
    promptZh: '跟著說',
    promptVi: 'Hãy nói',
    keyPhrases: const ['nước mắm'],
    practiceChunks: const ['Đây là', 'nước mắm'],
    expectedDurationSeconds: 2.2,
    draftConfidence: .9,
    humanConfirmed: true,
    createdAt: DateTime(2026, 7, 12),
  );

  test('reports steady timing without claiming phoneme correctness', () {
    final result = coach.analyze(
      story: story,
      focusText: 'Đây là',
      metrics: const RecordingMetrics(
        duration: Duration(milliseconds: 2300),
        averageDb: -25,
        peakDb: -8,
      ),
    );

    expect(result.pace, PracticePace.steady);
    expect(result.voiceLabel, contains('收音清楚'));
    expect(result.nextTip, contains('Đây là'));
    expect(result.storageSummary, isNot(contains('發音正確')));
    expect(result.storageSummary, isNot(contains('聲調正確')));
  });

  test('flags very short and quiet recordings as practice issues', () {
    final result = coach.analyze(
      story: story,
      metrics: const RecordingMetrics(
        duration: Duration(milliseconds: 650),
        averageDb: -62,
      ),
    );

    expect(result.pace, PracticePace.tooFast);
    expect(result.voiceLabel, contains('音量偏小'));
  });
}
