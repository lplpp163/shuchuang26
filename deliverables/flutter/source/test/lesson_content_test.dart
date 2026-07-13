import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_story.dart';
import 'package:hometongue_tags/models/lesson_content.dart';

void main() {
  FamilyStory storyWith(LessonContent? content) => FamilyStory(
        id: 'lesson-json',
        title: '短句',
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
        lessonContent: content,
      );

  test('structured lesson survives JSON round trip', () {
    const content = LessonContent(
      schemaVersion: 2,
      languageTag: 'vi-VN',
      romanizationSystem: 'quốc-ngữ',
      sentenceRomanization: 'Đây · là · nước · mắm',
      targetDurationMs: 1000,
      segments: [
        LessonSegment(
          id: 'fish-sauce',
          text: 'nước mắm',
          tokens: ['nước', 'mắm'],
          translationZh: '魚露',
          romanization: 'nước · mắm',
          pronunciationTipsZh: ['句尾收住'],
          audio: LessonAudio(path: 'asset://chunk.mp3'),
        ),
      ],
      patterns: [
        SentencePattern(
          id: 'pattern',
          template: 'Đây là + N.',
          meaningZh: '這是＋名詞。',
          examples: [
            LessonExample(
              targetText: 'Đây là cơm.',
              translationZh: '這是飯。',
            ),
          ],
        ),
      ],
    );
    final original = storyWith(content);

    final decoded = FamilyStory.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(original.toJson())) as Map,
      ),
    );

    expect(decoded.lessonContent?.languageTag, 'vi-VN');
    expect(decoded.lessonContent?.segments.single.translationZh, '魚露');
    expect(decoded.lessonContent?.patterns.single.examples.single.targetText,
        'Đây là cơm.');
    expect(decoded.effectiveTargetDurationMs, 1000);
  });

  test('damaged optional lesson falls back without losing the story', () {
    final json = storyWith(null).toJson();
    json['lessonContent'] = {'segments': 'broken'};

    final decoded = FamilyStory.fromJson(json);

    expect(decoded.id, 'lesson-json');
    expect(decoded.lessonContent, isNull);
    expect(decoded.effectivePracticeChunks, ['Đây là', 'nước mắm']);
  });

  test(
      'story language is explicit and an unknown family language stays unknown',
      () {
    final vietnamese = storyWith(null);
    final explicit = vietnamese.copyWith(languageTag: 'hak-TW');
    final unknown = FamilyStory.fromJson({
      ...vietnamese.toJson(),
      'languageName': '其他家語',
      'languageTag': null,
    });

    expect(vietnamese.effectiveLanguageTag, 'vi-VN');
    expect(explicit.effectiveLanguageTag, 'hak-TW');
    expect(explicit.toJson()['languageTag'], 'hak-TW');
    expect(unknown.effectiveLanguageTag, 'und');
  });

  test('family challenge survives JSON round trip', () {
    const original = FamilyChallenge(
      sceneTitleZh: '文化加分：魚露',
      promptZh: '外婆做菜時，要找哪一樣？',
      listeningPromptZh: '聽到句子後，找出魚露。',
      dialoguePromptZh: '找到後，跟著外婆說一次。',
      correctChoiceZh: '魚露',
      distractorsZh: ['白飯', '筷子'],
      correctEmoji: '🫙',
      distractorEmojis: ['🍚', '🥢'],
      successMessageZh: '找到我們家的味道了！',
      cultureNoteZh: '每個家庭調魚露的方法都不一樣。',
      hotspots: [
        ChallengeHotspot(
          labelZh: '魚露',
          left: .79,
          top: .51,
          width: .14,
          height: .42,
          hintZh: '找裝著琥珀色液體的瓶子。',
        ),
      ],
    );

    final decoded = FamilyChallenge.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(original.toJson())) as Map,
      ),
    );

    expect(decoded.promptZh, original.promptZh);
    expect(decoded.correctChoiceZh, original.correctChoiceZh);
    expect(decoded.distractorsZh, original.distractorsZh);
    expect(decoded.successMessageZh, original.successMessageZh);
    expect(decoded.cultureNoteZh, original.cultureNoteZh);
    expect(decoded.sceneTitleZh, original.sceneTitleZh);
    expect(decoded.listeningPromptZh, original.listeningPromptZh);
    expect(decoded.dialoguePromptZh, original.dialoguePromptZh);
    expect(decoded.correctEmoji, original.correctEmoji);
    expect(decoded.distractorEmojis, original.distractorEmojis);
    expect(decoded.hotspots, hasLength(1));
    expect(decoded.hotspots.single.labelZh, '魚露');
    expect(decoded.hotspots.single.left, .79);
    expect(decoded.hotspots.single.top, .51);
    expect(decoded.hotspots.single.width, .14);
    expect(decoded.hotspots.single.height, .42);
    expect(decoded.hotspots.single.hintZh, '找裝著琥珀色液體的瓶子。');
    expect(decoded.choices, ['魚露', '白飯', '筷子']);
    expect(decoded.emojiForChoice('魚露'), '🫙');
    expect(decoded.emojiForChoice('筷子'), '🥢');
  });
}
