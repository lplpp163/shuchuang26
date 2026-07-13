import '../models/task_draft.dart';

/// A transparent, deterministic MVP engine. It never calls a network service and
/// never pretends to grade pronunciation. A family member approves every draft.
class LocalTaskEngine {
  const LocalTaskEngine();

  static const Map<String, String> _familyLexicon = {
    'nước mắm': '魚露',
    'cảm ơn': '謝謝',
    'mời con ăn cơm': '請孩子吃飯',
    'ăn cơm': '吃飯',
    'bà ngoại': '外婆',
    'mẹ': '媽媽',
    'gia đình': '家人',
    'quê hương': '家鄉',
    'ngon': '好吃',
  };

  TaskDraft generate({
    required String objectName,
    required String vietnamese,
    required String chinese,
  }) {
    final normalized = vietnamese.trim().toLowerCase();
    final phrases = _familyLexicon.keys
        .where(normalized.contains)
        .toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));

    final fallback = _fallbackPhrase(vietnamese);
    final keyPhrases = phrases.isNotEmpty
        ? phrases.take(2).toList(growable: false)
        : <String>[if (fallback.isNotEmpty) fallback];

    final hasBothLanguages =
        vietnamese.trim().isNotEmpty && chinese.trim().isNotEmpty;
    final confidence = !hasBothLanguages
        ? 0.42
        : phrases.isEmpty
            ? 0.66
            : phrases.length == 1
                ? 0.84
                : 0.91;
    final focus = keyPhrases.isEmpty ? '這句家語' : keyPhrases.first;

    return TaskDraft(
      promptZh: '家人想聽你說說「$objectName」。用越南語回一句，說到「$focus」就可以。',
      promptVi:
          'Gia đình muốn nghe con nói về “$objectName”. Con trả lời một câu bằng tiếng Việt, có “$focus” là được.',
      keyPhrases: keyPhrases,
      confidence: confidence,
      explanation: phrases.isEmpty
          ? '系統還不熟這句話，請家人挑出想練的詞，再把題目改自然。'
          : '先從家人的句子挑出熟悉的詞，請家人再讀一遍並修改。',
    );
  }

  String _fallbackPhrase(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'[,.!?;:，。！？；：]'), ' ');
    final words =
        cleaned.split(RegExp(r'\s+')).where((word) => word.length > 1);
    return words.isEmpty ? '' : words.take(2).join(' ');
  }
}
