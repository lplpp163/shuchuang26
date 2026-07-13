import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A short, branching family conversation that can be played without a
/// generative-AI service.
class ConversationEpisode {
  const ConversationEpisode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.elderName,
    required this.elderAvatarEmoji,
    required this.languageName,
    required this.languageTag,
    required this.estimatedDurationSeconds,
    required this.openingPromptId,
    required this.openingScene,
    required this.prompts,
    this.illustrationAsset,
  })  : assert(estimatedDurationSeconds >= 60),
        assert(estimatedDurationSeconds <= 90);

  final String id;
  final String title;
  final String subtitle;
  final String elderName;
  final String elderAvatarEmoji;
  final String languageName;
  final String languageTag;
  final int estimatedDurationSeconds;
  final String openingPromptId;
  final ConversationSceneSnapshot openingScene;
  final List<ConversationPrompt> prompts;
  final String? illustrationAsset;

  ConversationPrompt promptById(String id) => prompts.firstWhere(
        (prompt) => prompt.id == id,
        orElse: () => throw StateError('找不到對話節點：$id'),
      );

  int get totalTurns => prompts.map((prompt) => prompt.step).reduce(
        (largest, step) => step > largest ? step : largest,
      );

  bool get isPlayable =>
      prompts.length >= 3 &&
      prompts.every((prompt) => prompt.choices.length >= 2);

  ConversationEpisode withElderDisplayName(String name) {
    final displayName = name.trim();
    if (displayName.isEmpty || displayName == elderName) return this;

    String personalize(String value) => value.replaceAll('外婆', displayName);
    ConversationLine line(ConversationLine source) => ConversationLine(
          targetText: source.targetText,
          translationZh: personalize(source.translationZh),
          romanization: source.romanization,
          audioPath: source.audioPath,
        );
    ConversationSceneSnapshot scene(ConversationSceneSnapshot source) =>
        ConversationSceneSnapshot(
          id: source.id,
          headlineZh: personalize(source.headlineZh),
          descriptionZh: personalize(source.descriptionZh),
          focusEmoji: source.focusEmoji,
          environmentEmojis: source.environmentEmojis,
        );

    return ConversationEpisode(
      id: id,
      title: personalize(title),
      subtitle: personalize(subtitle),
      elderName: displayName,
      elderAvatarEmoji: elderAvatarEmoji,
      languageName: languageName,
      languageTag: languageTag,
      estimatedDurationSeconds: estimatedDurationSeconds,
      openingPromptId: openingPromptId,
      openingScene: scene(openingScene),
      illustrationAsset: illustrationAsset,
      prompts: [
        for (final prompt in prompts)
          ConversationPrompt(
            id: prompt.id,
            step: prompt.step,
            elderLine: line(prompt.elderLine),
            stageDirectionZh: personalize(prompt.stageDirectionZh),
            choices: [
              for (final choice in prompt.choices)
                ConversationChoice(
                  id: choice.id,
                  emoji: choice.emoji,
                  line: line(choice.line),
                  matchKeywords: choice.matchKeywords.map(personalize).toList(),
                  elderReply: line(choice.elderReply),
                  sceneAfter: scene(choice.sceneAfter),
                  storyBeatZh: personalize(choice.storyBeatZh),
                  nextPromptId: choice.nextPromptId,
                ),
            ],
          ),
      ],
    );
  }
}

class ConversationPrompt {
  const ConversationPrompt({
    required this.id,
    required this.step,
    required this.elderLine,
    required this.stageDirectionZh,
    required this.choices,
  });

  final String id;
  final int step;
  final ConversationLine elderLine;
  final String stageDirectionZh;
  final List<ConversationChoice> choices;

  /// Finds choices whose reviewed keywords occur in the speech transcript.
  ///
  /// More than one match is deliberately treated as ambiguous. A transcript is
  /// never enough evidence for a pronunciation score, or for guessing between
  /// two choices that share a common word.
  List<ConversationChoice> matchingChoicesForTranscript(String transcript) {
    final heard = _normalizeSpeech(transcript);
    if (heard.isEmpty) return const [];
    final matches = <ConversationChoice>[];
    for (final choice in choices) {
      var matched = false;
      for (final keyword in [choice.line.targetText, ...choice.matchKeywords]) {
        final candidate = _normalizeSpeech(keyword);
        if (candidate.length >= 2 && _containsSpeechPhrase(heard, candidate)) {
          matched = true;
          break;
        }
      }
      if (matched) matches.add(choice);
    }
    return List.unmodifiable(matches);
  }

  ConversationChoice? choiceForTranscript(String transcript) {
    final matches = matchingChoicesForTranscript(transcript);
    return matches.length == 1 ? matches.single : null;
  }
}

class ConversationChoice {
  const ConversationChoice({
    required this.id,
    required this.emoji,
    required this.line,
    required this.matchKeywords,
    required this.elderReply,
    required this.sceneAfter,
    required this.storyBeatZh,
    this.nextPromptId,
  });

  final String id;
  final String emoji;
  final ConversationLine line;
  final List<String> matchKeywords;
  final ConversationLine elderReply;
  final ConversationSceneSnapshot sceneAfter;
  final String storyBeatZh;
  final String? nextPromptId;
}

class ConversationLine {
  const ConversationLine({
    required this.targetText,
    required this.translationZh,
    required this.romanization,
    this.audioPath,
  });

  final String targetText;
  final String translationZh;
  final String romanization;
  final String? audioPath;
}

