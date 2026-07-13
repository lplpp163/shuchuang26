import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../models/education_opportunity.dart';
import '../services/family_circle_store.dart';

class PracticeHubScreen extends StatelessWidget {
  const PracticeHubScreen({
    required this.familyCircle,
    required this.onOpenEpisode,
    required this.onCreateFromIdea,
    this.completedStoryIdeaIds = const <String>{},
    this.now,
    this.launchOfficialUrl,
    super.key,
  });

  final FamilyCircleStore familyCircle;
  final Future<void> Function(ConversationEpisode episode) onOpenEpisode;
  final Future<void> Function(StoryIdea idea) onCreateFromIdea;
  final Set<String> completedStoryIdeaIds;
  final DateTime Function()? now;
  final Future<bool> Function(Uri url)? launchOfficialUrl;

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
        final playedIds =
            familyCircle.cards.map((card) => card.episode).toSet();
        return ListView(
          key: const ValueKey('episode-library'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
          children: [
            Text('挑一集來演', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            const Text(
              '你不是在選題型，而是在決定今天要和家人發生什麼故事。',
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 18),
            _LibraryHero(completedCount: playedIds.length),
            const SizedBox(height: 16),
            _StoryAndEducationTeaser(
              now: now?.call() ?? DateTime.now(),
              launchOfficialUrl: launchOfficialUrl,
              onCreateFromIdea: onCreateFromIdea,
              completedStoryIdeaIds: completedStoryIdeaIds,
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 680 ? 2 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final episode in episodes)
                      SizedBox(
                        width: width,
                        child: _LibraryEpisodeCard(
                          episode: episode,
                          hasPlayed: playedIds.contains(episode.id),
                          onOpen: () => unawaited(onOpenEpisode(episode)),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            _StoryIdeaSection(
              onCreateFromIdea: onCreateFromIdea,
              completedStoryIdeaIds: completedStoryIdeaIds,
            ),
            const SizedBox(height: 22),
            _EducationOpportunityEntry(
              now: now?.call() ?? DateTime.now(),
              launchOfficialUrl: launchOfficialUrl,
              onCreateFromIdea: onCreateFromIdea,
            ),
            const SizedBox(height: 22),
            const _HowVoiceWorks(),
          ],
        );
      },
    );
  }
}

class _StoryAndEducationTeaser extends StatelessWidget {
  const _StoryAndEducationTeaser({
    required this.now,
    required this.launchOfficialUrl,
    required this.onCreateFromIdea,
    required this.completedStoryIdeaIds,
  });

  final DateTime now;
  final Future<bool> Function(Uri url)? launchOfficialUrl;
  final Future<void> Function(StoryIdea idea) onCreateFromIdea;
  final Set<String> completedStoryIdeaIds;

