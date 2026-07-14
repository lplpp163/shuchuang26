import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../services/local_media_service.dart';
import '../widgets/brand_mark.dart';

enum _PreviewVoice {
  openingElder,
  childChoice,
  elderReply,
  relayFamily,
}

/// A read-only first impression of the product's core interaction.
///
/// It deliberately has no store, recorder, speech recognizer, family identity,
/// or completion callback. Leaving this screen discards the selected branch.
class TheaterPreviewScreen extends StatefulWidget {
  const TheaterPreviewScreen({required this.media, super.key});

  final LocalMediaService media;

  @override
  State<TheaterPreviewScreen> createState() => _TheaterPreviewScreenState();
}

class _TheaterPreviewScreenState extends State<TheaterPreviewScreen> {
  late final ConversationEpisode _episode;
  late final ConversationPrompt _prompt;
  final ScrollController _scrollController = ScrollController();
  ConversationChoice? _choice;
  bool _showRelay = false;
  bool _playing = false;
  bool _relaySequenceRunning = false;
  int _relayStep = 0;
  _PreviewVoice? _playingVoice;
  final Set<_PreviewVoice> _heardVoices = <_PreviewVoice>{};
  PreviewStorySeed? _selectedStorySeed;
  String? _message;

  @override
  void initState() {
    super.initState();
    _episode = ConversationEpisodeCatalog.homecoming;
    _prompt = _episode.promptById(_episode.openingPromptId);
  }

  @override
  void dispose() {
    unawaited(widget.media.stopPlayback());
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _play(
    ConversationLine line, {
    required _PreviewVoice voice,
  }) async {
    if (_playing) return;
    setState(() {
      _playing = true;
      _playingVoice = voice;
      _message = null;
    });
    try {
      final path = line.audioPath;
      if (path != null) {
        await widget.media.playLocal(path);
      } else {
        await widget.media.speakText(
          line.targetText,
          languageTag: _episode.languageTag,
        );
      }
      if (mounted) setState(() => _heardVoices.add(voice));
    } on Object {
      if (mounted) setState(() => _message = '這台裝置暫時播不出聲音；文字與故事分支仍可繼續。');
    } finally {
      if (mounted) {
        setState(() {
          _playing = false;
          _playingVoice = null;
        });
      }
    }
  }

  void _choose(ConversationChoice choice) {
    if (_playing) return;
    setState(() {
      _choice = choice;
      _showRelay = false;
      _relayStep = 0;
      _selectedStorySeed = null;
    });
    _scrollToActStart();
    unawaited(_play(choice.line, voice: _PreviewVoice.childChoice));
  }

  void _openRelayPreview() {
    if (_playing || _relaySequenceRunning || _choice == null) return;
    setState(() {
      _showRelay = true;
      _relayStep = 0;
      _selectedStorySeed = null;
    });
    _scrollToActStart();
  }

  Future<void> _playRelaySequence(RelayPreviewData relay) async {
    if (_playing || _relaySequenceRunning) return;
    setState(() {
      _relaySequenceRunning = true;
      _relayStep = 1;
      _message = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _relayStep = 2);
    await _play(relay.familyLine, voice: _PreviewVoice.relayFamily);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _relayStep = 3;
      _relaySequenceRunning = false;
    });
  }

  void _returnToOutcome() {
    if (_playing || _relaySequenceRunning) return;
    setState(() {
      _showRelay = false;
      _relayStep = 0;
      _selectedStorySeed = null;
    });
    _scrollToActStart();
  }