class ConversationSceneSnapshot {
  const ConversationSceneSnapshot({
    required this.id,
    required this.headlineZh,
    required this.descriptionZh,
    required this.focusEmoji,
    required this.environmentEmojis,
  });

  final String id;
  final String headlineZh;
  final String descriptionZh;
  final String focusEmoji;
  final List<String> environmentEmojis;
}

class ConversationStoryMoment {
  const ConversationStoryMoment({
    required this.choiceId,
    required this.emoji,
    required this.childLine,
    required this.translationZh,
    required this.storyBeatZh,
    this.transcript,
  });

  final String choiceId;
  final String emoji;
  final String childLine;
  final String translationZh;
  final String storyBeatZh;
  final String? transcript;

  Map<String, Object?> toJson() => {
        'choiceId': choiceId,
        'emoji': emoji,
        'childLine': childLine,
        'translationZh': translationZh,
        'storyBeatZh': storyBeatZh,
        'transcript': transcript,
      };
}

class ConversationStoryCard {
  const ConversationStoryCard({
    required this.id,
    required this.episodeId,
    required this.title,
    required this.elderName,
    required this.completedAt,
    required this.endingTitleZh,
    required this.endingEmoji,
    required this.moments,
  });

  final String id;
  final String episodeId;
  final String title;
  final String elderName;
  final DateTime completedAt;
  final String endingTitleZh;
  final String endingEmoji;
  final List<ConversationStoryMoment> moments;

  String get shareMessageZh =>
      '我和$elderName演完了「$title」，還留下 ${moments.length} 句家裡的話。';

  Map<String, Object?> toJson() => {
        'id': id,
        'episodeId': episodeId,
        'title': title,
        'elderName': elderName,
        'completedAt': completedAt.toIso8601String(),
        'endingTitleZh': endingTitleZh,
        'endingEmoji': endingEmoji,
        'moments': moments.map((moment) => moment.toJson()).toList(),
      };
}

