import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../models/family_circle.dart';
import '../services/family_circle_store.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.familyCircle,
    required this.onOpenEpisode,
    super.key,
  });

  final FamilyCircleStore familyCircle;
  final Future<void> Function(ConversationEpisode episode) onOpenEpisode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: familyCircle,
      builder: (context, _) {
        final storyteller = familyCircle.members.firstWhere(
          (member) => member.isApproved && member.isAdult,
        );
        final episodes = ConversationEpisodeCatalog.defaults
            .map(
              (episode) => episode.withElderDisplayName(storyteller.nickname),
            )
            .toList(growable: false);
        final today = episodes[familyCircle.cards.length % episodes.length];
        final latestCard =
            familyCircle.cards.isEmpty ? null : familyCircle.cards.first;

        return ListView(
          key: const ValueKey('theater-home'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
          children: [
            _WelcomeLine(
              hasMemory: latestCard != null,
              elderName: storyteller.nickname,
            ),
            const SizedBox(height: 16),
            _EpisodeHero(
              episode: today,
              onOpen: () => unawaited(onOpenEpisode(today)),
            ),
            const SizedBox(height: 18),
            _FamilyPresence(
              members: familyCircle.members,
              latestCard: latestCard,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '還想演哪一集？',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const _TinyPill(label: '每集約 1 分鐘'),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              '每個選擇都會讓故事走向不一樣的地方。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 13),
            SizedBox(
              height: 194,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return _EpisodeMiniCard(
                    episode: episode,
                    isToday: episode.id == today.id,
                    onTap: () => unawaited(onOpenEpisode(episode)),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            const _NoWaitingPromise(),
          ],
        );
      },
    );
  }
}

class _WelcomeLine extends StatelessWidget {
  const _WelcomeLine({required this.hasMemory, required this.elderName});

  final bool hasMemory;
  final String elderName;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasMemory ? '故事又翻到新的一頁' : '今天，$elderName在等你接故事',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 5),
              Text(
                hasMemory ? '說一句、做一個選擇，看看家裡接著發生什麼。' : '不必先會越南語；看懂情境，再跟角色慢慢說。',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.sunSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.face_3_rounded,
            size: 34,
            color: AppColors.coral,
          ),
        ),
      ],
    );
  }
}

class _EpisodeHero extends StatelessWidget {
  const _EpisodeHero({required this.episode, required this.onOpen});

  final ConversationEpisode episode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '今天的家庭劇場：${episode.title}',
      child: Container(
        height: 420,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.berrySoft,
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20253331),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _EpisodeImage(asset: episode.illustrationAsset),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x12000000), Color(0xEA1B2927)],
                  stops: [.28, 1],
                ),
              ),
            ),
            const Positioned(
              left: 16,
              top: 16,
              child: _HeroTag(icon: Icons.play_arrow_rounded, label: '今天的第一幕'),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    episode.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    episode.subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    '約 1 分鐘 · 點場景、聽阿嬤、讓故事改變',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 15),
                  FilledButton.icon(
                    key: ValueKey('open-daily-theater'),
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sun,
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size.fromHeight(58),
                    ),
                    icon: const Icon(Icons.theater_comedy_rounded, size: 26),
                    label: Text('進入「${episode.title}」'),
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

class _FamilyPresence extends StatelessWidget {
  const _FamilyPresence({required this.members, required this.latestCard});

  final List<FamilyMember> members;
  final FamilyCircleStoryCard? latestCard;

  @override
  Widget build(BuildContext context) {
    final continuation = latestCard?.continuations.isNotEmpty == true
        ? latestCard!.continuations.last
        : null;
    final reaction = latestCard?.reactions.isNotEmpty == true
        ? latestCard!.reactions.last
        : null;
    final respondingMemberId =
        continuation?.adultMemberId ?? reaction?.memberId;
    FamilyMember? respondingMember;
    if (respondingMemberId != null) {
      for (final member in members) {
        if (member.id == respondingMemberId) {
          respondingMember = member;
          break;
        }
      }
    }
    final respondingName = respondingMember?.nickname ?? '家人';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 46,
            child: Stack(
              children: [
                for (var index = 0;
                    index < members.length && index < 3;
                    index++)
                  Positioned(
                    left: index * 27,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Color(members[index].roleColorValue),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Text(
                        members[index].nickname.characters.first,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  continuation != null
                      ? '$respondingName留了一句話給你！'
                      : reaction != null
                          ? '$respondingName回應了你的故事！'
                          : latestCard == null
                              ? '故事演完就會留在這裡'
                              : '上一集已收進家庭故事簿',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  latestCard == null
                      ? '家人可以在這台裝置加貼圖或留一句話。'
                      : continuation?.text ??
                          (reaction != null
                              ? '家人送來：${reaction.sticker.zhLabel}'
                              : '「${latestCard!.sourceConversationCard?.title ?? latestCard!.episode}」${latestCard!.sceneOutcome}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeMiniCard extends StatelessWidget {
  const _EpisodeMiniCard({
    required this.episode,
    required this.isToday,
    required this.onTap,
  });

  final ConversationEpisode episode;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: ValueKey('episode-card-${episode.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 105,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _EpisodeImage(asset: episode.illustrationAsset),
                    if (isToday)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: _TinyPill(label: '今天'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${episode.totalTurns} 回合 · 兩種走法',
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
        ),
      ),
    );
  }
}

class _NoWaitingPromise extends StatelessWidget {
  const _NoWaitingPromise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.jadeSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.theater_comedy_rounded,
            size: 30,
            color: AppColors.jade,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '角色現在陪你演，家人有空再加戲',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  '你不用等任何人就能把故事演完；真人回覆是驚喜，不是關卡。',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeImage extends StatelessWidget {
  const _EpisodeImage({required this.asset});

  final String? asset;

  @override
  Widget build(BuildContext context) {
    final path = asset;
    if (path == null) return const _EpisodeImageFallback();
    return Image.asset(
      path,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 260),
            child: child,
          );
        }
        return const _EpisodeImageLoading();
      },
      errorBuilder: (_, __, ___) => const _EpisodeImageFallback(),
    );
  }
}

class _EpisodeImageLoading extends StatelessWidget {
  const _EpisodeImageLoading();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFEEE7), Color(0xFFFFD8C9)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          size: 58,
          color: AppColors.coral,
        ),
      ),
    );
  }
}

class _EpisodeImageFallback extends StatelessWidget {
  const _EpisodeImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7656C5), Color(0xFF4C9BE8)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.home_rounded,
          size: 62,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.coral, size: 18),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.sunSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}
