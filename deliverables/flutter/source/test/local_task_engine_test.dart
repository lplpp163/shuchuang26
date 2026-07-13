import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/services/local_task_engine.dart';

void main() {
  group('LocalTaskEngine', () {
    const engine = LocalTaskEngine();

    test(
      'extracts transparent family phrases from a known Vietnamese example',
      () {
        final draft = engine.generate(
          objectName: '廚房的魚露',
          vietnamese: 'Đây là nước mắm bà ngoại thường dùng để nấu ăn.',
          chinese: '這是外婆常用來煮飯的魚露。',
        );

        expect(draft.keyPhrases, containsAll(<String>['nước mắm', 'bà ngoại']));
        expect(draft.confidence, 0.91);
        expect(draft.requiresHumanReview, isFalse);
        expect(draft.explanation, contains('請家人再讀一遍'));
        expect(draft.promptZh, contains('家人想聽你說說'));
      },
    );

    test('abstains with low confidence when no lexicon phrase is known', () {
      final draft = engine.generate(
        objectName: '家庭照片',
        vietnamese: 'Một câu địa phương chưa có trong từ điển.',
        chinese: '一個尚未收錄的地方說法。',
      );

      expect(draft.confidence, 0.66);
      expect(draft.requiresHumanReview, isTrue);
      expect(draft.explanation, contains('請家人挑出想練的詞'));
      expect(draft.keyPhrases, isNotEmpty);
    });

    test('does not give false confidence when one language is missing', () {
      final draft = engine.generate(
        objectName: '餐桌',
        vietnamese: 'Mời con ăn cơm',
        chinese: '',
      );

      expect(draft.confidence, 0.42);
      expect(draft.requiresHumanReview, isTrue);
    });
  });
}
