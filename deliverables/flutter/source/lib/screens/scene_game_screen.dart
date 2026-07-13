import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../models/family_story.dart';
import '../models/lesson_content.dart';
import '../services/local_media_service.dart';

enum SceneGameMode {
  fullJourney,
  pictureMatch,
  listeningOrder,
  familyChallenge,
}

class SceneGameScreen extends StatefulWidget {
  const SceneGameScreen({
    required this.story,
    required this.media,
    required this.lessonContent,
    this.mode = SceneGameMode.fullJourney,
    this.onCompleted,
    super.key,
  });

  final FamilyStory story;
  final LocalMediaService media;
  final LessonContent lessonContent;
  final SceneGameMode mode;
  final ValueChanged<int>? onCompleted;

  @override
  State<SceneGameScreen> createState() => _SceneGameScreenState();
}

class _SceneGameScreenState extends State<SceneGameScreen> {
  late int _stage;
  int _stars = 0;
  int _findMisses = 0;
  bool _stageDone = false;
  bool _playing = false;
  bool _heardChoiceAudio = false;
  bool _feedbackGood = false;
  String? _feedback;

  late final List<_TokenPiece> _targetTokens;
  late final List<_TokenPiece> _wordBank;
  final List<_TokenPiece> _answerTokens = [];

  int get _firstStage => switch (widget.mode) {
        SceneGameMode.fullJourney || SceneGameMode.pictureMatch => 0,
        SceneGameMode.listeningOrder => 1,
        SceneGameMode.familyChallenge => 3,
      };

  int get _lastStage => switch (widget.mode) {
        SceneGameMode.fullJourney => 3,
        SceneGameMode.pictureMatch => 0,
        SceneGameMode.listeningOrder => 2,
        SceneGameMode.familyChallenge => 3,
      };

  int get _stageCount => _lastStage - _firstStage + 1;
  int get _stagePosition => _stage - _firstStage;
  bool get _isLastStage => _stage >= _lastStage;
  String get _stepLabel => '第 ${_stagePosition + 1} 關';

  @override
  void initState() {
    super.initState();
    _stage = _firstStage;
    final words = _sentenceTokens();
    _targetTokens = [
      for (var index = 0; index < words.length; index++)
        _TokenPiece(id: index, text: words[index]),
    ];
    _wordBank = _targetTokens.reversed.toList(growable: true);
  }

  @override
  void dispose() {
    widget.media.stopPlayback();
    super.dispose();
  }

  String get _speaker => widget.story.isSample ? '外婆' : '家人';

  FamilyChallenge get _challenge =>
      widget.story.familyChallenge ??
      FamilyChallenge(
        promptZh: '先看看圖，再找出「${widget.story.chinese}」。',
        correctChoiceZh: widget.story.objectName,
        distractorsZh: const ['另一個答案'],
        successMessageZh: '你找到這句話的線索了！',
        cultureNoteZh: '下次在家裡遇到相同情境，再說一次。',
      );

  String get _targetLabel => _challenge.correctChoiceZh;
  String get _wrongLabel => _challenge.distractorsZh.isEmpty
      ? '另一個答案'
      : _challenge.distractorsZh.first;
  String get _targetEmoji => _challenge.correctEmoji;
  String get _wrongEmoji => _challenge.emojiForChoice(_wrongLabel);
  List<ChallengeHotspot> get _hotspots => _challenge.hotspots;
  bool get _hasHotspots => _hotspots.isNotEmpty;
  ChallengeHotspot? get _correctHotspot {
    for (final spot in _hotspots) {
      if (spot.labelZh == _targetLabel) return spot;
    }
    return null;
  }

  String get _locationHint => _correctHotspot?.hintZh ?? '先看完整張圖，再選最像的答案';

  List<String> _sentenceTokens() {
    final tokens = widget.lessonContent.segments
        .expand((segment) => segment.tokens)
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    return tokens.isNotEmpty
        ? tokens
        : _fallbackTokens(widget.story.vietnamese);
  }