  void _returnToOpening() {
    if (_playing || _relaySequenceRunning) return;
    setState(() {
      _choice = null;
      _showRelay = false;
      _relayStep = 0;
      _selectedStorySeed = null;
    });
    _scrollToActStart();
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    final step = choice == null
        ? 1
        : _showRelay
            ? 3
            : 2;
    final relay = choice == null
        ? null
        : RelayPreviewData(
            childIntentZh: choice.line.translationZh,
            familyLine: choice.line,
            childResultZh: choice.sceneAfter.headlineZh,
            childCompletionZh: '正式使用時，完成看、聽、排、答後，孩子會把家語變成故事裡真正發生的結果。',
          );
    return Scaffold(
      appBar: AppBar(title: const BrandMark(compact: true)),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PreviewPill(
                        icon: Icons.visibility_outlined,
                        label: '約 30 秒試演',
                      ),
                      _PreviewPill(
                        icon: Icons.mic_off_outlined,
                        label: '這次不錄音',
                      ),
                      _PreviewPill(
                        icon: Icons.folder_off_outlined,
                        label: '不存家庭資料',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PreviewActProgress(step: step),
                  const SizedBox(height: 14),
                  if (choice == null)
                    _OpeningPreview(
                      key: const ValueKey('preview-opening'),
                      episode: _episode,
                      prompt: _prompt,
                      playingVoice: _playingVoice,
                      heard: _heardVoices.contains(_PreviewVoice.openingElder),
                      onListen: () => unawaited(
                        _play(
                          _prompt.elderLine,
                          voice: _PreviewVoice.openingElder,
                        ),
                      ),
                      onChoose: _choose,
                    )
                  else if (!_showRelay)
                    _OutcomePreview(
                      key: ValueKey('preview-outcome-${choice.id}'),
                      choice: choice,
                      playingVoice: _playingVoice,
                      heardChildLine:
                          _heardVoices.contains(_PreviewVoice.childChoice),
                      heardElderReply:
                          _heardVoices.contains(_PreviewVoice.elderReply),
                      onListen: () => unawaited(
                        _play(
                          choice.elderReply,
                          voice: _PreviewVoice.elderReply,
                        ),
                      ),
                      onTryOther: _returnToOpening,
                    )
                  else
                    _RelayPreview(
                      key: const ValueKey('preview-relay'),
                      data: relay!,
                      activeStep: _relayStep,
                      sequenceRunning: _relaySequenceRunning,
                      heardFamilyLine:
                          _heardVoices.contains(_PreviewVoice.relayFamily),
                      selectedStorySeed: _selectedStorySeed,
                      onSelectStorySeed: (seed) =>
                          setState(() => _selectedStorySeed = seed),
                      onPlaySequence: () =>
                          unawaited(_playRelaySequence(relay)),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (!_showRelay)
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: AppColors.jadeSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              color: AppColors.jade),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '剛才只是在記憶體裡試一個分支。要錄下家人原音、使用麥克風或保存故事卡時，才會先取得同意。',
                              style: TextStyle(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (choice == null)
                    TextButton.icon(
                      key: const ValueKey('finish-theater-preview'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('回到同意說明'),
                    )
                  else if (!_showRelay)
                    FilledButton.icon(
                      key: const ValueKey('preview-to-relay'),
                      onPressed: _playing ? null : _openRelayPreview,
                      icon: const Icon(Icons.hub_rounded),
                      label: const Text('看這句怎麼傳回家'),
                    )
                  else ...[
                    OutlinedButton.icon(
                      key: const ValueKey('preview-replay-outcome'),
                      onPressed: _playing || _relaySequenceRunning
                          ? null
                          : _returnToOutcome,
                      icon: const Icon(Icons.alt_route_rounded),
                      label: const Text('再看一次舞台怎麼變'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const ValueKey('finish-theater-preview'),
                      onPressed: _playing || _relaySequenceRunning
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.family_restroom_rounded),
                      label: const Text('同意後建立我們家的三棒故事'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Immutable, bundled copy used only by the zero-data first-run preview.
///
/// It cannot create a family, relay, attempt, recording, or story card. The
/// real product flow constructs those records only after explicit consent.
@immutable
class RelayPreviewData {
  const RelayPreviewData({
    required this.childIntentZh,
    required this.familyLine,
    required this.childResultZh,
    required this.childCompletionZh,
  });

  final String childIntentZh;
  final ConversationLine familyLine;
  final String childResultZh;
  final String childCompletionZh;
}

@immutable
class PreviewStorySeed {
  const PreviewStorySeed({
    required this.id,
    required this.label,
    required this.intentZh,
    required this.icon,
  });

  final String id;
  final String label;
  final String intentZh;
  final IconData icon;
}

const _previewStorySeeds = <PreviewStorySeed>[
  PreviewStorySeed(
    id: 'family-sharing',
    label: '和家人分享',
    intentZh: '我今天最想告訴你一件事。',
    icon: Icons.forum_rounded,
  ),
  PreviewStorySeed(
    id: 'club',
    label: '社團',
    intentZh: '我今天第一次參加社團。',
    icon: Icons.groups_rounded,
  ),
  PreviewStorySeed(
    id: 'lunch',
    label: '午餐',
    intentZh: '今天午餐有一道菜我很喜歡。',
    icon: Icons.lunch_dining_rounded,
  ),
  PreviewStorySeed(
    id: 'class',
    label: '上課',
    intentZh: '今天上課有一件事我學會了。',
    icon: Icons.school_rounded,
  ),
  PreviewStorySeed(
    id: 'friendship',
    label: '朋友關係',
    intentZh: '我想和朋友把事情說開，再一起重來。',
    icon: Icons.diversity_1_rounded,
  ),
];

class _RelayPreview extends StatelessWidget {
  const _RelayPreview({
    super.key,
    required this.data,
    required this.activeStep,
    required this.sequenceRunning,
    required this.heardFamilyLine,
    required this.selectedStorySeed,
    required this.onSelectStorySeed,
    required this.onPlaySequence,
  });

  final RelayPreviewData data;
  final int activeStep;
  final bool sequenceRunning;
  final bool heardFamilyLine;
  final PreviewStorySeed? selectedStorySeed;
  final ValueChanged<PreviewStorySeed> onSelectStorySeed;
  final VoidCallback onPlaySequence;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.hub_rounded, color: AppColors.coral, size: 44),
          const SizedBox(height: 6),
          Text(
            '原來，一句話會這樣傳下來',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            '這是固定操作示範；正式使用時，內容由孩子與家人一起完成。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          _PreviewRelayBaton(
            key: const ValueKey('preview-relay-baton-1'),
            number: 1,
            icon: Icons.child_care_rounded,
            color: AppColors.coral,
            label: '孩子帶回',
            primary: data.childIntentZh,
            detail: '孩子先決定今天真正想說的事。',
            active: activeStep == 1,
            completed: activeStep > 1,
          ),
          const _PreviewRelayConnector(),
          _PreviewRelayBaton(
            key: const ValueKey('preview-relay-baton-2'),
            number: 2,
            icon: Icons.family_restroom_rounded,
            color: AppColors.berry,
            label: '家人傳下',
            primary: data.familyLine.targetText,
            detail: '正式使用時，由家人確認真正說法或錄下原音。',
            active: activeStep == 2,
            completed: activeStep > 2,
          ),
          const _PreviewRelayConnector(),
          _PreviewRelayBaton(
            key: const ValueKey('preview-relay-baton-3'),
            number: 3,
            icon: Icons.record_voice_over_rounded,
            color: AppColors.jade,
            label: '孩子接住',
            primary: data.childResultZh,
            detail: data.childCompletionZh,
            active: activeStep == 3,
            completed: activeStep == 3,
          ),
          const SizedBox(height: 13),
          FilledButton.icon(
            key: const ValueKey('preview-relay-listen'),
            onPressed: sequenceRunning ? null : onPlaySequence,
            style: FilledButton.styleFrom(backgroundColor: AppColors.berry),
            icon: Icon(
              sequenceRunning
                  ? Icons.graphic_eq_rounded
                  : activeStep == 3
                      ? Icons.replay_rounded
                      : Icons.play_arrow_rounded,
            ),
            label: Text(
              sequenceRunning
                  ? '正在傳第 $activeStep 棒…'
                  : activeStep == 3
                      ? '重播三棒接力'
                      : '播放三棒接力',
            ),
          ),
          if (heardFamilyLine && activeStep == 3) ...[
            const SizedBox(height: 7),
            const Text(
              '三棒接力完成 ✓',
              key: ValueKey('preview-relay-complete'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.jade,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('preview-relay-disclosure'),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.coralSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.coral.withValues(alpha: .35)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 20, color: AppColors.coral),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Piper 合成操作示範，不是真人原音，也不代表母語審閱完成；未使用、建立或保存任何家庭資料。',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PreviewStorySeedPicker(
            selected: selectedStorySeed,
            onSelected: onSelectStorySeed,
          ),
        ],
      ),
    );
  }
}

class _PreviewRelayBaton extends StatelessWidget {
  const _PreviewRelayBaton({
    super.key,
    required this.number,
    required this.icon,
    required this.color,
    required this.label,
    required this.primary,
    required this.detail,
    required this.active,
    required this.completed,
  });

  final int number;
  final IconData icon;
  final Color color;
  final String label;
  final String primary;
  final String detail;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '$label：$primary${active ? '，正在接力' : completed ? '，已完成' : '，等待接力'}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(
              alpha: active
                  ? .18
                  : completed
                      ? .11
                      : .05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(
                alpha: active
                    ? 1
                    : completed
                        ? .72
                        : .35),
            width: active ? 2.5 : 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: .22),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor:
                  active || completed ? color : color.withValues(alpha: .45),
              foregroundColor: Colors.white,
              child: completed && !active
                  ? const Icon(Icons.check_rounded, size: 19)
                  : Text(
                      '$number',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 6),
                        const Text(
                          '接力中',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    primary,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStorySeedPicker extends StatelessWidget {
  const _PreviewStorySeedPicker({
    required this.selected,
    required this.onSelected,
  });

  final PreviewStorySeed? selected;
  final ValueChanged<PreviewStorySeed> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('preview-life-seeds'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.backpack_rounded, color: AppColors.berry),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今天還能把什麼帶回家？',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '先選中文心意；同意後才交給家人確認家語，系統不會自己猜翻譯。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final seed in _previewStorySeeds)
                ChoiceChip(
                  key: ValueKey('preview-life-seed-${seed.id}'),
                  selected: selected?.id == seed.id,
                  onSelected: (_) => onSelected(seed),
                  avatar: Icon(seed.icon, size: 17),
                  label: Text(seed.label),
                ),
            ],
          ),
          if (selected case final seed?) ...[
            const SizedBox(height: 11),
            Container(
              key: const ValueKey('preview-life-seed-message'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '孩子想說｜${seed.intentZh}\n',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const TextSpan(
                      text: '這裡只試選題，不建立故事；真正家語由家人同意後確認。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewRelayConnector extends StatelessWidget {
  const _PreviewRelayConnector();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 20,
        child: Center(
          child: Icon(
            Icons.arrow_downward_rounded,
            size: 18,
            color: AppColors.muted,
          ),
        ),
      );
}

class _PreviewActProgress extends StatelessWidget {
  const _PreviewActProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = <String>['選一句', '看故事變', '傳回家'];
    return Semantics(
      key: ValueKey('preview-act-progress-step-$step'),
      container: true,
      label: '第 $step 幕，共三幕：${labels[step - 1]}',
      child: Container(
        key: const ValueKey('preview-act-progress'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          alignment: WrapAlignment.center,
          children: [
            for (var index = 0; index < labels.length; index += 1)
              AnimatedContainer(
                key: ValueKey('preview-act-${index + 1}'),
                duration: const Duration(milliseconds: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: step == index + 1
                      ? AppColors.jade
                      : step > index + 1
                          ? AppColors.jadeSoft
                          : AppColors.cream,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color:
                        step >= index + 1 ? AppColors.jade : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (step > index + 1)
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.jade,
                      )
                    else
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: step == index + 1
                              ? Colors.white
                              : AppColors.muted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      labels[index],
                      style: TextStyle(
                        color: step == index + 1 ? Colors.white : AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpeningPreview extends StatelessWidget {
  const _OpeningPreview({
    super.key,
    required this.episode,
    required this.prompt,
    required this.playingVoice,
    required this.heard,
    required this.onListen,
    required this.onChoose,
  });

  final ConversationEpisode episode;
  final ConversationPrompt prompt;
  final _PreviewVoice? playingVoice;
  final bool heard;
  final VoidCallback onListen;
  final ValueChanged<ConversationChoice> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewStage(
          episode: episode,
          headline: '外婆先說',
          targetText: prompt.elderLine.targetText,
          translation: prompt.elderLine.translationZh,
          playingVoice: playingVoice,
          voice: _PreviewVoice.openingElder,
          heard: heard,
          onListen: onListen,
        ),
        const SizedBox(height: 16),
        Text('你想怎麼接故事？', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 5),
        const Text(
          '先選中文意思；下一秒就會看見這句話改變舞台。',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        for (final choice in prompt.choices.take(2)) ...[
          _PreviewChoiceCard(
            choice: choice,
            onTap: playingVoice != null ? null : () => onChoose(choice),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _OutcomePreview extends StatelessWidget {
  const _OutcomePreview({
    super.key,
    required this.choice,
    required this.playingVoice,
    required this.heardChildLine,
    required this.heardElderReply,
    required this.onListen,
    required this.onTryOther,
  });

  final ConversationChoice choice;
  final _PreviewVoice? playingVoice;
  final bool heardChildLine;
  final bool heardElderReply;
  final VoidCallback onListen;
  final VoidCallback onTryOther;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewOutcomeStage(
          choice: choice,
          playingVoice: playingVoice,
          heardChildLine: heardChildLine,
          heardElderReply: heardElderReply,
          onListen: onListen,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.sunSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.record_voice_over_rounded, color: AppColors.coral),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正式故事裡，家人可以把這句換成你們家真正會說的版本或原音；每個家的腔調都可以不同。',
                  style: TextStyle(height: 1.45, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('preview-try-other'),
          onPressed: playingVoice != null ? null : onTryOther,
          icon: const Icon(Icons.alt_route_rounded),
          label: const Text('換另一句，看看不同結果'),
        ),
      ],
    );
  }
}

class _PreviewOutcomeStage extends StatelessWidget {
  const _PreviewOutcomeStage({
    required this.choice,
    required this.playingVoice,
    required this.heardChildLine,
    required this.heardElderReply,
    required this.onListen,
  });

  final ConversationChoice choice;
  final _PreviewVoice? playingVoice;
  final bool heardChildLine;
  final bool heardElderReply;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final responsiveHeight = 440.0 + ((textScale - 1).clamp(0.0, 1.0) * 180.0);
    return Container(
      key: ValueKey('preview-outcome-stage-${choice.sceneAfter.id}'),
      height: responsiveHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: AppColors.ink,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A253331),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            label: _previewOutcomeSemanticLabel(choice),
            image: true,
            child: Image.asset(
              _previewOutcomeAsset(choice),
              key: ValueKey(
                'preview-outcome-image-${choice.sceneAfter.id}',
              ),
              fit: BoxFit.cover,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x16000000), Color(0xD9253331)],
                stops: [.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: AppColors.coral, size: 18),
                  SizedBox(width: 6),
                  Text(
                    '你的話讓故事變了',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: Container(
              key: ValueKey('preview-outcome-icon-${choice.id}'),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.sun,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _previewSceneIcon(choice),
                color: AppColors.ink,
                size: 31,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .96),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    choice.sceneAfter.headlineZh,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    choice.storyBeatZh,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    choice.elderReply.targetText,
                    style: const TextStyle(
                      color: AppColors.jade,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(choice.elderReply.translationZh),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _outcomePlaybackStatus(
                        playingVoice: playingVoice,
                        heardChildLine: heardChildLine,
                        heardElderReply: heardElderReply,
                      ),
                      key: ValueKey(
                        'preview-playback-status-${playingVoice?.name ?? 'idle'}-$heardChildLine-$heardElderReply',
                      ),
                      style: const TextStyle(
                        color: AppColors.berry,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('preview-listen-line'),
                    onPressed: playingVoice != null ? null : onListen,
                    icon: Icon(
                      playingVoice != null
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(
                      playingVoice == _PreviewVoice.childChoice
                          ? '正在播放：你選的話'
                          : playingVoice == _PreviewVoice.elderReply
                              ? '外婆正在說…'
                              : heardElderReply
                                  ? '再聽一次外婆接話'
                                  : '聽外婆接下一句',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStage extends StatelessWidget {
  const _PreviewStage({
    required this.episode,
    required this.headline,
    required this.targetText,
    required this.translation,
    required this.playingVoice,
    required this.voice,
    required this.heard,
    required this.onListen,
  });

  final ConversationEpisode episode;
  final String headline;
  final String targetText;
  final String translation;
  final _PreviewVoice? playingVoice;
  final _PreviewVoice voice;
  final bool heard;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final responsiveHeight = 360.0 + ((textScale - 1).clamp(0.0, 1.0) * 140.0);
    return Container(
      height: responsiveHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.berrySoft,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A253331),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (episode.illustrationAsset case final asset?)
            Image.asset(asset, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x12000000), Color(0xD8253331)],
                stops: [.28, 1],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      color: AppColors.jade,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    targetText,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(translation,
                      style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('preview-listen-line'),
                    onPressed: playingVoice != null ? null : onListen,
                    icon: Icon(
                      playingVoice == voice
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(
                      playingVoice == voice
                          ? '外婆正在說…'
                          : heard
                              ? '再聽一次外婆開場'
                              : '點一下聽外婆開場',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewChoiceCard extends StatelessWidget {
  const _PreviewChoiceCard({required this.choice, required this.onTap});

  final ConversationChoice choice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: ValueKey('preview-choice-${choice.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                key: ValueKey('preview-choice-icon-${choice.id}'),
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.coralSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _previewChoiceIcon(choice),
                  color: AppColors.coral,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.line.translationZh,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('點下去看故事怎麼變',
                        style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.jade),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.sunSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.ink),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

IconData _previewChoiceIcon(ConversationChoice choice) => switch (choice.id) {
      'came-home' => Icons.waving_hand_rounded,
      'a-bit-tired' => Icons.bedtime_rounded,
      _ => Icons.forum_rounded,
    };

IconData _previewSceneIcon(ConversationChoice choice) =>
    switch (choice.sceneAfter.id) {
      'home-door-open' => Icons.door_front_door_rounded,
      'home-cushion' => Icons.chair_rounded,
      _ => Icons.auto_awesome_rounded,
    };

String _previewOutcomeAsset(ConversationChoice choice) =>
    switch (choice.sceneAfter.id) {
      'home-door-open' => 'assets/images/family-homecoming-theater-v2.png',
      'home-cushion' => 'assets/images/family-bedtime-theater-v1.png',
      _ => 'assets/images/family-stage-duo-v1.png',
    };

String _previewOutcomeSemanticLabel(ConversationChoice choice) =>
    switch (choice.sceneAfter.id) {
      'home-door-open' => '孩子說回來了，外婆在打開的家門前迎接他',
      'home-cushion' => '孩子說有一點累，外婆陪他在柔軟的休息場景坐下來',
      _ => '孩子的選擇改變了祖孫故事舞台',
    };

String _outcomePlaybackStatus({
  required _PreviewVoice? playingVoice,
  required bool heardChildLine,
  required bool heardElderReply,
}) {
  if (playingVoice == _PreviewVoice.childChoice) return '正在播放：你選的話';
  if (playingVoice == _PreviewVoice.elderReply) return '外婆正在接下一句';
  if (heardElderReply) return '你選的話與外婆回話都已聽過 ✓';
  if (heardChildLine) return '已聽過：你選的話 ✓，接著可以聽外婆回話';
  return '先聽你選的話，再聽外婆怎麼接';
}
