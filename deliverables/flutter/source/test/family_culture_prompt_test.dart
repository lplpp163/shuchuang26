import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_culture_prompt.dart';

void main() {
  test('five life scenes invite five concrete family memories', () {
    final prompts = <String>{
      for (final id in const [
        'theater-homecoming',
        'theater-morning',
        'theater-mealtime',
        'theater-garden',
        'theater-bedtime',
      ])
        familyCulturePromptForEpisode(id),
    };

    expect(prompts, hasLength(5));
    expect(prompts.every((prompt) => prompt.endsWith('？')), isTrue);
  });
}
