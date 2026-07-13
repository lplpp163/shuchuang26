import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../services/local_media_service.dart';
import '../widgets/brand_mark.dart';

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

  Future<void> _play(ConversationLine line) async {
    if (_playing) return;
    setState(() {
      _playing = true;
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
    } on Object {
      if (mounted) setState(() => _message = '這台裝置暫時播不出聲音；文字與故事分支仍可繼續。');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  void _choose(ConversationChoice choice) {
    if (_playing) return;
    setState(() {
      _choice = choice;
      _showRelay = false;
    });
    _scrollToActStart();
    unawaited(_play(choice.line));
  }

  void _openRelayPreview() {
    if (_playing || _choice == null) return;
    setState(() => _showRelay = true);
    _scrollToActStart();
  }

  void _returnToOutcome() {
    if (_playing) return;
    setState(() => _showRelay = false);
    _scrollToActStart();
  }

  void _returnToOpening() {
    if (_playing) return;
    setState(() {
      _choice = null;
      _showRelay = false;
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
            childCompletionZh: '正式使用時，完成看、聽、排、答後，可用錄音或文字留下這一棒。',
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const _PreviewPill(
                        icon: Icons.visibility_outlined,
                        label: '約 30 秒試演',
                      ),
                      const _PreviewPill(
                        icon: Icons.no_accounts_outlined,
                        label: '不錄音・不儲存',
                      ),
                      const _PreviewPill(
                        icon: Icons.science_outlined,
                        label: '固定合成・零家庭資料',
                      ),
                      _PreviewPill(
                        icon: Icons.theater_comedy_outlined,
                        label: '$step / 3',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (choice == null)
                    _OpeningPreview(
                      key: const ValueKey('preview-opening'),
                      episode: _episode,
                      prompt: _prompt,
                      playing: _playing,
                      onListen: () => unawaited(_play(_prompt.elderLine)),
                      onChoose: _choose,
                    )
                  else if (!_showRelay)
                    _OutcomePreview(
                      key: ValueKey('preview-outcome-${choice.id}'),
                      choice: choice,
                      playing: _playing,
                      onListen: () => unawaited(_play(choice.elderReply)),
                      onTryOther: _returnToOpening,
                    )
                  else
                    _RelayPreview(
                      key: const ValueKey('preview-relay'),
                      data: relay!,
                      playing: _playing,
                      onListen: () => unawaited(_play(relay.familyLine)),
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
                      onPressed: _playing ? null : _returnToOutcome,
                      icon: const Icon(Icons.alt_route_rounded),
                      label: const Text('再看一次舞台怎麼變'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const ValueKey('finish-theater-preview'),
                      onPressed: _playing ? null : () => Navigator.pop(context),
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
    required this.childCompletionZh,
  });

  final String childIntentZh;
  final ConversationLine familyLine;
  final String childCompletionZh;
}

class _RelayPreview extends StatelessWidget {
  const _RelayPreview({
    super.key,
    required this.data,
    required this.playing,
    required this.onListen,
  });

  final RelayPreviewData data;
  final bool playing;
  final VoidCallback onListen;

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
          ),
          const _PreviewRelayConnector(),
          _PreviewRelayBaton(
            key: const ValueKey('preview-relay-baton-3'),
            number: 3,
            icon: Icons.record_voice_over_rounded,
            color: AppColors.jade,
            label: '孩子接住',
            primary: data.familyLine.targetText,
            detail: data.childCompletionZh,
          ),
          const SizedBox(height: 13),
          FilledButton.icon(
            key: const ValueKey('preview-relay-listen'),
            onPressed: playing ? null : onListen,
            style: FilledButton.styleFrom(backgroundColor: AppColors.berry),
            icon: Icon(
              playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
            ),
            label: Text(playing ? '正在播放…' : '聽合成的家語示範'),
          ),
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
  });

  final int number;
  final IconData icon;
  final Color color;
  final String label;
  final String primary;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .72), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color,
            foregroundColor: Colors.white,
            child: Text(
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
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  primary,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
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

class _OpeningPreview extends StatelessWidget {
  const _OpeningPreview({
    super.key,
    required this.episode,
    required this.prompt,
    required this.playing,
    required this.onListen,
    required this.onChoose,
  });

  final ConversationEpisode episode;
  final ConversationPrompt prompt;
  final bool playing;
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
          playing: playing,
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
            onTap: playing ? null : () => onChoose(choice),
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
    required this.playing,
    required this.onListen,
    required this.onTryOther,
  });

  final ConversationChoice choice;
  final bool playing;
  final VoidCallback onListen;
  final VoidCallback onTryOther;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewOutcomeStage(
          choice: choice,
          playing: playing,
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
          onPressed: playing ? null : onTryOther,
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
    required this.playing,
    required this.onListen,
  });

  final ConversationChoice choice;
  final bool playing;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final accent = choice.sceneAfter.id == 'home-cushion'
        ? AppColors.berry
        : AppColors.jade;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final responsiveHeight = 440.0 + ((textScale - 1).clamp(0.0, 1.0) * 180.0);
    return Container(
      key: ValueKey('preview-outcome-stage-${choice.sceneAfter.id}'),
      height: responsiveHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, .10)!,
            Color.lerp(accent, AppColors.ink, .48)!,
          ],
        ),
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
          Positioned(
            left: -38,
            top: -64,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .11),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: 22,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: AppColors.sun.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(40),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 38,
            bottom: 150,
            child: Semantics(
              label: '孩子的選擇改變了祖孫故事舞台',
              image: true,
              child: Image.asset(
                'assets/images/family-stage-duo-v1.png',
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
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
          Align(
            alignment: const Alignment(0, -.48),
            child: Container(
              key: ValueKey('preview-outcome-icon-${choice.id}'),
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.sun,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white, width: 4),
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
                size: 42,
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
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('preview-listen-line'),
                    onPressed: playing ? null : onListen,
                    icon: Icon(
                      playing
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(playing ? '正在播放…' : '聽外婆接下一句'),
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
    required this.playing,
    required this.onListen,
  });

  final ConversationEpisode episode;
  final String headline;
  final String targetText;
  final String translation;
  final bool playing;
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
                    onPressed: playing ? null : onListen,
                    icon: Icon(
                      playing
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(playing ? '正在播放…' : '點一下聽這一句'),
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
