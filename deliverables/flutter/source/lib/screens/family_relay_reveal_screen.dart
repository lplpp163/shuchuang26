import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/family_relay.dart';
import '../models/family_story.dart';
import '../models/learning_attempt.dart';
import '../services/local_media_service.dart';

class FamilyRelayRevealView extends StatefulWidget {
  const FamilyRelayRevealView({
    required this.relay,
    required this.story,
    required this.attempt,
    required this.media,
    required this.onDone,
    super.key,
  });

  final FamilyRelay relay;
  final FamilyStory story;
  final LearningAttempt attempt;
  final LocalMediaService media;
  final VoidCallback onDone;

  @override
  State<FamilyRelayRevealView> createState() => _FamilyRelayRevealViewState();
}

class _FamilyRelayRevealViewState extends State<FamilyRelayRevealView> {
  bool _playing = false;
  int _activeBaton = 0;

  @override
  void dispose() {
    widget.media.stopPlayback();
    super.dispose();
  }

  Future<void> _playFamilyBaton() async {
    final path = widget.story.audioPath;
    if (path != null) {
      await widget.media.playLocal(path);
      return;
    }
    await widget.media.speakText(
      widget.story.targetText,
      languageTag: widget.story.effectiveLanguageTag,
      rate: LocalMediaService.normalSpeechRate,
    );
  }

  Future<void> _playChildBaton() async {
    final path = widget.attempt.audioPath;
    if (path == null) return;
    await widget.media.playLocal(path);
  }

  Future<void> _playTogether() async {
    if (_playing) return;
    setState(() {
      _playing = true;
      _activeBaton = 2;
    });
    try {
      await _playFamilyBaton();
      if (!mounted) return;
      if (widget.attempt.audioPath != null) {
        setState(() => _activeBaton = 3);
        await _playChildBaton();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _playing = false;
          _activeBaton = 0;
        });
      }
    }
  }

  Future<void> _stop() async {
    await widget.media.stopPlayback();
    if (mounted) {
      setState(() {
        _playing = false;
        _activeBaton = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('family-relay-reveal'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.sunSoft, AppColors.paper],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 28),
              children: [
                const Icon(
                  Icons.hub_rounded,
                  color: AppColors.coral,
                  size: 54,
                ),
                const SizedBox(height: 10),
                Text(
                  '三棒接成一個家的故事',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '「${widget.relay.seedTitle}」已完成；不是分數，是兩代共同留下的作品。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
                const SizedBox(height: 20),
                _RelayBatonCard(
                  number: 1,
                  active: _activeBaton == 1,
                  color: AppColors.coral,
                  icon: Icons.child_care_rounded,
                  label: '孩子帶回',
                  primary: widget.relay.childIntentZh,
                  secondary: '孩子先決定今天真正想說的事。',
                ),
                const _RelayConnector(),
                _RelayBatonCard(
                  number: 2,
                  active: _activeBaton == 2,
                  color: AppColors.berry,
                  icon: Icons.family_restroom_rounded,
                  label: '家人傳下',
                  primary: widget.story.targetText,
                  secondary: widget.story.audioPath == null
                      ? '${widget.story.translationZh}｜裝置語音示範'
                      : '${widget.story.translationZh}｜家人原音',
                ),
                const _RelayConnector(),
                _RelayBatonCard(
                  number: 3,
                  active: _activeBaton == 3,
                  color: AppColors.jade,
                  icon: Icons.record_voice_over_rounded,
                  label: '孩子接住',
                  primary: widget.story.targetText,
                  secondary: widget.attempt.audioPath == null
                      ? '以文字完成這一棒'
                      : '已留下孩子自己的錄音',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('play-family-relay'),
                  onPressed: _playing ? _stop : _playTogether,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    backgroundColor:
                        _playing ? AppColors.coral : AppColors.berry,
                  ),
                  icon: Icon(
                    _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    _playing ? '停止播放' : '一起播放我們的接力',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '依序播放家人示範與孩子錄音，不混音、不上傳；沒有孩子錄音時只播放家人這一棒。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const ValueKey('finish-family-relay'),
                  onPressed: widget.onDone,
                  icon: const Icon(Icons.favorite_rounded),
                  label: const Text('收進家人圈'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RelayBatonCard extends StatelessWidget {
  const _RelayBatonCard({
    required this.number,
    required this.active,
    required this.color,
    required this.icon,
    required this.label,
    required this.primary,
    required this.secondary,
  });

  final int number;
  final bool active;
  final Color color;
  final IconData icon;
  final String label;
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: .13) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color, width: active ? 3 : 1.5),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color,
            foregroundColor: Colors.white,
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 19),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  primary,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  secondary,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayConnector extends StatelessWidget {
  const _RelayConnector();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 30,
        child: Center(
          child: Icon(Icons.arrow_downward_rounded, color: AppColors.muted),
        ),
      );
}
