import 'dart:math' as math;

import '../models/family_story.dart';
import '../models/recording_metrics.dart';

enum PracticePace { tooFast, steady, tooSlow, unavailable }

class PronunciationFeedback {
  const PronunciationFeedback({
    required this.pace,
    required this.paceScore,
    required this.headline,
    required this.nextTip,
    required this.focusChunk,
    required this.durationLabel,
    required this.voiceLabel,
  });

  final PracticePace pace;
  final int? paceScore;
  final String headline;
  final String nextTip;
  final String focusChunk;
  final String durationLabel;
  final String voiceLabel;

  String get storageSummary => '$headline｜$nextTip';
}

/// A transparent, offline pre-check for the competition demo.
///
/// It measures recording duration and microphone level only. It deliberately
/// does not claim to recognise phonemes, tones, words, or a family's accent.
class LocalPracticeCoach {
  const LocalPracticeCoach();

  PronunciationFeedback analyze({
    required FamilyStory story,
    required RecordingMetrics metrics,
    String? focusText,
  }) {
    final expected = story.effectiveTargetDurationMs == null
        ? math.max(1.5, _wordCount(story.vietnamese) * .55)
        : story.effectiveTargetDurationMs! / 1000;
    final actual = metrics.duration.inMilliseconds / 1000;
    final ratio = actual <= 0 ? 0.0 : actual / expected;

    final pace = actual <= 0
        ? PracticePace.unavailable
        : ratio < .55
            ? PracticePace.tooFast
            : ratio > 1.90
                ? PracticePace.tooSlow
                : PracticePace.steady;
    final score = actual <= 0
        ? null
        : (100 - ((ratio - 1).abs() * 68)).round().clamp(45, 100);
    final focus = focusText ??
        (story.practiceChunks.isNotEmpty
            ? story.practiceChunks.last
            : story.keyPhrases.isNotEmpty
                ? story.keyPhrases.first
                : story.vietnamese);

    final (headline, tip) = switch (pace) {
      PracticePace.tooFast => (
          '這次比示範短一些',
          '下一次先把「$focus」慢慢說完；長度提示不代表發音對錯。',
        ),
      PracticePace.tooSlow => (
          '這次比示範長一些',
          '先分段聽，再試著把「$focus」和前後一段自然接起來。',
        ),
      PracticePace.steady => (
          '這次長度接近示範',
          '下一次只專心練「$focus」；聲調與家庭腔調仍請家人確認。',
        ),
      PracticePace.unavailable => (
          '錄音已保存',
          '這次沒有足夠的節奏資料，可以先聽自己一次再重錄。',
        ),
    };

    return PronunciationFeedback(
      pace: pace,
      paceScore: score,
      headline: headline,
      nextTip: tip,
      focusChunk: focus,
      durationLabel:
          '${actual.toStringAsFixed(1)} 秒／示範約 ${expected.toStringAsFixed(1)} 秒',
      voiceLabel: _voiceLabel(metrics),
    );
  }

  int _wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

  String _voiceLabel(RecordingMetrics metrics) {
    final average = metrics.averageDb;
    if (!metrics.hasVolumeData || average == null) return '音量：此裝置未提供數值';
    if (average < -48) return '音量偏小：靠近麥克風一點';
    if (average > -12) return '音量偏大：離麥克風一點';
    return '音量在建議範圍';
  }
}
