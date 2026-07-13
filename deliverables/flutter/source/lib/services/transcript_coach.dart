import '../models/family_story.dart';

enum TranscriptMatchLevel { understood, close, partial, unavailable }

class TranscriptFeedback {
  const TranscriptFeedback({
    required this.level,
    required this.matchPercent,
    required this.transcript,
    required this.headline,
    required this.nextTip,
    this.recognitionConfidence,
  });

  final TranscriptMatchLevel level;
  final int matchPercent;
  final String transcript;
  final String headline;
  final String nextTip;
  final double? recognitionConfidence;
}

/// Compares a browser/OS speech transcript with the lesson text.
///
/// This is deliberately a listening-comprehension signal, not a pronunciation
/// score. Recognition confidence must never be presented as phoneme accuracy.
class TranscriptCoach {
  const TranscriptCoach();

  TranscriptFeedback analyze({
    required FamilyStory story,
    required String transcript,
    double? recognitionConfidence,
    String? focusText,
  }) {
    final target = _normalize(story.targetText);
    final heard = _normalize(transcript);
    if (heard.isEmpty) {
      return TranscriptFeedback(
        level: TranscriptMatchLevel.unavailable,
        matchPercent: 0,
        transcript: transcript.trim(),
        headline: '這次還沒有辨識到文字',
        nextTip: '靠近麥克風，聽完提示音後再說一次短句。',
        recognitionConfidence: recognitionConfidence,
      );
    }

    final longest = target.length > heard.length ? target.length : heard.length;
    final distance = _levenshtein(target, heard);
    final percent = longest == 0
        ? 0
        : ((1 - distance / longest) * 100).round().clamp(0, 100);
    final level = percent >= 90
        ? TranscriptMatchLevel.understood
        : percent >= 68
            ? TranscriptMatchLevel.close
            : TranscriptMatchLevel.partial;

    final selected = focusText?.trim();
    final selectedWasHeard = selected != null &&
        selected.isNotEmpty &&
        heard.contains(_normalize(selected));
    final missing = story.effectivePracticeChunks.cast<String?>().firstWhere(
          (chunk) => chunk != null && !heard.contains(_normalize(chunk)),
          orElse: () => null,
        );
    final practiceTarget = selectedWasHeard ? missing : selected ?? missing;

    final (headline, tip) = switch (level) {
      TranscriptMatchLevel.understood => (
          '系統聽寫到完整短句',
          '很接近目標；下一次保留同樣節奏，再請家人確認家庭腔調。',
        ),
      TranscriptMatchLevel.close => (
          '系統聽寫到大部分內容',
          practiceTarget == null
              ? '再聽一次示範，把兩段連得更自然。'
              : '下一次先單獨練「$practiceTarget」，再回到整句。',
        ),
      TranscriptMatchLevel.partial => (
          '系統只聽寫到一部分',
          practiceTarget == null
              ? '放慢一點，每一小段之間停半拍再試一次。'
              : '先點播放聽「$practiceTarget」，跟一次後再測整句。',
        ),
      TranscriptMatchLevel.unavailable => throw StateError('handled above'),
    };

    return TranscriptFeedback(
      level: level,
      matchPercent: percent,
      transcript: transcript.trim(),
      headline: headline,
      nextTip: tip,
      recognitionConfidence: recognitionConfidence,
    );
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  int _levenshtein(String source, String target) {
    if (source.isEmpty) return target.length;
    if (target.isEmpty) return source.length;
    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex++) {
      final current = <int>[sourceIndex + 1];
      for (var targetIndex = 0; targetIndex < target.length; targetIndex++) {
        final substitution = previous[targetIndex] +
            (source.codeUnitAt(sourceIndex) == target.codeUnitAt(targetIndex)
                ? 0
                : 1);
        final insertion = current[targetIndex] + 1;
        final deletion = previous[targetIndex + 1] + 1;
        current.add(
          substitution < insertion
              ? (substitution < deletion ? substitution : deletion)
              : (insertion < deletion ? insertion : deletion),
        );
      }
      previous = current;
    }
    return previous.last;
  }
}