  List<String> _fallbackTokens(String sentence) {
    final cleaned = sentence.replaceAll(RegExp(r'[,.!?，。！？]'), ' ').trim();
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    return tokens.isEmpty ? <String>[sentence] : tokens;
  }

  Future<void> _playAudio(
    LessonAudio? audio, {
    double speed = 1,
    bool useStoryFallback = true,
    String? fallbackText,
  }) async {
    if (_playing) return;
    final path =
        audio?.path ?? (useStoryFallback ? widget.story.audioPath : null);
    if ((path == null || path.isEmpty) &&
        (fallbackText == null || fallbackText.trim().isEmpty)) {
      _showMessage('這段聲音還沒準備好');
      return;
    }
    setState(() => _playing = true);
    try {
      if (path != null && path.isNotEmpty) {
        await widget.media.playLocal(
          path,
          speed: speed,
          start: audio?.startMs == null
              ? null
              : Duration(milliseconds: audio!.startMs!),
          end: audio?.endMs == null
              ? null
              : Duration(milliseconds: audio!.endMs!),
        );
      } else {
        await widget.media.speakText(
          fallbackText!,
          languageTag: widget.lessonContent.languageTag,
          rate: (LocalMediaService.normalSpeechRate * speed)
              .clamp(LocalMediaService.slowSpeechRate, .60)
              .toDouble(),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _playWholeSentence({double speed = 1}) => _playAudio(
        LessonAudio(path: widget.story.audioPath),
        useStoryFallback: true,
        fallbackText: widget.story.vietnamese,
        speed: speed,
      );

  Future<void> _playListeningPrompt() async {
    // The card, prompt and answer choices all describe the complete sentence.
    // Playing a segment here made some lessons say only a final particle such
    // as "ạ" even though the child was looking at "Ngon quá ạ!".
    await _playWholeSentence(speed: .88);
    if (mounted) setState(() => _heardChoiceAudio = true);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _tryAgain(String message) {
    HapticFeedback.selectionClick();
    setState(() {
      _feedback = message;
      _feedbackGood = false;
    });
  }

  void _award(String message) {
    if (_stageDone) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _stageDone = true;
      _stars += 1;
      _feedback = '$message  +1 顆星';
      _feedbackGood = true;
    });
  }

  Future<void> _nextStage() async {
    await widget.media.stopPlayback();
    if (!mounted) return;
    setState(() {
      _stage = _isLastStage ? 4 : _stage + 1;
      _stageDone = false;
      _feedback = null;
      _feedbackGood = false;
    });
  }

  void _tapHotspot(ChallengeHotspot? spot) {
    if (_stageDone) return;
    if (spot?.labelZh == _targetLabel) {
      _award(
        _challenge.successMessageZh,
      );
      return;
    }
    _findMisses += 1;
    final message = spot == null
        ? '還沒找到，$_locationHint'
        : '這是${spot.labelZh}，$_locationHint';
    _tryAgain(message);
  }

  void _choosePictureAnswer(bool correct) {
    if (correct) {
      _award(_challenge.successMessageZh);
    } else {
      _findMisses += 1;
      _tryAgain('這是$_wrongLabel；再看看圖和中文提示');
    }
  }

  void _chooseListeningAnswer(bool correct) {
    if (_stageDone) return;
    if (!_heardChoiceAudio) {
      _tryAgain('先點大耳朵聽一遍');
      return;
    }
    if (correct) {
      _award('耳朵真厲害！');
    } else {
      _tryAgain('這是$_wrongLabel，再看一次意思、聽一次');
    }
  }

  void _addToken(_TokenPiece piece) {
    if (_stageDone || !_wordBank.any((item) => item.id == piece.id)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _wordBank.removeWhere((item) => item.id == piece.id);
      _answerTokens.add(piece);
      _feedback = null;
    });
    if (_answerTokens.length == _targetTokens.length) _checkTokenOrder();
  }

  void _removeToken(_TokenPiece piece) {
    if (_stageDone) return;
    HapticFeedback.selectionClick();
    setState(() {
      _answerTokens.removeWhere((item) => item.id == piece.id);
      _wordBank.add(piece);
      _feedback = null;
    });
  }

  void _clearTokens() {
    if (_stageDone || _answerTokens.isEmpty) return;
    setState(() {
      _wordBank
        ..clear()
        ..addAll(_targetTokens.reversed);
      _answerTokens.clear();
      _feedback = null;
    });
  }

  void _checkTokenOrder() {
    final correct = _answerTokens.length == _targetTokens.length &&
        List.generate(
          _targetTokens.length,
          (index) => _answerTokens[index].id == _targetTokens[index].id,
        ).every((value) => value);
    if (correct) {
      _award('句子排好了！');
    } else {
      _tryAgain('差一點！點上面的詞拿回去');
    }
  }

  Future<void> _chooseDialogueAnswer(bool correct) async {
    if (_stageDone) return;
    if (!correct) {
      _tryAgain('再看一次中文：「${widget.story.chinese}」');
      return;
    }
    _award('你選到這個情境要練的句子了！');
    await _playWholeSentence();
  }

  void _finish() {
    widget.onCompleted?.call(_stars);
    Navigator.of(context).pop<int>(_stars);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(_challenge.sceneTitleZh),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StarPill(stars: _stars, total: _stageCount),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (_stage <= _lastStage)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: _StageRail(
                      current: _stagePosition,
                      stars: _stars,
                      count: _stageCount,
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('${widget.mode.name}-$_stage'),
                      child: switch (_stage) {
                        0 => _buildFindStage(context),
                        1 => _buildListenStage(context),
                        2 => _buildArrangeStage(context),
                        3 => _buildDialogueStage(context),
                        _ => _buildCompletion(context),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFindStage(BuildContext context) {
    return _StageScroll(
      child: Column(
        children: [
          _StageTitle(
            icon: Icons.search_rounded,
            step: _stepLabel,
            title: _hasHotspots ? '在場景裡找線索' : '先看圖，再選答案',
            hint: _challenge.promptZh,
            color: AppColors.coral,
            background: AppColors.coralSoft,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        widget.story.illustrationAsset ??
                            'assets/images/family-kitchen-game-v2.webp',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                          color: AppColors.sunSoft,
                          child: Center(
                            child: Icon(
                              Icons.kitchen_rounded,
                              size: 72,
                              color: AppColors.coral,
                            ),
                          ),
                        ),
                      ),
                      if (_hasHotspots)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _tapHotspot(null),
                          ),
                        ),
                      for (final spot in _hotspots)
                        _Hotspot(
                          left: width * spot.left,
                          top: height * spot.top,
                          width: width * spot.width,
                          height: height * spot.height,
                          semanticLabel: spot.labelZh,
                          showHint: spot.labelZh == _targetLabel &&
                              (_findMisses >= 2 || _stageDone),
                          completed: spot.labelZh == _targetLabel && _stageDone,
                          onTap: () => _tapHotspot(spot),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (!_hasHotspots) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PictureAnswer(
                    emoji: _wrongEmoji,
                    label: _wrongLabel,
                    color: AppColors.sun,
                    selectedWrong: _feedback != null && !_feedbackGood,
                    onTap: () => _choosePictureAnswer(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PictureAnswer(
                    emoji: _targetEmoji,
                    label: _targetLabel,
                    color: AppColors.coral,
                    selectedGood: _stageDone,
                    onTap: () => _choosePictureAnswer(true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _stageFeedback(),
          if (_stageDone) ...[
            _LearnPhraseCard(
              story: widget.story,
              lessonContent: widget.lessonContent,
              emoji: _targetEmoji,
              playing: _playing,
              onPlay: _playWholeSentence,
            ),
            const SizedBox(height: 12),
          ],
          _nextButton(),
        ],
      ),
    );
  }

  Widget _buildListenStage(BuildContext context) {
    return _StageScroll(
      child: Column(
        children: [
          _StageTitle(
            icon: Icons.hearing_rounded,
            step: _stepLabel,
            title: '先看懂，再用耳朵找',
            hint: _challenge.listeningPromptZh ?? '聽到這句時，選哪張圖？',
            color: AppColors.sky,
            background: AppColors.skySoft,
          ),
          const SizedBox(height: 14),
          _LearnPhraseCard(
            story: widget.story,
            lessonContent: widget.lessonContent,
            emoji: _targetEmoji,
            playing: _playing,
            onPlay: _playWholeSentence,
            compact: true,
          ),
          const SizedBox(height: 18),
          _BigListenButton(
            playing: _playing,
            label: _heardChoiceAudio ? '再聽一次' : '點一下聽',
            onPressed: _playListeningPrompt,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _PictureAnswer(
                  emoji: _wrongEmoji,
                  label: _wrongLabel,
                  color: AppColors.sun,
                  selectedWrong: _feedback != null && !_feedbackGood,
                  onTap: () => _chooseListeningAnswer(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PictureAnswer(
                  emoji: _targetEmoji,
                  label: _targetLabel,
                  color: AppColors.coral,
                  selectedGood: _stageDone,
                  onTap: () => _chooseListeningAnswer(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _stageFeedback(),
          _nextButton(),
        ],
      ),
    );
  }

  Widget _buildArrangeStage(BuildContext context) {
    return _StageScroll(
      child: Column(
        children: [
          _StageTitle(
            icon: Icons.view_week_rounded,
            step: _stepLabel,
            title: '排好句子',
            hint: '拖上去，或點一下',
            color: AppColors.berry,
            background: AppColors.berrySoft,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _playing ? null : _playWholeSentence,
            icon: Icon(
              _playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
            ),
            label: Text(_playing ? '播放中…' : '再聽整句'),
          ),
          const SizedBox(height: 14),
          DragTarget<_TokenPiece>(
            onAcceptWithDetails: (details) => _addToken(details.data),
            builder: (context, candidates, rejected) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 104),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    candidates.isNotEmpty ? AppColors.jadeSoft : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color:
                      candidates.isNotEmpty ? AppColors.jade : AppColors.border,
                  width: candidates.isNotEmpty ? 2 : 1,
                ),
              ),
              child: _answerTokens.isEmpty
                  ? const Center(
                      child: Text(
                        '把詞放這裡',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final piece in _answerTokens)
                          _PlacedToken(
                            piece: piece,
                            locked: _stageDone,
                            onTap: () => _removeToken(piece),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final piece in _wordBank)
                _DraggableToken(
                  key: ValueKey(piece.id),
                  piece: piece,
                  onTap: () => _addToken(piece),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_answerTokens.isNotEmpty && !_stageDone)
            TextButton.icon(
              onPressed: _clearTokens,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新排'),
            ),
          _stageFeedback(),
          _nextButton(),
        ],
      ),
    );
  }

  Widget _buildDialogueStage(BuildContext context) {
    return _StageScroll(
      child: Column(
        children: [
          _StageTitle(
            icon: Icons.forum_rounded,
            step: _stepLabel,
            title: '幫角色回答',
            hint: _challenge.dialoguePromptZh ?? '這個情境裡，你會怎麼說？',
            color: AppColors.jade,
            background: AppColors.jadeSoft,
          ),
          const SizedBox(height: 18),
          _GrandmaBubble(
            speaker: _speaker,
            prompt: _challenge.dialoguePromptZh ?? '你會怎麼說？',
          ),
          const SizedBox(height: 16),
          _DialogueAnswer(
            emoji: _wrongEmoji,
            target: _wrongLabel,
            translation: '不是這次情境要說的話',
            color: AppColors.sun,
            wrong: _feedback != null && !_feedbackGood,
            onTap: () => _chooseDialogueAnswer(false),
          ),
          const SizedBox(height: 11),
          _DialogueAnswer(
            emoji: _targetEmoji,
            target: widget.story.vietnamese,
            translation: widget.story.chinese,
            color: AppColors.coral,
            correct: _stageDone,
            onTap: () => _chooseDialogueAnswer(true),
          ),
          const SizedBox(height: 14),
          _stageFeedback(),
          _nextButton(label: '看我的星星'),
        ],
      ),
    );
  }

  Widget _buildCompletion(BuildContext context) {
    return _StageScroll(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.sunSoft, Colors.white],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const _CelebrationBadge(),
            const SizedBox(height: 20),
            Text(
              '你完成了！',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.mode == SceneGameMode.fullJourney
                  ? '不等家人，星星現在就拿到；接著跟著說一句。'
                  : '不等家人，這次玩法的星星現在就拿到。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _stageCount,
                (index) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star_rounded,
                    color: AppColors.sun,
                    size: 40,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.berrySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.favorite_rounded, color: AppColors.berry),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '家人之後回覆，是額外的愛心加成。',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.story.familyChallenge != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.jadeSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_rounded, color: AppColors.jade),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '把家裡的故事接下去',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(widget.story.familyChallenge!.cultureNoteZh),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('finish-scene-game'),
              onPressed: _finish,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: AppColors.jade,
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                widget.mode == SceneGameMode.fullJourney ? '收下星星，跟著說' : '收下星星',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageFeedback() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _feedback == null
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(_feedback),
              padding: const EdgeInsets.only(bottom: 12),
              child: _FeedbackBanner(
                message: _feedback!,
                good: _feedbackGood,
              ),
            ),
    );
  }

  Widget _nextButton({String? label}) {
    final buttonLabel = label ?? (_isLastStage ? '看我的星星' : '下一關');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !_stageDone
          ? const SizedBox.shrink()
          : FilledButton.icon(
              key: ValueKey('next-$_stage'),
              onPressed: _nextStage,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: AppColors.jade,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(buttonLabel),
            ),
    );
  }
}

class _StageScroll extends StatelessWidget {
  const _StageScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
      child: child,
    );
  }
}

class _StageTitle extends StatelessWidget {
  const _StageTitle({
    required this.icon,
    required this.step,
    required this.title,
    required this.hint,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String step;
  final String title;
  final String hint;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              Text(
                hint,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageRail extends StatelessWidget {
  const _StageRail({
    required this.current,
    required this.stars,
    required this.count,
  });

  final int current;
  final int stars;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          count == 1 ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 4,
                color: index <= current ? AppColors.sun : AppColors.border,
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: index == current ? 39 : 33,
            height: index == current ? 39 : 33,
            decoration: BoxDecoration(
              color: index < stars
                  ? AppColors.sun
                  : index == current
                      ? AppColors.sunSoft
                      : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: index <= current ? AppColors.sun : AppColors.border,
                width: 2,
              ),
            ),
            child: Icon(
              index < stars ? Icons.star_rounded : Icons.circle,
              color: index < stars ? Colors.white : AppColors.muted,
              size: index < stars ? 22 : 8,
            ),
          ),
        ],
      ],
    );
  }
}

class _StarPill extends StatelessWidget {
  const _StarPill({required this.stars, required this.total});

  final int stars;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.sunSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.sun, size: 20),
          const SizedBox(width: 3),
          Text(
            '$stars/$total',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.semanticLabel,
    required this.onTap,
    this.showHint = false,
    this.completed = false,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool showHint;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            decoration: BoxDecoration(
              color: showHint
                  ? (completed ? AppColors.jade : AppColors.sun)
                      .withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: showHint
                  ? Border.all(
                      color: completed ? AppColors.jade : AppColors.sun,
                      width: 4,
                    )
                  : null,
            ),
            alignment: Alignment.topRight,
            child: completed
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.jade,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.check_rounded, size: 21),
                    ),
                  )
                : showHint
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(
                          Icons.touch_app_rounded,
                          color: AppColors.sun,
                          size: 31,
                        ),
                      )
                    : null,
          ),
        ),
      ),
    );
  }
}

