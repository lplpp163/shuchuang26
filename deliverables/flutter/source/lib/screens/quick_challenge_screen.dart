import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/family_story.dart';
import '../models/lesson_content.dart';
import '../models/task_draft.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import '../widgets/recording_control.dart';

abstract interface class QuickChallengeDraftGenerator {
  const QuickChallengeDraftGenerator();

  String get disclosure;

  Future<QuickChallengeDraft> generate({
    required String sourceText,
    required String languageName,
  });
}

class LocalQuickChallengeDraftGenerator
    implements QuickChallengeDraftGenerator {
  const LocalQuickChallengeDraftGenerator();

  @override
  String get disclosure => '內建生活模板只在這個裝置整理文字，並從早晨、玄關、餐桌、陽台與睡前五張圖庫情境中選一張。';

  static const _templates = <_LocalScenarioTemplate>[
    _LocalScenarioTemplate(
      keywords: ['早安', '早上', '早晨', '起床'],
      title: '早上先向家人問好',
      sceneLabel: '早安問候',
      sceneKind: _SceneKind.morning,
      translationZh: '外婆／奶奶您好。',
      vietnamese: 'Cháu chào bà ạ.',
      chunks: ['Cháu chào', 'bà ạ'],
      memoryTip: '每天第一次見到家人時說一次。',
    ),
    _LocalScenarioTemplate(
      keywords: ['放學', '回家', '回來', '到家'],
      title: '放學回家的第一句',
      sceneLabel: '放學回家',
      sceneKind: _SceneKind.homecoming,
      translationZh: '我回來了。',
      vietnamese: 'Con về rồi ạ.',
      chunks: ['Con về', 'rồi ạ'],
      memoryTip: '孩子一進門時就說一次，最容易記住。',
    ),
    _LocalScenarioTemplate(
      keywords: ['吃飯', '開飯', '餐桌', '晚餐'],
      title: '開飯前說一句',
      sceneLabel: '一起吃飯',
      sceneKind: _SceneKind.mealtime,
      translationZh: '請大家吃飯。',
      vietnamese: 'Mời cả nhà ăn cơm ạ.',
      chunks: ['Mời cả nhà', 'ăn cơm ạ'],
      memoryTip: '每天開飯前，全家一起說一次。',
    ),
    _LocalScenarioTemplate(
      keywords: ['睡覺', '晚安', '上床', '睡前'],
      title: '睡前的晚安',
      sceneLabel: '準備睡覺',
      sceneKind: _SceneKind.bedtime,
      translationZh: '晚安。',
      vietnamese: 'Chúc ngủ ngon ạ.',
      chunks: ['Chúc', 'ngủ ngon ạ'],
      memoryTip: '關燈前說一次，讓這句話變成家的習慣。',
    ),
    _LocalScenarioTemplate(
      keywords: ['澆花', '澆水', '陽台', '植物', '花盆'],
      title: '和家人一起照顧植物',
      sceneLabel: '陽台澆花',
      sceneKind: _SceneKind.garden,
      translationZh: '我來澆花。',
      vietnamese: 'Cháu tưới cây ạ.',
      chunks: ['Cháu tưới cây', 'ạ'],
      memoryTip: '拿起澆水壺時說一次，讓語言和動作連在一起。',
    ),
  ];

  static const _storySeeds = <_StorySeedTemplate>[
    _StorySeedTemplate(
      keywords: ['社團'],
      missionTitle: '把社團故事帶回家',
      sceneLabel: '社團時間',
      sceneKind: _SceneKind.homecoming,
      memoryTip: '放學後先挑一件社團裡最想分享的事，再用家裡話說一句。',
      familyReply: '家人接著問：「社團裡哪一刻最想讓我看見？」',
    ),
    _StorySeedTemplate(
      keywords: ['午餐'],
      missionTitle: '把午餐故事帶回家',
      sceneLabel: '今天的午餐',
      sceneKind: _SceneKind.mealtime,
      memoryTip: '吃飯時再說一次今天午餐最有印象的味道。',
      familyReply: '家人接著問：「如果一起做，你最想讓我嚐哪一道？」',
    ),
    _StorySeedTemplate(
      keywords: ['上課', '學到'],
      missionTitle: '把上課發現帶回家',
      sceneLabel: '今天的課堂',
      sceneKind: _SceneKind.homecoming,
      memoryTip: '回家後用一件小事示範今天學到的內容，再說這一句。',
      familyReply: '家人接著問：「可以用家裡的東西教我一次嗎？」',
    ),
    _StorySeedTemplate(
      keywords: ['朋友'],
      missionTitle: '把朋友的故事說給家人聽',
      sceneLabel: '朋友之間',
      sceneKind: _SceneKind.homecoming,
      memoryTip: '先說發生了什麼，再說自己希望明天怎麼做。',
      familyReply: '家人接著問：「你希望朋友聽懂你哪一個感受？」',
    ),
    _StorySeedTemplate(
      keywords: ['最想告訴你', '分享今天發生的事'],
      missionTitle: '把今天最重要的事帶回家',
      sceneLabel: '和家人分享',
      sceneKind: _SceneKind.homecoming,
      memoryTip: '每天挑一件最想讓家人知道的事，用家裡話留下一句。',
      familyReply: '家人接著問：「這件事讓你有什麼感覺？」',
    ),
  ];

  @override
  Future<QuickChallengeDraft> generate({
    required String sourceText,
    required String languageName,
  }) async {
    final normalized = sourceText.toLowerCase();
    _LocalScenarioTemplate? template;
    for (final item in _templates) {
      if (item.keywords.any(normalized.contains)) {
        template = item;
        break;
      }
    }
    _StorySeedTemplate? storySeed;
    for (final item in _storySeeds) {
      if (item.keywords.any(normalized.contains)) {
        storySeed = item;
        break;
      }
    }

    final intent = _extractIntent(sourceText) ??
        template?.translationZh.replaceAll('。', '') ??
        '這句家裡話';
    final hasLocalVietnamese = languageName == '越南語' && template != null;
    final targetText = hasLocalVietnamese ? template.vietnamese : intent;
    final translation = template?.translationZh ?? _withStop(intent);
    final chunks =
        hasLocalVietnamese ? template.chunks : _splitIntoChunks(targetText);
    final summary = sourceText
        .split(RegExp(r'[\n，。！？]'))
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '生活片段');
    final scene =
        storySeed?.sceneLabel ?? template?.sceneLabel ?? _shorten(summary, 12);
    final title = storySeed?.missionTitle ??
        (template == null ? '$scene的一句話' : template.title);
    final requiresReview = !hasLocalVietnamese;
    final sceneKind = storySeed?.sceneKind ??
        template?.sceneKind ??
        _sceneKindFor(normalized);
    final scenePreset = _ScenePreset.forKind(sceneKind);
    final challenge = template == null && storySeed == null
        ? null
        : scenePreset.buildChallenge(
            targetText: targetText,
            translationZh: translation,
            cultureNoteZh: storySeed?.familyReply,
          );

    return QuickChallengeDraft(
      title: title,
      sceneLabel: scene,
      targetText: targetText,
      translationZh: translation,
      pronunciationGuide: hasLocalVietnamese
          ? targetText
              .replaceAll(RegExp(r'[.!?]'), '')
              .split(RegExp(r'\s+'))
              .join(' · ')
          : '',
      promptZh: '在「$scene」時，請孩子跟著家人說一次：「$translation」',
      chunks: chunks,
      memoryTipZh:
          storySeed?.memoryTip ?? template?.memoryTip ?? '在這個情況真的發生時，全家再說一次。',
      confidence: hasLocalVietnamese ? .82 : .48,
      requiresTargetReview: requiresReview,
      illustrationAsset: scenePreset.assetPath,
      familyChallenge: challenge,
      generatorNote: requiresReview
          ? '本機模板沒有替這段話翻譯；已先保留意思，請把「孩子要說」改成家裡真正的說法。'
          : '這是本機生活模板草稿，請家人確認是否符合家裡自然的說法。',
    );
  }

  static _SceneKind _sceneKindFor(String source) {
    if (['睡覺', '晚安', '上床', '睡前'].any(source.contains)) {
      return _SceneKind.bedtime;
    }
    if (['澆花', '澆水', '陽台', '植物', '花盆'].any(source.contains)) {
      return _SceneKind.garden;
    }
    if (['早安', '早上', '早晨', '起床'].any(source.contains)) {
      return _SceneKind.morning;
    }
    if (['放學', '回家', '回來', '到家', '出門', '鞋', '上學', '分享', '社團', '上課', '朋友']
        .any(source.contains)) {
      return _SceneKind.homecoming;
    }
    return _SceneKind.mealtime;
  }

  static String? _extractIntent(String source) {
    final quote = RegExp(r'[「『“"]([^」』”"]{1,30})[」』”"]').firstMatch(source);
    if (quote != null) return quote.group(1)?.trim();
    final afterSay = RegExp(
      r'(?:想教孩子|教孩子|想讓孩子|讓孩子)?(?:說|講)[：: ]*([^，。！!\n]{2,24})',
    ).firstMatch(source);
    return afterSay?.group(1)?.trim();
  }

  static List<String> _splitIntoChunks(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[,.!?，。！？]+$'), '');
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length > 1) {
      final split = (words.length / 2).ceil();
      return [words.take(split).join(' '), words.skip(split).join(' ')];
    }
    if (cleaned.length > 6) {
      final split = (cleaned.length / 2).ceil();
      return [cleaned.substring(0, split), cleaned.substring(split)];
    }
    return [if (cleaned.isNotEmpty) cleaned];
  }

  static String _withStop(String value) =>
      RegExp(r'[。！？!?]$').hasMatch(value) ? value : '$value。';

  static String _shorten(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';
}