String _normalizeSpeech(String value) => value
    .toLowerCase()
    .replaceAll(
        RegExp(r'[^a-z0-9\u00c0-\u024f\u1e00-\u1eff\u3400-\u9fff]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

bool _containsSpeechPhrase(String heard, String candidate) {
  if (heard == candidate) return true;

  // Han-script recognizers commonly omit spaces, so the reviewed phrase must
  // be searched as a sequence. Ambiguity is still rejected by the caller.
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(candidate)) {
    return heard.contains(candidate);
  }

  // For alphabetic languages, respect word boundaries. This avoids treating a
  // short fragment inside another word as evidence for a choice.
  return heard.startsWith('$candidate ') ||
      heard.endsWith(' $candidate') ||
      heard.contains(' $candidate ');
}

/// Built-in episodes are deliberately scripted and reviewable. They keep the
/// prototype useful when speech recognition or a remote AI provider is absent.
abstract final class ConversationEpisodeCatalog {
  static final homecoming = _withBundledConversationAudio(ConversationEpisode(
    id: 'theater-homecoming',
    title: '放學回家',
    subtitle: '推開門，告訴外婆今天發生了什麼',
    elderName: '外婆',
    elderAvatarEmoji: '👵🏻',
    languageName: '越南語',
    languageTag: 'vi-VN',
    estimatedDurationSeconds: 75,
    openingPromptId: 'home-door',
    illustrationAsset: 'assets/images/family-homecoming-theater-v2.png',
    openingScene: ConversationSceneSnapshot(
      id: 'home-closed-door',
      headlineZh: '門裡傳來外婆的聲音',
      descriptionZh: '雨還滴答滴答，敲門讓外婆知道你回來了。',
      focusEmoji: '🚪',
      environmentEmojis: ['🌧️', '🎒', '🏠'],
    ),
    prompts: [
      ConversationPrompt(
        id: 'home-door',
        step: 1,
        elderLine: ConversationLine(
          targetText: 'Cháu về rồi à?',
          translationZh: '你回來啦？',
          romanization: 'cháu / về rồi / à',
        ),
        stageDirectionZh: '告訴外婆：你回來了，或今天有點累。',
        choices: [
          ConversationChoice(
            id: 'came-home',
            emoji: '🙋🏻',
            line: ConversationLine(
              targetText: 'Cháu về rồi ạ.',
              translationZh: '我回來了。',
              romanization: 'cháu / về rồi / ạ',
            ),
            matchKeywords: ['về rồi', 'cháu về', '回來'],
            elderReply: ConversationLine(
              targetText: 'Bà nhớ cháu quá!',
              translationZh: '外婆好想你！',
              romanization: 'bà / nhớ cháu / quá',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-door-open',
              headlineZh: '門打開了！',
              descriptionZh: '外婆笑著接過你的書包。',
              focusEmoji: '✨',
              environmentEmojis: ['🚪', '👵🏻', '🎒'],
            ),
            storyBeatZh: '你一說「我回來了」，外婆就笑著開門。',
            nextPromptId: 'home-happy-day',
          ),
          ConversationChoice(
            id: 'a-bit-tired',
            emoji: '😮‍💨',
            line: ConversationLine(
              targetText: 'Cháu hơi mệt ạ.',
              translationZh: '我有一點累。',
              romanization: 'cháu / hơi mệt / ạ',
            ),
            matchKeywords: ['hơi mệt', 'mệt', '有點累', '累'],
            elderReply: ConversationLine(
              targetText: 'Ôi, vào nghỉ một chút nhé.',
              translationZh: '哎呀，進來休息一下吧。',
              romanization: 'ôi / vào nghỉ / một chút nhé',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-cushion',
              headlineZh: '外婆搬來軟墊',
              descriptionZh: '外婆聽見你累了，先把書包放好。',
              focusEmoji: '🛋️',
              environmentEmojis: ['👵🏻', '💗', '🎒'],
            ),
            storyBeatZh: '你說今天有點累，外婆立刻幫你準備休息的地方。',
            nextPromptId: 'home-comfort',
          ),
        ],
      ),
      ConversationPrompt(
        id: 'home-happy-day',
        step: 2,
        elderLine: ConversationLine(
          targetText: 'Hôm nay vui không?',
          translationZh: '今天開心嗎？',
          romanization: 'hôm nay / vui không',
        ),
        stageDirectionZh: '選一件今天想告訴外婆的事。',
        choices: [
          ConversationChoice(
            id: 'happy-today',
            emoji: '😄',
            line: ConversationLine(
              targetText: 'Hôm nay vui ạ.',
              translationZh: '今天很開心。',
              romanization: 'hôm nay / vui / ạ',
            ),
            matchKeywords: ['hôm nay vui', 'vui', '開心'],
            elderReply: ConversationLine(
              targetText: 'Kể bà nghe nhé!',
              translationZh: '說給外婆聽吧！',
              romanization: 'kể bà / nghe nhé',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-happy-story',
              headlineZh: '快樂冒出小星星',
              descriptionZh: '外婆坐下來，準備聽你的校園故事。',
              focusEmoji: '🌟',
              environmentEmojis: ['😄', '📚', '👵🏻'],
            ),
            storyBeatZh: '你把今天的快樂帶回家，外婆想聽完整故事。',
            nextPromptId: 'home-final-after-happy-today',
          ),
          ConversationChoice(
            id: 'new-friend',
            emoji: '🧑🏻‍🤝‍🧑🏻',
            line: ConversationLine(
              targetText: 'Cháu có bạn mới ạ.',
              translationZh: '我交了新朋友。',
              romanization: 'cháu / có bạn mới / ạ',
            ),
            matchKeywords: ['bạn mới', 'có bạn', '新朋友'],
            elderReply: ConversationLine(
              targetText: 'Hay quá! Lát nữa kể bà nghe nhé.',
              translationZh: '太好了！等等說給外婆聽。',
              romanization: 'hay quá / lát nữa / kể bà nghe nhé',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-new-friend',
              headlineZh: '故事多了一位新朋友',
              descriptionZh: '外婆把新朋友也畫進今天的回憶裡。',
              focusEmoji: '🖍️',
              environmentEmojis: ['🧑🏻‍🤝‍🧑🏻', '📒', '💛'],
            ),
            storyBeatZh: '你把新朋友介紹給外婆，家庭故事多了一位角色。',
            nextPromptId: 'home-final-after-new-friend',
          ),
        ],
      ),
      ConversationPrompt(
        id: 'home-comfort',
        step: 2,
        elderLine: ConversationLine(
          targetText: 'Cháu muốn nghỉ hay uống nước?',
          translationZh: '你想休息，還是喝水？',
          romanization: 'cháu muốn / nghỉ / hay uống nước',
        ),
        stageDirectionZh: '告訴外婆，現在什麼會讓你舒服一點。',
        choices: [
          ConversationChoice(
            id: 'want-rest',
            emoji: '🛋️',
            line: ConversationLine(
              targetText: 'Cháu muốn nghỉ ạ.',
              translationZh: '我想休息。',
              romanization: 'cháu muốn / nghỉ / ạ',
            ),
            matchKeywords: ['muốn nghỉ', 'nghỉ', '休息'],
            elderReply: ConversationLine(
              targetText: 'Bà để gối ở đây nhé.',
              translationZh: '外婆把枕頭放這裡。',
              romanization: 'bà để gối / ở đây nhé',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-resting',
              headlineZh: '沙發變成小小休息站',
              descriptionZh: '枕頭蓬蓬的，你可以先慢慢呼吸。',
              focusEmoji: '💤',
              environmentEmojis: ['🛋️', '🧸', '👵🏻'],
            ),
            storyBeatZh: '你說出自己的需要，外婆陪你安靜休息。',
            nextPromptId: 'home-final-after-want-rest',
          ),
          ConversationChoice(
            id: 'want-water',
            emoji: '🥤',
            line: ConversationLine(
              targetText: 'Cho cháu nước ạ.',
              translationZh: '請給我水。',
              romanization: 'cho cháu / nước / ạ',
            ),
            matchKeywords: ['cho cháu nước', 'nước', '水'],
            elderReply: ConversationLine(
              targetText: 'Đây, uống từ từ nhé.',
              translationZh: '來，慢慢喝。',
              romanization: 'đây / uống từ từ nhé',
            ),
            sceneAfter: ConversationSceneSnapshot(
              id: 'home-water',
              headlineZh: '桌上出現一杯水',
              descriptionZh: '外婆聽懂了，水杯真的送到你手上。',
              focusEmoji: '💧',
              environmentEmojis: ['🥤', '👵🏻', '💙'],
            ),
            storyBeatZh: '你開口說想喝水，外婆馬上拿來一杯。',
            nextPromptId: 'home-final-after-want-water',
          ),
        ],
      ),
      _homecomingFinalPrompt(
        id: 'home-final-after-happy-today',
        bridgeTarget: 'Nghe cháu vui, bà cũng vui.',
        bridgeZh: '聽見你開心，外婆也好開心。',
        bridgeRomanization: 'nghe cháu vui / bà cũng vui',
        rememberedBeatZh: '今天的快樂還在房間裡閃亮。',
      ),
      _homecomingFinalPrompt(
        id: 'home-final-after-new-friend',
        bridgeTarget: 'Mai kể bà nghe về bạn mới nhé.',
        bridgeZh: '明天也要說新朋友的故事給外婆聽。',
        bridgeRomanization: 'mai / kể bà nghe / về bạn mới nhé',
        rememberedBeatZh: '新朋友已經被畫進今天的家庭故事。',
      ),
      _homecomingFinalPrompt(
        id: 'home-final-after-want-rest',
        bridgeTarget: 'Cháu nghỉ một chút rồi mình đi nhé.',
        bridgeZh: '你休息一下，我們再一起走。',
        bridgeRomanization: 'cháu nghỉ một chút / rồi mình đi nhé',
        rememberedBeatZh: '軟枕頭還在陪你慢慢恢復力氣。',
      ),
      _homecomingFinalPrompt(
        id: 'home-final-after-want-water',
        bridgeTarget: 'Uống nước xong rồi mình đi nhé.',
        bridgeZh: '喝完水，我們再一起走。',
        bridgeRomanization: 'uống nước xong / rồi mình đi nhé',
        rememberedBeatZh: '那杯水讓你舒服多了。',
      ),
    ],
  ));

  static final morning = _threeTurnEpisode(
    id: 'theater-morning',
    title: '早安！起床囉',
    subtitle: '從睜開眼睛到選好早餐',
    openingEmoji: '🌤️',
    illustrationAsset: 'assets/images/family-morning-game-v1.webp',
    prompt1: _SeedPrompt(
      elderTarget: 'Cháu dậy rồi à?',
      elderZh: '你起床啦？',
      elderRomanization: 'cháu / dậy rồi / à',
      cueZh: '告訴外婆你醒了，或還有一點想睡。',
      options: [
        _SeedChoice(
          'awake',
          '🙋🏻',
          'Cháu dậy rồi ạ.',
          '我起床了。',
          'cháu / dậy rồi / ạ',
          ['dậy rồi'],
          'Chào buổi sáng!',
          '早安！',
          'chào buổi sáng',
          '窗簾拉開了',
          '陽光跑進房間。',
          nextLeadTarget: 'Nắng vào phòng rồi.',
          nextLeadZh: '陽光已經跑進房間了。',
          nextLeadRomanization: 'nắng / vào phòng rồi',
        ),
        _SeedChoice(
          'sleepy',
          '🥱',
          'Cháu còn buồn ngủ ạ.',
          '我還想睡。',
          'cháu / còn buồn ngủ / ạ',
          ['buồn ngủ'],
          'Mình vươn vai nhé.',
          '我們先伸伸懶腰。',
          'mình / vươn vai nhé',
          '一起伸個懶腰',
          '身體慢慢醒過來。',
          nextLeadTarget: 'Cháu tỉnh hơn rồi đấy.',
          nextLeadZh: '你已經清醒一點了。',
          nextLeadRomanization: 'cháu / tỉnh hơn rồi đấy',
        ),
      ],
    ),
    prompt2: _SeedPrompt(
      elderTarget: 'Cháu muốn mặc áo màu nào?',
      elderZh: '你想穿哪個顏色？',
      elderRomanization: 'cháu muốn / mặc áo / màu nào',
      cueZh: '選一件今天想穿的衣服。',
      options: [
        _SeedChoice(
            'yellow-shirt',
            '💛',
            'Áo màu vàng ạ.',
            '黃色的衣服。',
            'áo / màu vàng / ạ',
            ['màu vàng'],
            'Sáng như mặt trời!',
            '像太陽一樣亮！',
            'sáng / như mặt trời',
            '換上太陽色上衣',
            '鏡子裡亮晶晶。'),
        _SeedChoice(
            'blue-shirt',
            '💙',
            'Áo màu xanh ạ.',
            '藍色的衣服。',
            'áo / màu xanh / ạ',
            ['màu xanh'],
            'Đẹp quá!',
            '真好看！',
            'đẹp quá',
            '換上藍色上衣',
            '像把天空穿在身上。'),
      ],
    ),
    prompt3: _SeedPrompt(
      elderTarget: 'Cháu muốn ăn gì?',
      elderZh: '你想吃什麼？',
      elderRomanization: 'cháu muốn / ăn gì',
      cueZh: '幫今天的早餐做決定。',
      options: [
        _SeedChoice(
            'bread',
            '🥖',
            'Cháu muốn ăn bánh mì ạ.',
            '我想吃麵包。',
            'cháu muốn / ăn bánh mì / ạ',
            ['bánh mì'],
            'Có ngay đây!',
            '馬上來！',
            'có ngay đây',
            '早餐麵包出爐',
            '香味叫醒整間屋子。'),
        _SeedChoice(
            'fruit',
            '🍌',
            'Cháu muốn ăn trái cây ạ.',
            '我想吃水果。',
            'cháu muốn / ăn trái cây / ạ',
            ['trái cây'],
            'Mình cùng chọn nhé!',
            '我們一起選！',
            'mình / cùng chọn nhé',
            '水果盤變得繽紛',
            '今天從甜甜的水果開始。'),
      ],
    ),
  );

  static final mealtime = _threeTurnEpisode(
    id: 'theater-mealtime',
    title: '一起準備晚餐',
    subtitle: '幫忙擺桌，也說出喜歡的味道',
    openingEmoji: '🍲',
    illustrationAsset: 'assets/images/family-mealtime-theater-v2.png',
    prompt1: _SeedPrompt(
      elderTarget: 'Cháu giúp bà nhé?',
      elderZh: '你來幫外婆好嗎？',
      elderRomanization: 'cháu / giúp bà / nhé',
      cueZh: '選一件你想幫忙的事。',
      options: [
        _SeedChoice(
          'bowls',
          '🥣',
          'Cháu lấy bát ạ.',
          '我來拿碗。',
          'cháu / lấy bát / ạ',
          ['lấy bát'],
          'Cảm ơn cháu!',
          '謝謝你！',
          'cảm ơn cháu',
          '碗排好隊了',
          '桌子準備迎接全家人。',
          nextLeadTarget: 'Bát đã sẵn sàng rồi.',
          nextLeadZh: '碗都準備好了。',
          nextLeadRomanization: 'bát / đã sẵn sàng rồi',
        ),
        _SeedChoice(
          'chopsticks',
          '🥢',
          'Cháu lấy đũa ạ.',
          '我來拿筷子。',
          'cháu / lấy đũa / ạ',
          ['lấy đũa'],
          'Khéo quá!',
          '好能幹！',
          'khéo quá',
          '筷子找到位置',
          '每個座位都準備好了。',
          nextLeadTarget: 'Đũa đã có chỗ rồi.',
          nextLeadZh: '筷子也找到位置了。',
          nextLeadRomanization: 'đũa / đã có chỗ rồi',
        ),
      ],
    ),
    prompt2: _SeedPrompt(
      elderTarget: 'Thơm không?',
      elderZh: '香不香？',
      elderRomanization: 'thơm / không',
      cueZh: '聞聞看，告訴外婆你的感覺。',
      options: [
        _SeedChoice(
            'smells-good',
            '😋',
            'Thơm lắm ạ.',
            '好香。',
            'thơm lắm / ạ',
            ['thơm lắm'],
            'Bà cũng thấy vậy!',
            '外婆也這麼覺得！',
            'bà / cũng thấy vậy',
            '香氣飄滿廚房',
            '大家都忍不住靠近餐桌。'),
        _SeedChoice(
            'a-bit-hot',
            '♨️',
            'Hơi nóng ạ.',
            '有一點燙。',
            'hơi nóng / ạ',
            ['hơi nóng'],
            'Mình chờ một chút nhé.',
            '我們等一下再吃。',
            'mình / chờ một chút nhé',
            '熱湯先吹一吹',
            '外婆和你一起耐心等。'),
      ],
    ),
    prompt3: _SeedPrompt(
      elderTarget: 'Mời cả nhà ăn cơm nào!',
      elderZh: '請大家一起吃飯！',
      elderRomanization: 'mời cả nhà / ăn cơm nào',
      cueZh: '把全家人邀請到餐桌邊。',
      options: [
        _SeedChoice(
            'invite-family',
            '👨‍👩‍👧',
            'Mời cả nhà ăn cơm ạ.',
            '請大家吃飯。',
            'mời cả nhà / ăn cơm / ạ',
            ['mời cả nhà'],
            'Cùng ăn thôi!',
            '一起吃吧！',
            'cùng ăn thôi',
            '全家都到齊了',
            '這句話讓晚餐正式開始。'),
        _SeedChoice(
            'invite-grandma',
            '👵🏻',
            'Mời bà ăn cơm ạ.',
            '外婆請吃飯。',
            'mời bà / ăn cơm / ạ',
            ['mời bà'],
            'Bà cảm ơn cháu!',
            '外婆謝謝你！',
            'bà / cảm ơn cháu',
            '先邀請外婆入座',
            '一句貼心的話讓外婆笑了。'),
      ],
    ),
  );

  static final garden = _threeTurnEpisode(
    id: 'theater-garden',
    title: '陽台澆花',
    subtitle: '和外婆照顧今天冒出的新葉子',
    openingEmoji: '🌱',
    illustrationAsset: 'assets/images/family-garden-theater-v1.png',
    prompt1: _SeedPrompt(
      elderTarget: 'Mình tưới cây nhé?',
      elderZh: '我們來澆花，好嗎？',
      elderRomanization: 'mình / tưới cây / nhé',
      cueZh: '告訴外婆你想怎麼幫忙。',
      options: [
        _SeedChoice(
          'water-plants',
          '🪴',
          'Cháu tưới cây ạ.',
          '我來澆花。',
          'cháu / tưới cây / ạ',
          ['tưới cây'],
          'Tưới nhẹ thôi nhé.',
          '輕輕澆就好。',
          'tưới nhẹ / thôi nhé',
          '小水珠落在土裡',
          '葉子像在跟你說謝謝。',
          nextLeadTarget: 'Đất đủ nước rồi.',
          nextLeadZh: '泥土已經喝飽水了。',
          nextLeadRomanization: 'đất / đủ nước rồi',
        ),
        _SeedChoice(
          'hold-can',
          '🫗',
          'Cháu cầm bình ạ.',
          '我來拿澆水壺。',
          'cháu / cầm bình / ạ',
          ['cầm bình'],
          'Mình cùng làm nhé!',
          '我們一起來！',
          'mình / cùng làm nhé',
          '兩個人一起拿水壺',
          '水壺變得一點也不重。',
          nextLeadTarget: 'Mình đặt bình xuống nhé.',
          nextLeadZh: '我們把水壺放下來吧。',
          nextLeadRomanization: 'mình / đặt bình xuống nhé',
        ),
      ],
    ),
    prompt2: _SeedPrompt(
      elderTarget: 'Cháu thấy gì?',
      elderZh: '你看到什麼？',
      elderRomanization: 'cháu / thấy gì',
      cueZh: '找找植物今天的新變化。',
      options: [
        _SeedChoice(
            'new-leaf',
            '🌿',
            'Có lá mới ạ.',
            '有新葉子。',
            'có / lá mới / ạ',
            ['lá mới'],
            'Cháu quan sát giỏi quá!',
            '你觀察得真仔細！',
            'cháu / quan sát giỏi quá',
            '新葉子探出頭',
            '外婆把發現記進家庭日曆。'),
        _SeedChoice(
            'little-flower',
            '🌼',
            'Có hoa nhỏ ạ.',
            '有一朵小花。',
            'có / hoa nhỏ / ạ',
            ['hoa nhỏ'],
            'Đẹp quá nhỉ!',
            '真漂亮呀！',
            'đẹp quá nhỉ',
            '小花慢慢打開',
            '陽台多了一顆亮亮的小太陽。'),
      ],
    ),
    prompt3: _SeedPrompt(
      elderTarget: 'Đặt tên cho cây nhé?',
      elderZh: '幫植物取名字，好嗎？',
      elderRomanization: 'đặt tên / cho cây / nhé',
      cueZh: '為這位綠色朋友選一個名字。',
      options: [
        _SeedChoice(
            'sun-name',
            '☀️',
            'Tên là Mặt Trời ạ.',
            '叫它小太陽。',
            'tên là / mặt trời / ạ',
            ['mặt trời'],
            'Tên hay quá!',
            '好棒的名字！',
            'tên hay quá',
            '植物有了名字：小太陽',
            '以後全家都知道怎麼叫它。'),
        _SeedChoice(
            'bean-name',
            '🫘',
            'Tên là Đậu Nhỏ ạ.',
            '叫它小豆豆。',
            'tên là / đậu nhỏ / ạ',
            ['đậu nhỏ'],
            'Dễ thương quá!',
            '真可愛！',
            'dễ thương quá',
            '植物有了名字：小豆豆',
            '新的家庭成員住進陽台。'),
      ],
    ),
  );

  static final bedtime = _threeTurnEpisode(
    id: 'theater-bedtime',
    title: '睡前故事',
    subtitle: '選一個故事，再把晚安送給家人',
    openingEmoji: '🌙',
    illustrationAsset: 'assets/images/family-bedtime-theater-v1.png',
    prompt1: _SeedPrompt(
      elderTarget: 'Đến giờ đi ngủ rồi.',
      elderZh: '睡覺時間到了。',
      elderRomanization: 'đến giờ / đi ngủ rồi',
      cueZh: '告訴外婆，你想先做什麼。',
      options: [
        _SeedChoice(
          'story-first',
          '📖',
          'Bà kể chuyện nhé.',
          '外婆說故事吧。',
          'bà / kể chuyện / nhé',
          ['kể chuyện'],
          'Được, cháu chọn nhé.',
          '好，你來選。',
          'được / cháu chọn nhé',
          '故事書打開了',
          '月光也湊過來聽。',
          nextLeadTarget: 'Sách đã mở rồi.',
          nextLeadZh: '故事書已經打開了。',
          nextLeadRomanization: 'sách / đã mở rồi',
        ),
        _SeedChoice(
          'not-sleepy',
          '🧸',
          'Cháu chưa buồn ngủ ạ.',
          '我還不睏。',
          'cháu / chưa buồn ngủ / ạ',
          ['chưa buồn ngủ'],
          'Mình ôm gấu và nghe chuyện nhé.',
          '我們抱著小熊聽故事吧。',
          'mình ôm gấu / và nghe chuyện nhé',
          '小熊也坐上床',
          '有小熊陪伴，房間安靜下來。',
          nextLeadTarget: 'Gấu bông cũng sẵn sàng rồi.',
          nextLeadZh: '小熊也準備好了。',
          nextLeadRomanization: 'gấu bông / cũng sẵn sàng rồi',
        ),
      ],
    ),
    prompt2: _SeedPrompt(
      elderTarget: 'Cháu chọn chuyện nào?',
      elderZh: '你選哪一個故事？',
      elderRomanization: 'cháu / chọn chuyện nào',
      cueZh: '今晚由你決定故事會去哪裡。',
      options: [
        _SeedChoice(
            'moon-story',
            '🌙',
            'Chuyện mặt trăng ạ.',
            '月亮的故事。',
            'chuyện / mặt trăng / ạ',
            ['mặt trăng'],
            'Mình bay lên trời nhé!',
            '我們飛上天空吧！',
            'mình / bay lên trời nhé',
            '床變成月亮船',
            '你和外婆一起飛過星星。'),
        _SeedChoice(
            'tiger-story',
            '🐯',
            'Chuyện con hổ ạ.',
            '老虎的故事。',
            'chuyện / con hổ / ạ',
            ['con hổ'],
            'Mình vào rừng nhé!',
            '我們進森林吧！',
            'mình / vào rừng nhé',
            '棉被變成森林',
            '一隻溫柔的小老虎來帶路。'),
      ],
    ),
    prompt3: _SeedPrompt(
      elderTarget: 'Chúc cháu ngủ ngon.',
      elderZh: '祝你睡得香甜。',
      elderRomanization: 'chúc cháu / ngủ ngon',
      cueZh: '把最後一句晚安送回給外婆。',
      options: [
        _SeedChoice(
            'goodnight-grandma',
            '💤',
            'Chúc bà ngủ ngon ạ.',
            '外婆晚安。',
            'chúc bà / ngủ ngon / ạ',
            ['chúc bà ngủ ngon'],
            'Bà yêu cháu.',
            '外婆愛你。',
            'bà / yêu cháu',
            '星星關上小夜燈',
            '你們互道晚安，把愛留在夢裡。'),
        _SeedChoice(
            'love-grandma',
            '💗',
            'Cháu yêu bà ạ.',
            '我愛外婆。',
            'cháu / yêu bà / ạ',
            ['yêu bà'],
            'Bà cũng yêu cháu.',
            '外婆也愛你。',
            'bà / cũng yêu cháu',
            '愛心藏進枕頭',
            '今晚的夢被家人的愛抱住。'),
      ],
    ),
  );

  static final List<ConversationEpisode> defaults = List.unmodifiable([
    homecoming,
    morning,
    mealtime,
    garden,
    bedtime,
  ]);

  static ConversationPrompt _homecomingFinalPrompt({
    required String id,
    required String bridgeTarget,
    required String bridgeZh,
    required String bridgeRomanization,
    required String rememberedBeatZh,
  }) {
    return ConversationPrompt(
      id: id,
      step: 3,
      elderLine: ConversationLine(
        targetText: '$bridgeTarget Mình rửa tay rồi ăn cơm nhé?',
        translationZh: '$bridgeZh 我們洗手再吃飯，好嗎？',
        romanization: '$bridgeRomanization / mình / rửa tay / rồi ăn cơm nhé',
      ),
      stageDirectionZh: '$rememberedBeatZh 為今天選一個溫暖的結尾。',
      choices: const [
        ConversationChoice(
          id: 'wash-hands',
          emoji: '🫧',
          line: ConversationLine(
            targetText: 'Vâng ạ!',
            translationZh: '好呀！',
            romanization: 'vâng / ạ',
          ),
          matchKeywords: ['vâng', 'dạ', '好呀', '好'],
          elderReply: ConversationLine(
            targetText: 'Ngoan quá, cùng đi thôi!',
            translationZh: '真棒，我們一起去！',
            romanization: 'ngoan quá / cùng đi thôi',
          ),
          sceneAfter: ConversationSceneSnapshot(
            id: 'home-wash-finale',
            headlineZh: '小泡泡帶你們去餐桌',
            descriptionZh: '洗好手，今天的家庭時間開始了。',
            focusEmoji: '🫧',
            environmentEmojis: ['👐🏻', '🍚', '👵🏻'],
          ),
          storyBeatZh: '你和外婆一起洗手，準備分享晚餐。',
        ),
        ConversationChoice(
          id: 'hug-first',
          emoji: '🫂',
          line: ConversationLine(
            targetText: 'Cháu ôm bà trước ạ.',
            translationZh: '我想先抱抱外婆。',
            romanization: 'cháu / ôm bà / trước ạ',
          ),
          matchKeywords: ['ôm bà', 'ôm', '抱抱', '外婆'],
          elderReply: ConversationLine(
            targetText: 'Lại đây với bà nào!',
            translationZh: '來外婆這裡吧！',
            romanization: 'lại đây / với bà nào',
          ),
          sceneAfter: ConversationSceneSnapshot(
            id: 'home-hug-finale',
            headlineZh: '先送外婆一個大抱抱',
            descriptionZh: '雨聲變小了，屋裡暖暖的。',
            focusEmoji: '🫂',
            environmentEmojis: ['👵🏻', '💞', '🏠'],
          ),
          storyBeatZh: '你先抱抱外婆，讓今天用想念收尾。',
        ),
      ],
    );
  }

  static ConversationEpisode _threeTurnEpisode({
    required String id,
    required String title,
    required String subtitle,
    required String openingEmoji,
    required String illustrationAsset,
    required _SeedPrompt prompt1,
    required _SeedPrompt prompt2,
    required _SeedPrompt prompt3,
  }) {
    ConversationPrompt buildPrompt(
      _SeedPrompt seed,
      int step, {
      String? promptId,
      _SeedChoice? followsChoice,
      String? earlierStoryBeatZh,
    }) {
      final bridgeTarget =
          followsChoice?.nextLeadTarget ?? followsChoice?.replyTarget;
      final bridgeZh = followsChoice?.nextLeadZh ?? followsChoice?.replyZh;
      final bridgeRomanization = followsChoice?.nextLeadRomanization ??
          followsChoice?.replyRomanization;

      return ConversationPrompt(
        id: promptId ?? '$id-$step',
        step: step,
        elderLine: ConversationLine(
          targetText: followsChoice == null
              ? seed.elderTarget
              : '$bridgeTarget ${seed.elderTarget}',
          translationZh: followsChoice == null
              ? seed.elderZh
              : '$bridgeZh ${seed.elderZh}',
          romanization: followsChoice == null
              ? seed.elderRomanization
              : '$bridgeRomanization / ${seed.elderRomanization}',
        ),
        stageDirectionZh: followsChoice == null
            ? seed.cueZh
            : [
                if (earlierStoryBeatZh != null) earlierStoryBeatZh,
                followsChoice.sceneHeadline,
                seed.cueZh,
              ].join('，'),
        choices: seed.options
            .map(
              (choice) => ConversationChoice(
                id: choice.id,
                emoji: choice.emoji,
                line: ConversationLine(
                  targetText: choice.target,
                  translationZh: choice.zh,
                  romanization: choice.romanization,
                ),
                matchKeywords: [choice.keyword, choice.zh],
                elderReply: ConversationLine(
                  targetText: choice.replyTarget,
                  translationZh: choice.replyZh,
                  romanization: choice.replyRomanization,
                ),
                sceneAfter: ConversationSceneSnapshot(
                  id: '$id-${choice.id}',
                  headlineZh: choice.sceneHeadline,
                  descriptionZh: choice.sceneDescription,
                  focusEmoji: choice.emoji,
                  environmentEmojis: [openingEmoji, choice.emoji, '✨'],
                ),
                storyBeatZh: '${choice.zh}${choice.sceneDescription}',
                nextPromptId: switch (step) {
                  1 => '$id-2-after-${choice.id}',
                  2 => '$id-3-after-${followsChoice!.id}-${choice.id}',
                  _ => null,
                },
              ),
            )
            .toList(growable: false),
      );
    }

    return _withBundledConversationAudio(ConversationEpisode(
      id: id,
      title: title,
      subtitle: subtitle,
      elderName: '外婆',
      elderAvatarEmoji: '👵🏻',
      languageName: '越南語',
      languageTag: 'vi-VN',
      estimatedDurationSeconds: 70,
      illustrationAsset: illustrationAsset,
      openingPromptId: '$id-1',
      openingScene: ConversationSceneSnapshot(
        id: '$id-opening',
        headlineZh: title,
        descriptionZh: subtitle,
        focusEmoji: openingEmoji,
        environmentEmojis: [openingEmoji, '🏠', '👵🏻'],
      ),
      prompts: [
        buildPrompt(prompt1, 1),
        for (final firstChoice in prompt1.options)
          buildPrompt(
            prompt2,
            2,
            promptId: '$id-2-after-${firstChoice.id}',
            followsChoice: firstChoice,
          ),
        for (final firstChoice in prompt1.options)
          for (final secondChoice in prompt2.options)
            buildPrompt(
              prompt3,
              3,
              promptId: '$id-3-after-${firstChoice.id}-${secondChoice.id}',
              followsChoice: secondChoice,
              earlierStoryBeatZh: firstChoice.sceneHeadline,
            ),
      ],
    ));
  }
}

/// Stable asset name for a reviewed theater line.
///
/// The catalog uses the target-language text itself as the identity so repeated
/// lines across branches share one small bundled MP3. This keeps the primary
/// story flow audible even when Web Speech exposes no Vietnamese system voice.
String bundledConversationAudioPath(String targetText) {
  final key =
      sha256.convert(utf8.encode(targetText)).toString().substring(0, 12);
  return 'asset://assets/audio/theater_$key.mp3';
}

ConversationEpisode _withBundledConversationAudio(
  ConversationEpisode episode,
) {
  ConversationLine line(ConversationLine source) => ConversationLine(
        targetText: source.targetText,
        translationZh: source.translationZh,
        romanization: source.romanization,
        audioPath:
            source.audioPath ?? bundledConversationAudioPath(source.targetText),
      );

  return ConversationEpisode(
    id: episode.id,
    title: episode.title,
    subtitle: episode.subtitle,
    elderName: episode.elderName,
    elderAvatarEmoji: episode.elderAvatarEmoji,
    languageName: episode.languageName,
    languageTag: episode.languageTag,
    estimatedDurationSeconds: episode.estimatedDurationSeconds,
    openingPromptId: episode.openingPromptId,
    openingScene: episode.openingScene,
    illustrationAsset: episode.illustrationAsset,
    prompts: [
      for (final prompt in episode.prompts)
        ConversationPrompt(
          id: prompt.id,
          step: prompt.step,
          elderLine: line(prompt.elderLine),
          stageDirectionZh: prompt.stageDirectionZh,
          choices: [
            for (final choice in prompt.choices)
              ConversationChoice(
                id: choice.id,
                emoji: choice.emoji,
                line: line(choice.line),
                matchKeywords: choice.matchKeywords,
                elderReply: line(choice.elderReply),
                sceneAfter: choice.sceneAfter,
                storyBeatZh: choice.storyBeatZh,
                nextPromptId: choice.nextPromptId,
              ),
          ],
        ),
    ],
  );
}

class _SeedPrompt {
  const _SeedPrompt({
    required this.elderTarget,
    required this.elderZh,
    required this.elderRomanization,
    required this.cueZh,
    required this.options,
  });

  final String elderTarget;
  final String elderZh;
  final String elderRomanization;
  final String cueZh;
  final List<_SeedChoice> options;
}

class _SeedChoice {
  const _SeedChoice(
    this.id,
    this.emoji,
    this.target,
    this.zh,
    this.romanization,
    this.keywords,
    this.replyTarget,
    this.replyZh,
    this.replyRomanization,
    this.sceneHeadline,
    this.sceneDescription, {
    this.nextLeadTarget,
    this.nextLeadZh,
    this.nextLeadRomanization,
  });

  final String id;
  final String emoji;
  final String target;
  final String zh;
  final String romanization;
  final List<String> keywords;
  final String replyTarget;
  final String replyZh;
  final String replyRomanization;
  final String sceneHeadline;
  final String sceneDescription;
  final String? nextLeadTarget;
  final String? nextLeadZh;
  final String? nextLeadRomanization;

  String get keyword => keywords.first;
}