  Future<void> _openEducation(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EducationOpportunitySheet(
        now: now,
        launchOfficialUrl: launchOfficialUrl,
        onCreateFromIdea: onCreateFromIdea,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('library-top-story-teaser'),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.berrySoft, AppColors.skySoft],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.forum_rounded, color: AppColors.berry),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '把今天的事帶回家說',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '先挑一個故事種子，再交給家人確認真正說法；完成後會變成孩子可闖四關的生活任務，但不冒充內建分支劇集。',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 11),
          _StoryPassportProgress(completedIds: completedStoryIdeaIds),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final idea in StoryIdeaCatalog.next)
                _StorySeedChip(
                  idea: idea,
                  completed: completedStoryIdeaIds.contains(idea.id),
                  onPressed: () => unawaited(onCreateFromIdea(idea)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('top-education-opportunities'),
            onPressed: () => unawaited(_openEducation(context)),
            icon: const Icon(Icons.school_rounded),
            label: Text(
              '${EducationOpportunityCatalog.official.length} 筆官方教材・課程・競賽入口',
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryPassportProgress extends StatelessWidget {
  const _StoryPassportProgress({required this.completedIds});

  final Set<String> completedIds;

  @override
  Widget build(BuildContext context) {
    final total = StoryIdeaCatalog.next.length;
    final count = StoryIdeaCatalog.next
        .where((idea) => completedIds.contains(idea.id))
        .length;
    return Container(
      key: const ValueKey('story-passport-progress'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories_rounded, color: AppColors.coral),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '家庭故事護照',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$count／$total',
                key: const ValueKey('story-passport-count'),
                style: const TextStyle(
                  color: AppColors.berry,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 9,
              backgroundColor: AppColors.berrySoft,
              color: AppColors.jade,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            count == 0
                ? '先從今天最想說的一件事開始；護照只在這台裝置記錄完成題材。'
                : count == total
                    ? '五種日常都留下家庭版本了；可以挑一題再做不同的說法。'
                    : '已完成$count種日常；再收集${total - count}種，就有一組家庭說故事素材。',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StorySeedChip extends StatelessWidget {
  const _StorySeedChip({
    required this.idea,
    required this.completed,
    required this.onPressed,
  });

  final StoryIdea idea;
  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: ValueKey('story-seed-chip-${idea.id}'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: completed ? AppColors.jadeSoft : Colors.white,
        side: BorderSide(
          color: completed ? AppColors.jade : AppColors.border,
        ),
      ),
      icon: Icon(
        completed ? Icons.check_circle_rounded : _storyIdeaIcon(idea.id),
        size: 17,
        color: completed ? AppColors.jade : AppColors.berry,
      ),
      label: Text(idea.title),
      onPressed: onPressed,
    );
  }
}

class _StoryIdeaSection extends StatelessWidget {
  const _StoryIdeaSection({
    required this.onCreateFromIdea,
    required this.completedStoryIdeaIds,
  });

  final Future<void> Function(StoryIdea idea) onCreateFromIdea;
  final Set<String> completedStoryIdeaIds;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('story-idea-section'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.berrySoft,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: AppColors.berry),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  '家庭故事靈感',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '這五類不是已完成劇集，也不在 119 個內建示範音檔裡。孩子先挑今天想說的事，再把裝置交給家人，做成由家人確認、孩子可闖四關的生活任務；護照只記題材是否完成，不讀取短句內容。',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          for (var index = 0;
              index < StoryIdeaCatalog.next.length;
              index++) ...[
            _StoryIdeaCard(
              index: index,
              idea: StoryIdeaCatalog.next[index],
              completed: completedStoryIdeaIds.contains(
                StoryIdeaCatalog.next[index].id,
              ),
              onCreate: () =>
                  unawaited(onCreateFromIdea(StoryIdeaCatalog.next[index])),
            ),
            if (index < StoryIdeaCatalog.next.length - 1)
              const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _StoryIdeaCard extends StatelessWidget {
  const _StoryIdeaCard({
    required this.index,
    required this.idea,
    required this.completed,
    required this.onCreate,
  });

  final int index;
  final StoryIdea idea;
  final bool completed;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('story-idea-${idea.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: completed ? AppColors.jade : Colors.white,
          width: completed ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.berry,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        idea.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      completed ? '護照已蓋章' : '共創題材',
                      style: TextStyle(
                        color: completed ? AppColors.jade : AppColors.berry,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(idea.prompt),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey('create-story-idea-${idea.id}'),
                    onPressed: onCreate,
                    icon: Icon(
                      completed
                          ? Icons.replay_rounded
                          : Icons.family_restroom_rounded,
                      size: 18,
                    ),
                    label: Text(completed ? '再做一個家庭版本' : '交給家人做成四關任務'),
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

class _EducationOpportunityEntry extends StatelessWidget {
  const _EducationOpportunityEntry({
    required this.now,
    required this.launchOfficialUrl,
    required this.onCreateFromIdea,
  });

  final DateTime now;
  final Future<bool> Function(Uri url)? launchOfficialUrl;
  final Future<void> Function(StoryIdea idea) onCreateFromIdea;

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EducationOpportunitySheet(
        now: now,
        launchOfficialUrl: launchOfficialUrl,
        onCreateFromIdea: onCreateFromIdea,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('education-opportunity-entry'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.jadeSoft, AppColors.skySoft],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.school_rounded, color: AppColors.jade, size: 32),
          const SizedBox(height: 10),
          const Text(
            '教育機會情報',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '收件期程、官方教育資源與已結束比賽成果，都先在 App 內看清楚；只有你按下官方頁按鈕才會離開。',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('show-education-opportunities'),
            onPressed: () => unawaited(_openSheet(context)),
            icon: const Icon(Icons.fact_check_outlined),
            label:
                Text('查看 ${EducationOpportunityCatalog.official.length} 筆官方資訊'),
          ),
        ],
      ),
    );
  }
}

class _EducationOpportunitySheet extends StatelessWidget {
  const _EducationOpportunitySheet({
    required this.now,
    required this.launchOfficialUrl,
    required this.onCreateFromIdea,
  });

  final DateTime now;
  final Future<bool> Function(Uri url)? launchOfficialUrl;
  final Future<void> Function(StoryIdea idea) onCreateFromIdea;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: SingleChildScrollView(
        key: const ValueKey('education-opportunity-list'),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '教育機會情報',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('close-education-opportunities'),
                  tooltip: '關閉教育資訊',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '傳家話只整理官方入口，不代辦報名、不收集報名資料。請和家人一起查看。',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            for (var index = 0;
                index < EducationOpportunityCatalog.official.length;
                index++) ...[
              _EducationOpportunityCard(
                opportunity: EducationOpportunityCatalog.official[index],
                now: now,
                launchOfficialUrl: launchOfficialUrl,
                onCreateFromIdea: onCreateFromIdea,
              ),
              if (index < EducationOpportunityCatalog.official.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _EducationOpportunityCard extends StatelessWidget {
  const _EducationOpportunityCard({
    required this.opportunity,
    required this.now,
    required this.launchOfficialUrl,
    required this.onCreateFromIdea,
  });

  final EducationOpportunity opportunity;
  final DateTime now;
  final Future<bool> Function(Uri url)? launchOfficialUrl;
  final Future<void> Function(StoryIdea idea) onCreateFromIdea;

  void _startLocalExtension(BuildContext context) {
    final idea = StoryIdeaCatalog.next.singleWhere(
      (candidate) => candidate.id == opportunity.localStoryIdeaId,
    );
    Navigator.of(context).pop();
    unawaited(onCreateFromIdea(idea));
  }

  Future<void> _openOfficialPage(BuildContext context) async {
    var opened = false;
    try {
      opened = await (launchOfficialUrl?.call(opportunity.officialUrl) ??
          launchUrl(
            opportunity.officialUrl,
            mode: LaunchMode.externalApplication,
          ));
    } on Object {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('official-link-error'),
        title: const Text('無法開啟官方頁'),
        content: const Text('請稍後再試；活動日期與辦法仍以官網公告為準。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = opportunity.statusAt(now);
    return Container(
      key: ValueKey('education-opportunity-${opportunity.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (opportunity.scheduleLabel case final schedule?)
                Text(
                  schedule,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            opportunity.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(opportunity.summary),
          const SizedBox(height: 10),
          Text(
            '官方主辦：${opportunity.organizer}',
            style: const TextStyle(
              color: AppColors.jade,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            EducationOpportunityCatalog.checkedOnLabel,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 2),
          const Text(
            '以官網為準',
            style: TextStyle(
              color: AppColors.coral,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '主題延伸，非官方授權教案',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: ValueKey('start-local-extension-${opportunity.id}'),
            onPressed: () => _startLocalExtension(context),
            icon: const Icon(Icons.family_restroom_rounded),
            label: Text(opportunity.localActionLabel),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: ValueKey('open-official-${opportunity.id}'),
            onPressed: () => unawaited(_openOfficialPage(context)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('和家人開啟官方頁'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        '收件中' => AppColors.jadeSoft,
        '即將收件' => AppColors.skySoft,
        '持續更新' => AppColors.sunSoft,
        _ => AppColors.cream,
      };
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({required this.completedCount});

  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7656C5), Color(0xFF4C9BE8)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.theater_comedy_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '五個生活舞台，很多種我們家',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completedCount == 0
                      ? '從一集開始，故事會記住你選過的路。'
                      : '你已經留下 $completedCount 個場景的家庭回憶。',
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryEpisodeCard extends StatelessWidget {
  const _LibraryEpisodeCard({
    required this.episode,
    required this.hasPlayed,
    required this.onOpen,
  });

  final ConversationEpisode episode;
  final bool hasPlayed;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('library-${episode.id}'),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (episode.illustrationAsset case final path?)
                    Image.asset(
                      path,
                      fit: BoxFit.cover,
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return child;
                        }
                        return _fallback();
                      },
                      errorBuilder: (_, __, ___) => _fallback(),
                    )
                  else
                    _fallback(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xC8253331)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: hasPlayed ? AppColors.jadeSoft : Colors.white,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        hasPlayed ? '演過，還能換條路' : '新故事',
                        style: TextStyle(
                          color: hasPlayed ? AppColors.jade : AppColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 13,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          episode.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                children: [
                  for (var index = 0; index < episode.totalTurns; index++) ...[
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.berrySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppColors.berry,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (index < episode.totalTurns - 1)
                      Container(width: 14, height: 2, color: AppColors.border),
                  ],
                  const Spacer(),
                  const Text(
                    '開始演',
                    style: TextStyle(
                      color: AppColors.jade,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.jade,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.sky, AppColors.berry],
          ),
        ),
        child: const Center(
          child: Icon(Icons.home_rounded, color: Colors.white, size: 60),
        ),
      );
}

class _HowVoiceWorks extends StatelessWidget {
  const _HowVoiceWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.sunSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '卡住也不會被判錯',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 10),
          _HelpRow(
            icon: Icons.hearing_rounded,
            text: '角色先說，隨時可以重播或看中文。',
          ),
          SizedBox(height: 8),
          _HelpRow(
            icon: Icons.mic_rounded,
            text: '裝置會尋找選項關鍵詞，不替發音打分。',
          ),
          SizedBox(height: 8),
          _HelpRow(
            icon: Icons.image_rounded,
            text: '沒有聽清楚時，圖片和短詞會幫故事繼續。',
          ),
        ],
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.coral, size: 22),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    );
  }
}

IconData _storyIdeaIcon(String id) => switch (id) {
      'family-sharing' => Icons.record_voice_over_rounded,
      'club' => Icons.groups_rounded,
      'lunch' => Icons.lunch_dining_rounded,
      'class' => Icons.school_rounded,
      'friendship' => Icons.handshake_rounded,
      _ => Icons.forum_rounded,
    };