class QuickChallengeDraft {
  const QuickChallengeDraft({
    required this.title,
    required this.sceneLabel,
    required this.targetText,
    required this.translationZh,
    required this.pronunciationGuide,
    required this.promptZh,
    required this.chunks,
    required this.memoryTipZh,
    required this.confidence,
    required this.requiresTargetReview,
    required this.illustrationAsset,
    required this.familyChallenge,
    required this.generatorNote,
  });

  final String title;
  final String sceneLabel;
  final String targetText;
  final String translationZh;
  final String pronunciationGuide;
  final String promptZh;
  final List<String> chunks;
  final String memoryTipZh;
  final double confidence;
  final bool requiresTargetReview;
  final String illustrationAsset;
  final FamilyChallenge? familyChallenge;
  final String generatorNote;
}

class QuickChallengeScreen extends StatefulWidget {
  const QuickChallengeScreen({
    required this.store,
    required this.media,
    required this.onCreated,
    this.draftGenerator,
    this.initialSourceText,
    this.originStoryIdeaId,
    this.originStoryIdeaTitle,
    this.relayId,
    this.relayChildIntentZh,
    this.adultMemberId,
    super.key,
  }) : assert(relayId == null || adultMemberId != null);

  final AppStore store;
  final LocalMediaService media;
  final ValueChanged<FamilyStory> onCreated;
  final QuickChallengeDraftGenerator? draftGenerator;
  final String? initialSourceText;
  final String? originStoryIdeaId;
  final String? originStoryIdeaTitle;
  final String? relayId;
  final String? relayChildIntentZh;
  final String? adultMemberId;

