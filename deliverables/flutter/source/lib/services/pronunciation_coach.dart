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
        : ratio < .68
            ? PracticePace.tooFast
            : ratio > 1.65
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
          '有錄到完整一句，再放鬆一點',
          '下一次在「$focus」前停半拍，讓每一段更容易聽清楚。',
        ),
      PracticePace.tooSlow => (
          '每個字都有說到，很不錯',
          '試著把前後兩段接起來，像家人說話時一樣自然。',
        ),
      PracticePace.steady => (
          '節奏很接近示範音',
          '下一次只專心練「$focus」，再把整句連起來。',
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
    return '收音清楚：音量在舒適範圍';
  }
}