class _LearnPhraseCard extends StatelessWidget {
  const _LearnPhraseCard({
    required this.story,
    required this.lessonContent,
    required this.emoji,
    required this.playing,
    required this.onPlay,
    this.compact = false,
  });

  final FamilyStory story;
  final LessonContent lessonContent;
  final String emoji;
  final bool playing;
  final VoidCallback onPlay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reading = story.effectivePronunciation ?? story.vietnamese;
    return Semantics(
      container: true,
      label: '先看懂這一句 ${story.vietnamese} ${story.chinese} $reading',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF3CF), Colors.white],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFFD96D)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: compact ? 25 : 29,
              backgroundColor: AppColors.sunSoft,
              child: Icon(
                _sceneGameIconForEmoji(emoji),
                size: compact ? 27 : 31,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '先看意思，不用盲猜',
                    style: TextStyle(
                      color: AppColors.coral,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    story.vietnamese,
                    style: TextStyle(
                      fontSize: compact ? 20 : 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    reading,
                    style: const TextStyle(
                      color: AppColors.berry,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    story.chinese,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    Text(
                      lessonContent.coachIntroZh ?? '先看中文，再點小段慢慢跟著說。',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: playing ? '播放中' : '聽這一句',
              onPressed: playing ? null : onPlay,
              icon: Icon(
                playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigListenButton extends StatelessWidget {
  const _BigListenButton({
    required this.playing,
    required this.label,
    required this.onPressed,
  });

  final bool playing;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? '播放中' : label,
      child: InkWell(
        onTap: playing ? null : onPressed,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 126,
          height: 126,
          decoration: BoxDecoration(
            color: playing ? AppColors.berry : AppColors.sky,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x334C9BE8),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 48,
              ),
              Text(
                playing ? '播放中' : label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PictureAnswer extends StatelessWidget {
  const _PictureAnswer({
    required this.label,
    required this.color,
    required this.onTap,
    this.emoji,
    this.selectedGood = false,
    this.selectedWrong = false,
  });

  final String? emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selectedGood;
  final bool selectedWrong;

  @override
  Widget build(BuildContext context) {
    final borderColor = selectedGood
        ? AppColors.jade
        : selectedWrong
            ? AppColors.coral
            : AppColors.border;
    return Semantics(
      button: true,
      label: label,
      selected: selectedGood,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: borderColor, width: 3),
            ),
            child: Column(
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _sceneGameIconForEmoji(emoji),
                    size: 42,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableToken extends StatelessWidget {
  const _DraggableToken({
    required this.piece,
    required this.onTap,
    super.key,
  });

  final _TokenPiece piece;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = _TokenTile(text: piece.text, onTap: onTap);
    return Draggable<_TokenPiece>(
      data: piece,
      feedback: Material(
        color: Colors.transparent,
        child: _TokenTile(text: piece.text),
      ),
      childWhenDragging: Opacity(opacity: .28, child: tile),
      child: tile,
    );
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.berrySoft,
      borderRadius: BorderRadius.circular(17),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minWidth: 66, minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.berry,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlacedToken extends StatelessWidget {
  const _PlacedToken({
    required this.piece,
    required this.locked,
    required this.onTap,
  });

  final _TokenPiece piece;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: locked ? AppColors.jadeSoft : AppColors.skySoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                piece.text,
                style: TextStyle(
                  color: locked ? AppColors.jade : AppColors.sky,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!locked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GrandmaBubble extends StatelessWidget {
  const _GrandmaBubble({required this.speaker, required this.prompt});

  final String speaker;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.sunSoft,
          foregroundColor: AppColors.coral,
          child: Icon(Icons.face_3_rounded, size: 37),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker,
                  style: const TextStyle(
                      color: AppColors.coral, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  prompt,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogueAnswer extends StatelessWidget {
  const _DialogueAnswer({
    required this.target,
    required this.translation,
    required this.color,
    required this.onTap,
    this.emoji,
    this.correct = false,
    this.wrong = false,
  });

  final String? emoji;
  final String target;
  final String translation;
  final Color color;
  final VoidCallback onTap;
  final bool correct;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: correct
                  ? AppColors.jade
                  : wrong
                      ? AppColors.coral
                      : AppColors.border,
              width: correct || wrong ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .17),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _sceneGameIconForEmoji(emoji),
                  size: 31,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      translation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.touch_app_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _sceneGameIconForEmoji(String? emoji) {
  final glyph = emoji ?? '';
  if (glyph.contains('🎒')) return Icons.backpack_rounded;
  if (glyph.contains('🏠') || glyph.contains('🚪')) {
    return Icons.home_rounded;
  }
  if (glyph.contains('👵') || glyph.contains('👩')) {
    return Icons.face_3_rounded;
  }
  if (glyph.contains('👨') || glyph.contains('🧑')) {
    return Icons.face_6_rounded;
  }
  if (glyph.contains('👧') || glyph.contains('🧒')) {
    return Icons.child_care_rounded;
  }
  if (glyph.contains('🍚') || glyph.contains('🥣') || glyph.contains('🍲')) {
    return Icons.rice_bowl_rounded;
  }
  if (glyph.contains('🥢')) return Icons.restaurant_rounded;
  if (glyph.contains('🥤') || glyph.contains('🫗')) {
    return Icons.local_drink_rounded;
  }
  if (glyph.contains('⏰')) return Icons.alarm_rounded;
  if (glyph.contains('🥿')) return Icons.directions_walk_rounded;
  if (glyph.contains('📖')) return Icons.menu_book_rounded;
  if (glyph.contains('🧸')) return Icons.toys_rounded;
  if (glyph.contains('💡')) return Icons.lightbulb_rounded;
  if (glyph.contains('🫙')) return Icons.kitchen_rounded;
  if (glyph.contains('🥬') || glyph.contains('🌱') || glyph.contains('🌿')) {
    return Icons.eco_rounded;
  }
  if (glyph.contains('🌼')) return Icons.local_florist_rounded;
  if (glyph.contains('🌙')) return Icons.bedtime_rounded;
  if (glyph.contains('☀')) return Icons.wb_sunny_rounded;
  if (glyph.contains('🙋')) return Icons.record_voice_over_rounded;
  if (glyph.contains('🫂') || glyph.contains('🤝')) {
    return Icons.diversity_1_rounded;
  }
  if (glyph.contains('😄') || glyph.contains('😋')) {
    return Icons.sentiment_very_satisfied_rounded;
  }
  return Icons.auto_awesome_rounded;
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.good});

  final String message;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: good ? AppColors.jadeSoft : AppColors.coralSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.star_rounded : Icons.waving_hand_rounded,
            color: good ? AppColors.jade : AppColors.coral,
            size: 27,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _CelebrationBadge extends StatelessWidget {
  const _CelebrationBadge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 142,
          height: 142,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.coral, AppColors.sun],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33E96B52),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            Icons.emoji_events_rounded,
            color: Colors.white,
            size: 72,
          ),
        ),
        const Positioned(
          left: -22,
          top: 8,
          child: Icon(Icons.star_rounded, color: AppColors.sky, size: 29),
        ),
        const Positioned(
          right: -18,
          top: 22,
          child: Icon(Icons.star_rounded, color: AppColors.berry, size: 25),
        ),
      ],
    );
  }
}

class _TokenPiece {
  const _TokenPiece({required this.id, required this.text});

  final int id;
  final String text;
}