  @override
  State<QuickChallengeScreen> createState() => _QuickChallengeScreenState();
}

class _QuickChallengeScreenState extends State<QuickChallengeScreen> {
  static const _examples = <_ScenarioExample>[
    _ScenarioExample(
      icon: Icons.wb_sunny_rounded,
      label: '早安問候',
      text: '早上起床看到外婆，想教孩子先說「外婆早安」',
    ),
    _ScenarioExample(
      icon: Icons.backpack_rounded,
      label: '放學回家',
      text: '放學回家，想教孩子說「我回來了」',
    ),
    _ScenarioExample(
      icon: Icons.restaurant_rounded,
      label: '一起吃飯',
      text: '晚餐開動前，想教孩子請全家一起吃飯',
    ),
    _ScenarioExample(
      icon: Icons.bedtime_rounded,
      label: '睡前晚安',
      text: '準備關燈睡覺，想教孩子跟家人說晚安',
    ),
    _ScenarioExample(
      icon: Icons.local_florist_rounded,
      label: '陽台澆花',
      text: '和外婆一起照顧植物，想教孩子說「我來澆花」',
    ),
  ];

  final _sourceText = TextEditingController();
  final _title = TextEditingController();
  final _sceneLabel = TextEditingController();
  final _targetText = TextEditingController();
  final _translation = TextEditingController();
  final _pronunciation = TextEditingController();
  final _prompt = TextEditingController();
  final _chunks = TextEditingController();

  String _languageName = '越南語';
  QuickChallengeDraft? _draft;
  String? _audioPath;
  bool _generating = false;
  bool _saving = false;
  bool _sourceOutdated = false;
  bool _familyConfirmedTarget = false;
  int _recordingGeneration = 0;
  late final QuickChallengeDraftGenerator _draftGenerator;

  @override
  void initState() {
    super.initState();
    _draftGenerator =
        widget.draftGenerator ?? const LocalQuickChallengeDraftGenerator();
    final initialSourceText = widget.initialSourceText?.trim();
    if (initialSourceText != null && initialSourceText.isNotEmpty) {
      _sourceText.text = initialSourceText;
    }
  }

  @override
  void dispose() {
    _sourceText.dispose();
    _title.dispose();
    _sceneLabel.dispose();
    _targetText.dispose();
    _translation.dispose();
    _pronunciation.dispose();
    _prompt.dispose();
    _chunks.dispose();
    super.dispose();
  }

  void _useExample(_ScenarioExample example) {
    _sourceText
      ..text = example.text
      ..selection = TextSelection.collapsed(offset: example.text.length);
    setState(() => _sourceOutdated = _draft != null);
  }

  void _markSourceChanged() {
    if (_draft != null && !_sourceOutdated) {
      setState(() => _sourceOutdated = true);
    }
  }

