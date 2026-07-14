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
        headline: '系統這次沒有寫出文字',
        nextTip: '可能是瀏覽器、環境音或腔調差異，不代表你念錯。先聽一小段，再決定要不要重試。',
        recognitionConfidence: recognitionConfidence,
      );
    }

    final longest = target.length > heard.length ? target.length : heard.length;
    final distance = _levenshtein(target, heard);
    final percent = longest == 0
        ? 0
        : ((1 - distance / longest) * 100).round().clamp(0, 100);
    final level = percent >= 80
        ? TranscriptMatchLevel.understood
        : percent >= 50
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
          '系統寫下的文字接近整句',
          '這只表示聽寫有找到文字；聲調與家庭腔調仍請家人親耳確認。',
        ),
      TranscriptMatchLevel.close => (
          '系統寫下的文字大致相近',
          practiceTarget == null
              ? '再聽一次示範，把兩段分開跟讀後再連起來。'
              : '先聽「$practiceTarget」一次、跟著說一次，再回到整句。',
        ),
      TranscriptMatchLevel.partial => (
          '系統只寫下一部分',
          practiceTarget == null
              ? '聽寫不完整不代表念錯；放慢一點，每一小段之間停半拍。'
              : '聽寫不完整不代表念錯；先點播放聽「$practiceTarget」，跟一次後再試。',
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

  String _normalize(String value) {
    var normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const vietnameseFoldGroups = <String, String>{
      'a': 'àáảãạăằắẳẵặâầấẩẫậ',
      'e': 'èéẻẽẹêềếểễệ',
      'i': 'ìíỉĩị',
      'o': 'òóỏõọôồốổỗộơờớởỡợ',
      'u': 'ùúủũụưừứửữự',
      'y': 'ỳýỷỹỵ',
      'd': 'đ',
    };
    for (final entry in vietnameseFoldGroups.entries) {
      normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return normalized;
  }

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
