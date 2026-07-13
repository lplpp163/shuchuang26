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
  ConversationChoice? _choice;
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
    super.dispose();
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
    setState(() => _choice = choice);
    unawaited(_play(choice.line));
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    return Scaffold(
      appBar: AppBar(title: const BrandMark(compact: true)),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const _PreviewPill(
                        icon: Icons.visibility_outlined,
                        label: '30 秒試演',
                      ),
                      const SizedBox(width: 8),
                      const _PreviewPill(
                        icon: Icons.no_accounts_outlined,
                        label: '不錄音・不儲存',
                      ),
                      const Spacer(),
                      Text(
                        choice == null ? '1 / 2' : '2 / 2',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
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
                  else
                    _OutcomePreview(
                      key: ValueKey('preview-outcome-${choice.id}'),
                      choice: choice,
                      playing: _playing,
                      onListen: () => unawaited(_play(choice.elderReply)),
                      onTryOther: () => setState(() => _choice = null),
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
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: AppColors.jadeSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, color: AppColors.jade),
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
                  FilledButton.icon(
                    key: const ValueKey('finish-theater-preview'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.family_restroom_rounded),
                    label: Text(choice == null ? '回到同意說明' : '建立我們家的故事'),
                  ),
                ],
              ),
            ),
          ),
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