  Future<void> _generateDraft() async {
    final source = _sourceText.text.trim();
    if (source.isEmpty) {
      _showMessage('先貼上家裡發生的事，一行也可以。');
      return;
    }
    setState(() => _generating = true);
    try {
      final draft = await _draftGenerator.generate(
        sourceText: source,
        languageName: _languageName,
      );
      if (!mounted) return;
      _title.text = draft.title;
      _sceneLabel.text = draft.sceneLabel;
      _targetText.text = draft.targetText;
      _translation.text = draft.translationZh;
      _pronunciation.text = draft.pronunciationGuide;
      _prompt.text = draft.promptZh;
      _chunks.text = draft.chunks.join(' | ');
      setState(() {
        _draft = draft;
        _audioPath = null;
        _recordingGeneration += 1;
        _sourceOutdated = false;
        _familyConfirmedTarget = false;
        _generating = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _generating = false);
      _showMessage('草稿沒有產生，原文還在，請再試一次。');
    }
  }

  List<String> _parsedChunks(String target) {
    final chunks = _chunks.text
        .split(RegExp(r'[|\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(3)
        .toList(growable: false);
    final parsed = chunks.isNotEmpty
        ? chunks
        : LocalQuickChallengeDraftGenerator._splitIntoChunks(target);
    if (parsed.length > 1 && parsed.last.split(RegExp(r'\s+')).length == 1) {
      return [
        ...parsed.take(parsed.length - 2),
        '${parsed[parsed.length - 2]} ${parsed.last}',
      ];
    }
    return parsed;
  }

  String get _languageTag => switch (_languageName) {
        '越南語' => 'vi-VN',
        '臺灣台語' => 'nan-TW',
        '客語' => 'hak-TW',
        // An unknown family language must never be guessed as Mandarin.
        _ => 'und',
      };

  LessonContent _buildLessonContent({
    required QuickChallengeDraft draft,
    required String target,
    required String translation,
    required List<String> chunks,
  }) {
    final tokenCount = target
        .replaceAll(RegExp(r'[,.!?，。！？]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .length;
    return LessonContent(
      schemaVersion: 3,
      languageTag: _languageTag,
      romanizationSystem: _languageName == '臺灣台語' ? '臺羅' : 'family-reading',
      sentenceRomanization: _pronunciation.text.trim().isEmpty
          ? target
          : _pronunciation.text.trim(),
      coachIntroZh: '先聽家人的完整說法，再把短句分成 ${chunks.length} 塊慢慢接起來。',
      memoryTipZh: draft.memoryTipZh,
      targetDurationMs: (tokenCount * 600).clamp(1000, 5000).toInt(),
      segments: [
        for (var index = 0; index < chunks.length; index++)
          LessonSegment(
            id: 'family-chunk-$index',
            text: chunks[index],
            tokens: chunks[index]
                .split(RegExp(r'\s+'))
                .where((token) => token.isNotEmpty)
                .toList(growable: false),
            translationZh: chunks.length == 1 || index == chunks.length - 1
                ? translation
                : '先聽第 ${index + 1} 小段',
            romanization: chunks[index],
            pronunciationTipsZh: const [
              '先模仿家人的節奏；沒有家人錄音時，裝置會用系統語音示範。',
            ],
          ),
      ],
      patterns: const [],
    );
  }

  FamilyChallenge? _buildFamilyChallenge({
    required QuickChallengeDraft draft,
    required String target,
  }) {
    final base = draft.familyChallenge;
    if (base == null) return null;
    return FamilyChallenge(
      sceneTitleZh: base.sceneTitleZh,
      promptZh: base.promptZh,
      listeningPromptZh: '先聽「$target」，再選出剛才找到的線索。',
      dialoguePromptZh: '看著「${base.correctChoiceZh}」，幫角色說一次：「$target」',
      correctChoiceZh: base.correctChoiceZh,
      distractorsZh: base.distractorsZh,
      correctEmoji: base.correctEmoji,
      distractorEmojis: base.distractorEmojis,
      successMessageZh: base.successMessageZh,
      cultureNoteZh: base.cultureNoteZh,
      hotspots: base.hotspots,
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) {
      _showMessage('先按「幫我做成草稿」。');
      return;
    }
    if (_sourceOutdated) {
      _showMessage('生活情境改過了，請再產生一次草稿。');
      return;
    }
    final title = _title.text.trim();
    final scene = _sceneLabel.text.trim();
    final target = _targetText.text.trim();
    final translation = _translation.text.trim();
    final prompt = _prompt.text.trim();
    if ([title, scene, target, translation, prompt]
        .any((value) => value.isEmpty)) {
      _showMessage('還有空白欄位，請補上紅色提示的內容。');
      return;
    }
    if (draft.requiresTargetReview &&
        _normalizedReviewText(target) ==
            _normalizedReviewText(draft.targetText)) {
      _showMessage('這一欄目前還是中文提示，請先換成你們家真正會說的家語短句。');
      return;
    }
    if (!_familyConfirmedTarget) {
      _showMessage('請先勾選「我確認這是我們家會說的方式」。');
      return;
    }
    if (_languageTag == 'und' && _audioPath == null) {
      _showMessage('「其他家語」不會猜成中文發音；請先錄下家人的完整說法再儲存。');
      return;
    }
    setState(() => _saving = true);
    final chunks = _parsedChunks(target);
    final lessonContent = _buildLessonContent(
      draft: draft,
      target: target,
      translation: translation,
      chunks: chunks,
    );
    final familyChallenge = _buildFamilyChallenge(
      draft: draft,
      target: target,
    );
    try {
      final story = await widget.store.addStory(
        title: title,
        objectName: scene,
        vietnamese: target,
        chinese: translation,
        draft: TaskDraft(
          promptZh: prompt,
          promptVi: target,
          keyPhrases: chunks,
          confidence: draft.confidence,
          explanation: _audioPath == null
              ? '家人已預覽、微調並確認；聲音由裝置 TTS 示範。'
              : '家人已預覽、微調、確認並親自錄音的生活情境草稿。',
        ),
        humanConfirmed: true,
        audioPath: _audioPath,
        languageName: _languageName,
        languageTag: _languageTag,
        pronunciationGuide:
            _pronunciation.text.trim().isEmpty ? target : _pronunciation.text,
        pronunciationSystem: _languageName == '臺灣台語' ? '臺羅' : '家人讀音',
        practiceChunks: chunks,
        lessonContent: lessonContent,
        familyChallenge: familyChallenge,
        illustrationAsset: draft.illustrationAsset,
        originStoryIdeaId: widget.originStoryIdeaId,
        originStoryIdeaTitle: widget.originStoryIdeaTitle,
      );
      final relayId = widget.relayId;
      if (relayId != null) {
        try {
          await widget.store.completeAdultRelay(
            relayId: relayId,
            adultMemberId: widget.adultMemberId!,
            storyId: story.id,
          );
        } on Object {
          await widget.store.deleteStory(story.id);
          rethrow;
        }
      }
      if (!mounted) return;
      widget.onCreated(story);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('題目沒有存好，文字和錄音都還在，請再試一次。');
    }
  }

  String _normalizedReviewText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s，。！？、…,.!?；;：:「」『』（）()]+'), '');

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth > 820 ? 760.0 : constraints.maxWidth - 40;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Align(
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    if (widget.relayChildIntentZh case final intent?) ...[
                      const SizedBox(height: 14),
                      _ChildFirstBatonCard(
                        childIntentZh: intent,
                        seedTitle: widget.originStoryIdeaTitle ?? '今天的故事',
                      ),
                    ],
                    const SizedBox(height: 22),
                    const _StepHeader(
                      number: 1,
                      title: '把生活情況貼上來',
                      subtitle: '不用整理成表格，一行也可以。',
                    ),
                    const SizedBox(height: 12),
                    _buildSourceCard(context),
                    const SizedBox(height: 22),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: _draft == null
                          ? const _WaitingDraftCard()
                          : _buildDraftEditor(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ideaTitle = widget.originStoryIdeaTitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ideaTitle == null ? '一句話變成孩子任務' : '把「$ideaTitle」變成四關故事任務',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              const Text(
                '家人確認真正說法後，孩子會看情境、聽一句、排句子，再幫角色回話；錄音可選。',
                style: TextStyle(color: AppColors.muted, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const _NoScoreBadge(),
      ],
    );
  }

  Widget _buildSourceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _languageName,
            decoration: const InputDecoration(
              labelText: '想教哪一種家裡話？',
              prefixIcon: Icon(Icons.language_rounded),
            ),
            items: const [
              DropdownMenuItem(value: '越南語', child: Text('越南語')),
              DropdownMenuItem(value: '臺灣台語', child: Text('臺灣台語')),
              DropdownMenuItem(value: '客語', child: Text('客語')),
              DropdownMenuItem(value: '其他家語', child: Text('其他家語')),
            ],
            onChanged: (value) {
              setState(() {
                _languageName = value ?? '越南語';
                _sourceOutdated = _draft != null;
              });
            },
          ),
          if (_languageName == '其他家語') ...[
            const SizedBox(height: 8),
            const Text(
              '為了不把家語用中文音色硬念，「其他家語」需要家人錄音；之後可再補精確語言代碼。',
              style: TextStyle(color: AppColors.coral, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '不知道怎麼寫？點一個例子',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in _examples)
                ActionChip(
                  avatar: Icon(
                    example.icon,
                    size: 17,
                    color: AppColors.berry,
                  ),
                  label: Text(example.label),
                  onPressed: () => _useExample(example),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('quick-challenge-source'),
            controller: _sourceText,
            minLines: 3,
            maxLines: 5,
            maxLength: 360,
            onChanged: (_) => _markSourceChanged(),
            decoration: const InputDecoration(
              labelText: '家裡發生什麼事？想教哪一句？',
              hintText: '例如：\n放學回家，想教孩子說「我回來了」\n希望他一進門就能跟外婆說',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('generate-quick-challenge-draft'),
            onPressed: _generating ? null : _generateDraft,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: AppColors.berry,
            ),
            icon: Icon(
              _generating
                  ? Icons.hourglass_top_rounded
                  : Icons.auto_awesome_rounded,
            ),
            label: Text(_generating ? '正在整理…' : '產生本機故事草稿'),
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _draftGenerator.disclosure,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDraftEditor(BuildContext context) {
    final draft = _draft!;
    return Column(
      key: const ValueKey('quick-challenge-draft-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          number: 2,
          title: '家人看一眼、改一改',
          subtitle: '這不是答案，請改成你們家真的會說的方式。',
        ),
        const SizedBox(height: 12),
        if (_sourceOutdated) ...[
          _NoticeCard(
            icon: Icons.refresh_rounded,
            color: AppColors.coral,
            background: AppColors.coralSoft,
            text: '上面的生活情境改過了，請再按一次「產生本機故事草稿」。',
          ),
          const SizedBox(height: 10),
        ],
        _NoticeCard(
          icon: draft.requiresTargetReview
              ? Icons.family_restroom_rounded
              : Icons.fact_check_rounded,
          color: draft.requiresTargetReview ? AppColors.coral : AppColors.jade,
          background: draft.requiresTargetReview
              ? AppColors.coralSoft
              : AppColors.jadeSoft,
          text: draft.generatorNote,
        ),
        const SizedBox(height: 10),
        _NoticeCard(
          icon: Icons.lightbulb_rounded,
          color: AppColors.sun,
          background: AppColors.sunSoft,
          text: '生活中怎麼練：${draft.memoryTipZh}',
        ),
        const SizedBox(height: 12),
        if (draft.familyChallenge != null) ...[
          _FourStepMissionPreview(challenge: draft.familyChallenge!),
          const SizedBox(height: 18),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.asset(
                    draft.illustrationAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(
                      color: AppColors.cream,
                      child: Center(
                        child: Icon(
                          Icons.image_rounded,
                          color: AppColors.muted,
                          size: 52,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Row(
                children: [
                  Icon(Icons.collections_rounded,
                      size: 17, color: AppColors.muted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '依情境關鍵詞挑選固定圖庫示意圖，執行時不會建立新圖片。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEEE8FF), Color(0xFFE5F2FF)],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '孩子會先看到這張卡',
                style: TextStyle(
                    color: AppColors.berry, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('quick-challenge-target'),
                controller: _targetText,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                onChanged: (_) {
                  if (_familyConfirmedTarget || _audioPath != null) {
                    setState(() {
                      _familyConfirmedTarget = false;
                      _audioPath = null;
                      _recordingGeneration += 1;
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: '孩子要說（請用 $_languageName）',
                  helperText: '最重要：請改成家裡真正會說的短句。',
                ),
              ),
              const SizedBox(height: 11),
              TextField(
                controller: _translation,
                decoration: const InputDecoration(
                  labelText: '這句中文是什麼？',
                ),
              ),
              const SizedBox(height: 11),
              TextField(
                controller: _pronunciation,
                decoration: const InputDecoration(
                  labelText: '注音、台羅或分詞提示（可空白）',
                  hintText: '例如：Con · về · rồi',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _familyConfirmedTarget,
                onChanged: (value) => setState(
                  () => _familyConfirmedTarget = value ?? false,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '我確認這是我們家會說的方式',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('不確定時，可以先問家裡真的會說的人。'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('想再調整題目？'),
          subtitle: const Text('不改也可以'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '任務名稱'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sceneLabel,
              decoration: const InputDecoration(labelText: '生活場景'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prompt,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '給孩子的短提示'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _chunks,
              decoration: const InputDecoration(
                labelText: '句子積木',
                helperText: '用直線分開，例如：Con về | rồi',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _StepHeader(
          number: 3,
          title: '家人錄一次（可選）',
          subtitle: '沒錄也能建立，裝置會用系統 TTS 示範。',
        ),
        const SizedBox(height: 12),
        RecordingControl(
          key: ValueKey(_recordingGeneration),
          media: widget.media,
          prefix: 'family_natural_challenge',
          label: '想留下家人聲音再按這裡',
          maxSeconds: 12,
          onRecorded: (path) => setState(() => _audioPath = path),
        ),
        const SizedBox(height: 14),
        _NoticeCard(
          icon: _audioPath == null
              ? Icons.record_voice_over_rounded
              : Icons.family_restroom_rounded,
          color: _audioPath == null ? AppColors.sky : AppColors.jade,
          background:
              _audioPath == null ? AppColors.skySoft : AppColors.jadeSoft,
          text: _audioPath == null
              ? '目前會用裝置的 system TTS 自動發聲；不同手機的聲音可能不一樣。'
              : '已收到家人錄音，孩子會優先聽這段真人聲音。',
        ),
        const SizedBox(height: 10),
        const _NoticeCard(
          icon: Icons.extension_rounded,
          color: AppColors.berry,
          background: AppColors.berrySoft,
          text: '這份草稿會套用現有圖庫情境、短句與分段練習；建立前可先修改內容。',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('save-quick-challenge'),
          onPressed: _saving || _sourceOutdated ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            backgroundColor: AppColors.coral,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.rocket_launch_rounded),
          label: Text(
            _saving
                ? '正在建立…'
                : draft.familyChallenge == null
                    ? '建立孩子的生活任務'
                    : '建立並交給孩子闖四關',
          ),
        ),
      ],
    );
  }
}

class _ChildFirstBatonCard extends StatelessWidget {
  const _ChildFirstBatonCard({
    required this.childIntentZh,
    required this.seedTitle,
  });

  final String childIntentZh;
  final String seedTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('relay-child-first-baton'),
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.sunSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.sun),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.coral,
            child: Icon(Icons.looks_one_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '孩子帶回的第一棒｜$seedTitle',
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  childIntentZh,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '現在輪到家人傳下真正的家語；儲存後再把裝置交回孩子。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FourStepMissionPreview extends StatelessWidget {
  const _FourStepMissionPreview({required this.challenge});

  final FamilyChallenge challenge;

  @override
  Widget build(BuildContext context) {
    const steps = <({IconData icon, String title, String detail})>[
      (
        icon: Icons.image_search_rounded,
        title: '看見情境',
        detail: '先在生活圖裡找到線索',
      ),
      (
        icon: Icons.hearing_rounded,
        title: '聽完整句',
        detail: '由家人原音或裝置語音示範',
      ),
      (
        icon: Icons.view_week_rounded,
        title: '排回一句',
        detail: '把短句積木接回正確順序',
      ),
      (
        icon: Icons.forum_rounded,
        title: '幫角色回話',
        detail: '用家人確認的說法完成故事',
      ),
    ];
    return Container(
      key: const ValueKey('quick-challenge-four-step-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.jadeSoft, AppColors.skySoft],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: AppColors.jade),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '孩子收到的不是一張答案卡，是四關生活任務',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    steps[index].icon,
                    size: 19,
                    color: AppColors.berry,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${steps[index].title}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        steps[index].detail,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (index < steps.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '故事接力：${challenge.cultureNoteZh}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          child: Text('$number',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaitingDraftCard extends StatelessWidget {
  const _WaitingDraftCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('waiting-for-quick-draft'),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppColors.berry, size: 42),
          SizedBox(height: 8),
          Text('草稿會出現在這裡', style: TextStyle(fontWeight: FontWeight.w900)),
          SizedBox(height: 3),
          Text('可以預覽、改句子，再錄家人的聲音。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
        ],
      ),
    );
  }
}

class _NoScoreBadge extends StatelessWidget {
  const _NoScoreBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.berrySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.favorite_rounded, color: AppColors.berry, size: 21),
          Text('家人確認',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _ScenarioExample {
  const _ScenarioExample({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;
}

enum _SceneKind { morning, homecoming, mealtime, garden, bedtime }

class _ScenePreset {
  const _ScenePreset({
    required this.assetPath,
    required this.sceneTitleZh,
    required this.promptZh,
    required this.correctChoiceZh,
    required this.distractorsZh,
    required this.correctEmoji,
    required this.distractorEmojis,
    required this.successMessageZh,
    required this.hotspots,
  });

  final String assetPath;
  final String sceneTitleZh;
  final String promptZh;
  final String correctChoiceZh;
  final List<String> distractorsZh;
  final String correctEmoji;
  final List<String> distractorEmojis;
  final String successMessageZh;
  final List<ChallengeHotspot> hotspots;

  static const morning = _ScenePreset(
    assetPath: 'assets/images/family-morning-game-v1.webp',
    sceneTitleZh: '早晨的家',
    promptZh: '在圖裡找到要說話的外婆。',
    correctChoiceZh: '外婆',
    distractorsZh: ['鬧鐘', '拖鞋'],
    correctEmoji: '👵',
    distractorEmojis: ['⏰', '🥿'],
    successMessageZh: '找到外婆了！',
    hotspots: [
      ChallengeHotspot(
        labelZh: '外婆',
        left: .62,
        top: .10,
        width: .23,
        height: .61,
        hintZh: '看看右邊正在拉窗簾的家人。',
      ),
      ChallengeHotspot(
        labelZh: '鬧鐘',
        left: .86,
        top: .04,
        width: .12,
        height: .22,
        hintZh: '這是牆上的鬧鐘。',
      ),
      ChallengeHotspot(
        labelZh: '拖鞋',
        left: .02,
        top: .82,
        width: .19,
        height: .13,
        hintZh: '這是床邊的拖鞋。',
      ),
    ],
  );

  static const homecoming = _ScenePreset(
    assetPath: 'assets/images/family-homecoming-theater-v2.png',
    sceneTitleZh: '回到家的時刻',
    promptZh: '找出剛剛回到家的孩子。',
    correctChoiceZh: '回家的孩子',
    distractorsZh: ['爸爸', '外婆'],
    correctEmoji: '🎒',
    distractorEmojis: ['👨', '👵'],
    successMessageZh: '找到回家的孩子了！',
    hotspots: [
      ChallengeHotspot(
        labelZh: '回家的孩子',
        left: .13,
        top: .25,
        width: .33,
        height: .61,
        hintZh: '找找背著綠色書包、正在揮手的人。',
      ),
      ChallengeHotspot(
        labelZh: '爸爸',
        left: .42,
        top: .24,
        width: .39,
        height: .72,
        hintZh: '這是蹲下迎接孩子的爸爸。',
      ),
      ChallengeHotspot(
        labelZh: '外婆',
        left: .75,
        top: .10,
        width: .22,
        height: .82,
        hintZh: '這是右邊迎接孩子的外婆。',
      ),
    ],
  );

  static const mealtime = _ScenePreset(
    assetPath: 'assets/images/family-mealtime-theater-v2.png',
    sceneTitleZh: '全家的餐桌',
    promptZh: '在餐桌旁找到要一起說話的外婆。',
    correctChoiceZh: '外婆',
    distractorsZh: ['白飯', '筷子'],
    correctEmoji: '👵',
    distractorEmojis: ['🍚', '🥢'],
    successMessageZh: '找到餐桌旁的外婆了！',
    hotspots: [
      ChallengeHotspot(
        labelZh: '外婆',
        left: .79,
        top: .23,
        width: .21,
        height: .57,
        hintZh: '看看餐桌最右邊的長輩。',
      ),
      ChallengeHotspot(
        labelZh: '白飯',
        left: .39,
        top: .56,
        width: .26,
        height: .25,
        hintZh: '這是桌子中央的飯鍋。',
      ),
      ChallengeHotspot(
        labelZh: '筷子',
        left: .17,
        top: .78,
        width: .25,
        height: .19,
        hintZh: '這是桌子左下方的筷子。',
      ),
    ],
  );

  static const garden = _ScenePreset(
    assetPath: 'assets/images/family-garden-theater-v1.png',
    sceneTitleZh: '陽台的小花園',
    promptZh: '在陽台找到孩子手上的澆水壺。',
    correctChoiceZh: '澆水壺',
    distractorsZh: ['外婆', '小花'],
    correctEmoji: '🫗',
    distractorEmojis: ['👵', '🌼'],
    successMessageZh: '找到澆水壺，可以一起照顧植物了！',
    hotspots: [
      ChallengeHotspot(
        labelZh: '澆水壺',
        left: .26,
        top: .43,
        width: .25,
        height: .30,
        hintZh: '看看孩子兩手中間的綠色澆水壺。',
      ),
      ChallengeHotspot(
        labelZh: '外婆',
        left: .51,
        top: .12,
        width: .36,
        height: .74,
        hintZh: '這是正指著新葉子的外婆。',
      ),
      ChallengeHotspot(
        labelZh: '小花',
        left: .02,
        top: .50,
        width: .22,
        height: .32,
        hintZh: '這是陽台左邊盛開的小花。',
      ),
    ],
  );

  static const bedtime = _ScenePreset(
    assetPath: 'assets/images/family-bedtime-theater-v1.png',
    sceneTitleZh: '睡前故事時間',
    promptZh: '在床上找到外婆正在讀的故事書。',
    correctChoiceZh: '故事書',
    distractorsZh: ['小熊', '床頭燈'],
    correctEmoji: '📖',
    distractorEmojis: ['🧸', '💡'],
    successMessageZh: '故事書打開了，可以把晚安送給家人！',
    hotspots: [
      ChallengeHotspot(
        labelZh: '故事書',
        left: .40,
        top: .45,
        width: .39,
        height: .34,
        hintZh: '看看孩子和外婆中間打開的大書。',
      ),
      ChallengeHotspot(
        labelZh: '小熊',
        left: .04,
        top: .53,
        width: .22,
        height: .28,
        hintZh: '這是床邊陪著聽故事的小熊。',
      ),
      ChallengeHotspot(
        labelZh: '床頭燈',
        left: .82,
        top: .31,
        width: .17,
        height: .29,
        hintZh: '這是照亮故事書的床頭燈。',
      ),
    ],
  );

  static _ScenePreset forKind(_SceneKind kind) => switch (kind) {
        _SceneKind.morning => morning,
        _SceneKind.homecoming => homecoming,
        _SceneKind.mealtime => mealtime,
        _SceneKind.garden => garden,
        _SceneKind.bedtime => bedtime,
      };

  FamilyChallenge buildChallenge({
    required String targetText,
    required String translationZh,
    String? cultureNoteZh,
  }) {
    return FamilyChallenge(
      sceneTitleZh: sceneTitleZh,
      promptZh: promptZh,
      listeningPromptZh: '聽到「$targetText」時，選出剛才找到的線索。',
      dialoguePromptZh: '看著「$correctChoiceZh」，說一次：「$targetText」',
      correctChoiceZh: correctChoiceZh,
      distractorsZh: distractorsZh,
      correctEmoji: correctEmoji,
      distractorEmojis: distractorEmojis,
      successMessageZh: successMessageZh,
      cultureNoteZh: cultureNoteZh ?? '「$translationZh」要以家人確認的真正說法為準；圖是生活情境示意。',
      hotspots: hotspots,
    );
  }
}

class _LocalScenarioTemplate {
  const _LocalScenarioTemplate({
    required this.keywords,
    required this.title,
    required this.sceneLabel,
    required this.sceneKind,
    required this.translationZh,
    required this.vietnamese,
    required this.chunks,
    required this.memoryTip,
  });

  final List<String> keywords;
  final String title;
  final String sceneLabel;
  final _SceneKind sceneKind;
  final String translationZh;
  final String vietnamese;
  final List<String> chunks;
  final String memoryTip;
}

class _StorySeedTemplate {
  const _StorySeedTemplate({
    required this.keywords,
    required this.missionTitle,
    required this.sceneLabel,
    required this.sceneKind,
    required this.memoryTip,
    required this.familyReply,
  });

  final List<String> keywords;
  final String missionTitle;
  final String sceneLabel;
  final _SceneKind sceneKind;
  final String memoryTip;
  final String familyReply;
}
