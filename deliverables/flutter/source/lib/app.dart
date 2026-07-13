import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
import 'models/conversation_episode.dart';
import 'models/education_opportunity.dart';
import 'models/family_circle.dart';
import 'models/family_invitation.dart';
import 'models/family_relay.dart';
import 'models/family_story.dart';
import 'screens/conversation_theater_screen.dart';
import 'screens/family_circle_screen.dart';
import 'screens/home_screen.dart';
import 'screens/learning_flow.dart';
import 'screens/practice_hub_screen.dart';
import 'screens/privacy_gate.dart';
import 'screens/quick_challenge_screen.dart';
import 'screens/story_detail_screen.dart';
import 'services/app_store.dart';
import 'services/family_circle_store.dart';
import 'services/local_media_service.dart';
import 'widgets/adult_pin_gate.dart';
import 'widgets/brand_mark.dart';
import 'widgets/family_invitation_acceptance.dart';
import 'widgets/privacy_center_sheet.dart';

const primaryAdultMemberId = 'family-owner';
const primaryChildMemberId = 'family-child';

class HomeTongueApp extends StatefulWidget {
  const HomeTongueApp({
    required this.store,
    this.familyCircle,
    this.media,
    super.key,
  });

  final AppStore store;
  final FamilyCircleStore? familyCircle;
  final LocalMediaService? media;

  @override
  State<HomeTongueApp> createState() => _HomeTongueAppState();
}

class _HomeTongueAppState extends State<HomeTongueApp> {
  late final LocalMediaService _media;
  late final bool _ownsMedia;
  Future<FamilyCircleStore>? _familyCircleFuture;

  @override
  void initState() {
    super.initState();
    _ownsMedia = widget.media == null;
    _media = widget.media ?? LocalMediaService();
  }

  Future<FamilyCircleStore> _loadFamilyCircle() async {
    return widget.familyCircle ?? FamilyCircleStore.load();
  }

  Future<FamilyCircleStore> _circleAfterConsent() =>
      _familyCircleFuture ??= _loadFamilyCircle();

  @override
  void dispose() {
    if (_ownsMedia) unawaited(_media.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appBrandName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          if (!widget.store.privacyConsent) {
            _familyCircleFuture = null;
            return PrivacyGate(store: widget.store, media: _media);
          }
          return FutureBuilder<FamilyCircleStore>(
            future: _circleAfterConsent(),
            builder: (context, snapshot) {
              final circle = snapshot.data;
              if (circle == null) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final hasAdult = circle.members.any(
                (member) => member.isApproved && member.isAdult,
              );
              final hasChild = circle.members.any(
                (member) => member.isApproved && !member.isAdult,
              );
              if (!hasAdult || !hasChild) {
                return _FamilyCircleSetupScreen(
                  circle: circle,
                  onReady: () => setState(() {}),
                );
              }
              return MainShell(
                store: widget.store,
                familyCircle: circle,
                media: _media,
              );
            },
          );
        },
      ),
    );
  }
}

class _FamilyCircleSetupScreen extends StatefulWidget {
  const _FamilyCircleSetupScreen({
    required this.circle,
    required this.onReady,
  });

  final FamilyCircleStore circle;
  final VoidCallback onReady;

  @override
  State<_FamilyCircleSetupScreen> createState() =>
      _FamilyCircleSetupScreenState();
}

class _FamilyCircleSetupScreenState extends State<_FamilyCircleSetupScreen> {
  final _adultNameController = TextEditingController();
  final _childNameController = TextEditingController();
  String _relationship = '外婆';
  bool _confirmed = false;
  bool _saving = false;
  String? _setupError;

  FamilyMember? get _existingAdult {
    for (final member in widget.circle.members) {
      if (member.isApproved && member.isAdult) return member;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final adult = _existingAdult;
    if (adult != null) {
      _adultNameController.text = adult.nickname;
      _relationship = adult.relationship;
    }
  }

  @override
  void dispose() {
    _adultNameController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  String _availableId(String preferred) {
    if (widget.circle.memberById(preferred) == null) return preferred;
    var suffix = 2;
    while (widget.circle.memberById('$preferred-$suffix') != null) {
      suffix += 1;
    }
    return '$preferred-$suffix';
  }

  Future<void> _createCircle() async {
    if (_saving || !_confirmed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // Web and mobile IMEs can commit their last composing text when focus is
    // released. Read controllers on the following frame so the visible name
    // and the saved name can never diverge.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final adultName = _adultNameController.text.trim();
    final childName = _childNameController.text.trim();
    if (adultName.isEmpty || childName.isEmpty) {
      setState(() => _setupError = '請填上長輩稱呼和孩子小名。');
      return;
    }

    setState(() {
      _saving = true;
      _setupError = null;
    });
    try {
      var adult = _existingAdult;
      if (adult == null) {
        final now = DateTime.now();
        final adultId = _availableId(primaryAdultMemberId);
        await widget.circle.bootstrapAdult(
          FamilyMember(
            id: adultId,
            relationship: _relationship,
            nickname: adultName,
            isAdult: true,
            avatarEmoji: '👵🏻',
            roleColorValue: 0xFFFFE5DE,
            createdAt: now,
          ),
        );
        adult = widget.circle.memberById(adultId);
      }
      if (adult == null) throw StateError('家庭圈缺少管理者。');

      FamilyMember? child;
      for (final member in widget.circle.members) {
        if (!member.isAdult) {
          child = member;
          break;
        }
      }
      if (child == null) {
        final childId = _availableId(primaryChildMemberId);
        await widget.circle.inviteMember(
          actorMemberId: adult.id,
          member: FamilyMember(
            id: childId,
            relationship: '孩子',
            nickname: childName,
            isAdult: false,
            avatarEmoji: '🧒🏻',
            roleColorValue: 0xFFDDEEFF,
            createdAt: DateTime.now(),
          ),
        );
        child = widget.circle.memberById(childId);
      }
      if (child != null && !child.isApproved) {
        await widget.circle.approveMember(
          actorMemberId: adult.id,
          memberId: child.id,
        );
      }
      widget.onReady();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('還沒建立成功：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adultAlreadyExists = _existingAdult != null;
    final canSubmit = _confirmed && !_saving;
    return Scaffold(
      appBar: AppBar(title: const BrandMark(compact: true)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: .13),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      size: 40,
                      color: AppColors.coral,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    adultAlreadyExists ? '再加入一位孩子' : '先建立你們家的小圈圈',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '不會自動假設誰是家人。由一位成人親自確認後，故事卡才會留在這個裝置的家庭圈。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    key: const ValueKey('accept-family-invitation'),
                    onPressed: () => showAcceptFamilyInvitationFlow(context),
                    icon: const Icon(Icons.mark_email_unread_outlined),
                    label: const Text('我收到另一個家庭的邀請'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '或在這台裝置建立新家庭',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  if (!adultAlreadyExists) ...[
                    Text(
                      '這位說故事的女性長輩是誰？',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['外婆', '阿嬤', '奶奶', '其他女性長輩']
                          .map(
                            (role) => ChoiceChip(
                              label: Text(role),
                              labelStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              selected: _relationship == role,
                              onSelected: (_) =>
                                  setState(() => _relationship = role),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '越南語 bà 可用於外婆、奶奶等女性長輩；請在下方填家裡真正使用的稱呼。',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const ValueKey('family-setup-adult-name'),
                    controller: _adultNameController,
                    enabled: !adultAlreadyExists,
                    decoration: const InputDecoration(
                      labelText: '孩子怎麼叫這位長輩？',
                      hintText: '例如：阿嬤、姨婆或家中習慣稱呼',
                      prefixIcon: Icon(Icons.face_3_outlined),
                    ),
                  ),
                  if (_setupError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _setupError!,
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('family-setup-child-name'),
                    controller: _childNameController,
                    decoration: const InputDecoration(
                      labelText: '孩子的小名',
                      hintText: '例如：小米',
                      prefixIcon: Icon(Icons.child_care_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    onChanged: (value) =>
                        setState(() => _confirmed = value ?? false),
                    title: const Text('我是成人，確認以上兩位可以加入這個家庭圈'),
                    subtitle: const Text(
                      '目前只保存在這台裝置，不會自動傳給其他人。',
                      style: TextStyle(fontSize: 15, height: 1.4),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('create-family-circle'),
                    onPressed: canSubmit ? _createCircle : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_rounded),
                    label: Text(_saving ? '正在建立…' : '確認家人，進入故事劇場'),
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

class MainShell extends StatefulWidget {
  const MainShell({
    required this.store,
    required this.familyCircle,
    required this.media,
    super.key,
  });

  final AppStore store;
  final FamilyCircleStore familyCircle;
  final LocalMediaService media;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _childIndex = 0;
  _AdultPage? _adultPage;
  bool _startedImageWarmup = false;
  String? _actingAdultMemberId;
  String? _quickDraftSource;
  String? _quickDraftIdeaId;
  String? _quickDraftIdeaTitle;
  String? _quickRelayId;
  String? _quickRelayChildIntent;

  FamilyMember get _adultMember {
    final managerId = widget.familyCircle.managerMemberId;
    return widget.familyCircle.members.firstWhere(
      (member) => member.id == managerId && member.isApproved && member.isAdult,
      orElse: () => widget.familyCircle.members.firstWhere(
        (member) => member.isApproved && member.isAdult,
      ),
    );
  }

  FamilyMember get _childMember => widget.familyCircle.members.firstWhere(
        (member) => member.isApproved && !member.isAdult,
      );

  FamilyMember get _actingAdultMember {
    final requestedId = _actingAdultMemberId;
    if (requestedId != null) {
      for (final member in widget.familyCircle.members) {
        if (member.id == requestedId && member.isApproved && member.isAdult) {
          return member;
        }
      }
    }
    return _adultMember;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.familyCircle.addListener(_refreshCircleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedImageWarmup) return;
    _startedImageWarmup = true;
    for (final episode in ConversationEpisodeCatalog.defaults) {
      final asset = episode.illustrationAsset;
      if (asset != null) {
        unawaited(
          precacheImage(AssetImage(asset), context).catchError((_) {}),
        );
      }
    }
    unawaited(
      precacheImage(
        const AssetImage('assets/images/family-stage-duo-v1.png'),
        context,
      ).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.familyCircle.removeListener(_refreshCircleState);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !mounted) return;
    setState(() {
      _quickDraftSource = null;
      _quickDraftIdeaId = null;
      _quickDraftIdeaTitle = null;
      _quickRelayId = null;
      _quickRelayChildIntent = null;
      _adultPage = null;
      _actingAdultMemberId = null;
    });
  }

  void _refreshCircleState() {
    if (mounted) setState(() {});
  }

  void _setChildIndex(int index) {
    setState(() => _childIndex = index);
  }

  Future<void> _saveConversationCard(ConversationStoryCard card) async {
    if (widget.familyCircle.cardById(card.id) != null) return;
    final familyCard = FamilyCircleStoryCard.fromConversationCard(
      card,
      createdByMemberId: _childMember.id,
      childMemberId: _childMember.id,
    );
    await widget.familyCircle.addStoryCard(
      actorMemberId: _childMember.id,
      card: familyCard,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('故事卡已放進我們家的私密故事圈。')),
      );
    }
  }

  Future<bool> _requestIndividualMemberPin(FamilyMember member) async {
    final controller = TextEditingController();
    String? errorText;
    var busy = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(
            Icons.switch_account_rounded,
            color: AppColors.berry,
            size: 36,
          ),
          title: Text('請 ${member.nickname} 本人確認'),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '輸入 ${member.nickname} 接受邀請時設定的六位數家人碼。其他家人的碼不能代替。',
                    style:
                        const TextStyle(color: AppColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: ValueKey('member-pin-${member.id}'),
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '${member.nickname} 的六位數家人碼',
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                  ),
                  if (errorText != null)
                    Text(
                      errorText!,
                      key: const ValueKey('member-pin-error'),
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消切換'),
            ),
            FilledButton(
              key: const ValueKey('verify-individual-member-pin'),
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      final result = await widget.familyCircle.verifyMemberPin(
                        memberId: member.id,
                        pin: controller.text,
                      );
                      if (!dialogContext.mounted) return;
                      if (result.isVerified) {
                        Navigator.pop(dialogContext, true);
                        return;
                      }
                      setDialogState(() {
                        busy = false;
                        errorText = switch (result.status) {
                          FamilyMemberPinVerificationStatus.incorrect =>
                            '家人碼不對，還可以再試 ${result.remainingAttempts} 次。',
                          FamilyMemberPinVerificationStatus.locked =>
                            '嘗試太多次，先休息 30 秒；其他家人仍可使用。',
                          FamilyMemberPinVerificationStatus.invalidFormat =>
                            '家人碼要剛好六位數。',
                          FamilyMemberPinVerificationStatus.unavailable =>
                            '這位家人還沒在這台裝置完成本人接受。',
                          FamilyMemberPinVerificationStatus.verified => null,
                        };
                      });
                    },
              child: Text(busy ? '正在確認…' : '確認是 ${member.nickname}'),
            ),
          ],
        ),
      ),
    );
    // showDialog completes when pop starts; keep the controller alive through
    // the route's reverse animation so the fading TextField cannot rebuild
    // against a disposed notifier.
    await Future<void>.delayed(kThemeAnimationDuration);
    controller.dispose();
    return verified ?? false;
  }

  Future<void> _switchActingAdult(String memberId) async {
    if (memberId == _actingAdultMember.id) return;
    final member = widget.familyCircle.memberById(memberId);
    if (member == null || !member.isApproved || !member.isAdult) return;

    final verified = widget.familyCircle.memberHasIndividualPin(member.id)
        ? await _requestIndividualMemberPin(member)
        : member.id == _adultMember.id
            ? await requestAdultPin(
                context,
                widget.store,
                reason: '切回家庭管理者時，需要管理者自己的確認。',
              )
            : false;
    if (!verified || !mounted) return;
    setState(() => _actingAdultMemberId = member.id);
  }

  Future<void> _openEpisode(ConversationEpisode episode) async {
    await Navigator.of(context).push<ConversationStoryCard>(
      MaterialPageRoute(
        builder: (context) => ConversationTheaterScreen(
          episode: episode,
          media: widget.media,
          familyEpisodeVoices: widget.familyCircle.episodeVoicesFor(episode.id),
          // Web browsers may reject playback that starts after navigation and
          // a post-frame callback. Keep the first elder line behind an obvious
          // tap so real Edge/Chrome users always create the media gesture.
          autoPlayElderVoice: false,
          autoAdvanceReplies: true,
          onStoryCardCreated: _saveConversationCard,
        ),
      ),
    );
  }

  Future<void> _openStoryIdeaDraft(StoryIdea idea) async {
    final choice = await showModalBottomSheet<StorySeedChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _StorySeedIntentSheet(
        idea: idea,
        childName: _childMember.nickname,
      ),
    );
    if (choice == null || !mounted) return;
    final relay = await widget.store.startFamilyRelay(
      seedId: idea.id,
      seedTitle: idea.title,
      childIntentZh: choice.intentZh,
      childMemberId: _childMember.id,
    );
    if (!mounted) return;
    final handedOver = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('handoff-story-idea-${idea.id}'),
        icon: const Icon(
          Icons.family_restroom_rounded,
          color: AppColors.berry,
          size: 34,
        ),
        title: Text('把「${idea.title}」交給家人'),
        content: Text(
          '${_childMember.nickname}已經留下第一棒。接下來請把裝置交給家人；家人會確認真正的說法，系統不會替家庭猜翻譯。',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('先不要'),
          ),
          FilledButton(
            key: ValueKey('continue-story-idea-${idea.id}'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('已交給家人'),
          ),
        ],
      ),
    );
    if (handedOver != true || !mounted) return;
    final unlocked = await requestAdultPin(
      context,
      widget.store,
      reason: '把孩子挑的故事靈感做成家庭短句，需要家庭管理者確認。',
    );
    if (!unlocked || !mounted) return;
    setState(() {
      _quickDraftSource = choice.draftSource;
      _quickDraftIdeaId = idea.id;
      _quickDraftIdeaTitle = idea.title;
      _quickRelayId = relay.id;
      _quickRelayChildIntent = choice.intentZh;
      _adultPage = _AdultPage.quick;
    });
  }

  Future<void> _openPrivacyCenter({bool alreadyUnlocked = false}) async {
    if (!alreadyUnlocked) {
      final unlocked = await requestAdultPin(
        context,
        widget.store,
        reason: '匯出與刪除家庭資料需要成人確認。',
      );
      if (!unlocked || !mounted) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => PrivacyCenterSheet(
        store: widget.store,
        familyCircle: widget.familyCircle,
        adultMemberId: _adultMember.id,
        media: widget.media,
      ),
    );
  }

  Future<void> _openApprovedFamilyMemberMode() async {
    final invitedAdults = widget.familyCircle.members
        .where(
          (member) =>
              member.isApproved &&
              member.isAdult &&
              widget.familyCircle.memberHasIndividualPin(member.id),
        )
        .toList(growable: false);
    if (invitedAdults.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('還沒有已接受邀請的家人'),
          content: const Text('請由家庭管理者先建立邀請，再由家人本人接受並帶回回覆包。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final member = await showModalBottomSheet<FamilyMember>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '今天由哪位家人回應？',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              '下一步只會詢問這位家人自己的六位數家人碼。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            for (final item in invitedAdults)
              ListTile(
                key: ValueKey('enter-as-${item.id}'),
                leading: const CircleAvatar(
                  child: Icon(Icons.record_voice_over_rounded),
                ),
                title: Text(item.nickname),
                subtitle: Text(item.relationship),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (member == null || !mounted) return;
    final verified = await _requestIndividualMemberPin(member);
    if (!verified || !mounted) return;
    setState(() {
      _actingAdultMemberId = member.id;
      _adultPage = _AdultPage.familyCircle;
    });
  }

  Future<void> _openParentMenu() async {
    final handoffAction = await showDialog<_FamilyHandoffAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.front_hand_rounded,
          color: AppColors.coral,
          size: 34,
        ),
        title: const Text('接下來請把裝置交給家人'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '家人的邀請、錄音和故事回應都由成人處理；孩子不用看懂任何設定。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                key: const ValueKey('continue-as-invited-family'),
                onPressed: () => Navigator.pop(
                  context,
                  _FamilyHandoffAction.invitedFamily,
                ),
                icon: const Icon(Icons.record_voice_over_rounded),
                label: const Text('已加入家人・回應故事'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('continue-to-family-pin'),
                onPressed: () => Navigator.pop(
                  context,
                  _FamilyHandoffAction.manager,
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('家庭管理者・出題與管理'),
              ),
              TextButton.icon(
                key: const ValueKey('received-family-invitation'),
                onPressed: () => Navigator.pop(
                  context,
                  _FamilyHandoffAction.acceptInvitation,
                ),
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: const Text('我收到一份邀請'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回故事'),
          ),
        ],
      ),
    );
    if (!mounted || handoffAction == null) return;
    if (handoffAction == _FamilyHandoffAction.acceptInvitation) {
      await showAcceptFamilyInvitationFlow(context);
      return;
    }
    if (handoffAction == _FamilyHandoffAction.invitedFamily) {
      await _openApprovedFamilyMemberMode();
      return;
    }
    final unlocked = await requestAdultPin(
      context,
      widget.store,
      reason: '家人模式可以出短句、回應故事與管理資料。',
    );
    if (!unlocked || !mounted) return;
    final unread = widget.familyCircle.unreadCardsFor(_adultMember.id).length;
    final action = await showModalBottomSheet<_ParentAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ParentMenu(unreadCount: unread),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ParentAction.quick:
        setState(() {
          _quickDraftSource = null;
          _quickDraftIdeaId = null;
          _quickDraftIdeaTitle = null;
          _quickRelayId = null;
          _quickRelayChildIntent = null;
          _adultPage = _AdultPage.quick;
        });
      case _ParentAction.familyCircle:
        setState(() {
          _quickDraftSource = null;
          _quickDraftIdeaId = null;
          _quickDraftIdeaTitle = null;
          _quickRelayId = null;
          _quickRelayChildIntent = null;
          _actingAdultMemberId = null;
          _adultPage = _AdultPage.familyCircle;
        });
      case _ParentAction.privacy:
        await _openPrivacyCenter(alreadyUnlocked: true);
    }
  }

  void _handleQuickStoryCreated(FamilyStory story) {
    setState(() {
      _quickDraftSource = null;
      _quickDraftIdeaId = null;
      _quickDraftIdeaTitle = null;
      _quickRelayId = null;
      _quickRelayChildIntent = null;
      _adultPage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (story.lessonContent != null && story.familyChallenge != null) {
        await openLearningFlow(
          context: context,
          story: story,
          store: widget.store,
          media: widget.media,
        );
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => StoryDetailScreen(
              story: story,
              store: widget.store,
              media: widget.media,
            ),
          ),
        );
      }
      await _saveCompletedRelayCard(story);
      if (mounted) setState(() {});
    });
  }

  Future<void> _saveCompletedRelayCard(FamilyStory story) async {
    final relay = widget.store.relayForStory(story.id);
    if (relay == null || relay.stage != FamilyRelayStage.completed) return;
    final cardId = 'relay-${relay.id}';
    if (widget.familyCircle.cardById(cardId) != null) return;
    final attempt = widget.store.attempts.where(
      (item) => item.id == relay.childAttemptId,
    );
    if (attempt.isEmpty) return;
    final card = FamilyCircleStoryCard(
      id: cardId,
      episode: '家庭接力・${relay.seedTitle}',
      createdByMemberId: _childMember.id,
      childMemberId: _childMember.id,
      childChoice: relay.childIntentZh,
      childUtterance: story.targetText,
      sceneOutcome: '三棒接成一個家的故事',
      createdAt: relay.completedAt!,
      localRecordingReference: attempt.first.audioPath,
      relayId: relay.id,
      familyRecordingReference: story.audioPath,
    );
    await widget.familyCircle.addStoryCard(
      actorMemberId: _childMember.id,
      card: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final childUnread =
        widget.familyCircle.unreadCardsFor(_childMember.id).length;
    final childScreens = [
      HomeScreen(
        familyCircle: widget.familyCircle,
        onOpenEpisode: _openEpisode,
      ),
      PracticeHubScreen(
        familyCircle: widget.familyCircle,
        onOpenEpisode: _openEpisode,
        onCreateFromIdea: _openStoryIdeaDraft,
        completedStoryIdeaIds: widget.store.relays
            .where((relay) => relay.stage == FamilyRelayStage.completed)
            .map((relay) => relay.seedId)
            .toSet(),
      ),
      FamilyCircleScreen(
        store: widget.familyCircle,
        viewerMemberId: _childMember.id,
        media: widget.media,
        childMemberId: _childMember.id,
      ),
    ];
    final adultPage = _adultPage;
    final body = switch (adultPage) {
      _AdultPage.quick => QuickChallengeScreen(
          store: widget.store,
          media: widget.media,
          onCreated: _handleQuickStoryCreated,
          initialSourceText: _quickDraftSource,
          originStoryIdeaId: _quickDraftIdeaId,
          originStoryIdeaTitle: _quickDraftIdeaTitle,
          relayId: _quickRelayId,
          relayChildIntentZh: _quickRelayChildIntent,
          adultMemberId: _adultMember.id,
        ),
      _AdultPage.familyCircle => FamilyCircleScreen(
          store: widget.familyCircle,
          viewerMemberId: _actingAdultMember.id,
          media: widget.media,
          childMemberId: _childMember.id,
          adultActions: true,
          managerMemberId: _adultMember.id,
        ),
      null => IndexedStack(index: _childIndex, children: childScreens),
    };
    return Scaffold(
      appBar: AppBar(
        leading: adultPage == null
            ? null
            : IconButton(
                tooltip: '離開家人模式',
                onPressed: () => setState(() {
                  _quickDraftSource = null;
                  _quickDraftIdeaId = null;
                  _quickDraftIdeaTitle = null;
                  _quickRelayId = null;
                  _quickRelayChildIntent = null;
                  _adultPage = null;
                  _actingAdultMemberId = null;
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: adultPage == null
            ? const BrandMark(compact: true)
            : Text(switch (adultPage) {
                _AdultPage.quick => _quickDraftIdeaTitle == null
                    ? '做一張家庭短句'
                    : '家庭故事接力 · $_quickDraftIdeaTitle',
                _AdultPage.familyCircle =>
                  '家人加戲 · ${_actingAdultMember.nickname}',
              }),
        actions: [
          if (adultPage == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const ValueKey('parent-mode'),
                onPressed: _openParentMenu,
                icon: const Icon(Icons.pan_tool_alt_outlined, size: 18),
                label: const Text('交給家人'),
              ),
            ),
          if (adultPage == _AdultPage.familyCircle)
            PopupMenuButton<String>(
              tooltip: '切換正在回應的家人角色',
              icon: const Icon(Icons.switch_account_rounded),
              onSelected: _switchActingAdult,
              itemBuilder: (context) => [
                for (final member in widget.familyCircle.members.where(
                  (member) => member.isApproved && member.isAdult,
                ))
                  PopupMenuItem(
                    value: member.id,
                    child: Row(
                      children: [
                        Icon(
                          member.id == _actingAdultMember.id
                              ? Icons.check_circle_rounded
                              : Icons.account_circle_outlined,
                          color: member.id == _actingAdultMember.id
                              ? AppColors.jade
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 9),
                        Text(member.nickname),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: adultPage == null
          ? NavigationBar(
              selectedIndex: _childIndex,
              onDestinationSelected: _setChildIndex,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.theater_comedy_outlined),
                  selectedIcon: Icon(Icons.theater_comedy_rounded),
                  label: '劇場',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: '選故事',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: childUnread > 0,
                    label: Text('$childUnread'),
                    child: const Icon(Icons.family_restroom_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: childUnread > 0,
                    label: Text('$childUnread'),
                    child: const Icon(Icons.family_restroom_rounded),
                  ),
                  label: '家人圈',
                ),
              ],
            )
          : null,
    );
  }
}

enum _AdultPage { quick, familyCircle }

enum _FamilyHandoffAction { invitedFamily, manager, acceptInvitation }

enum _ParentAction { quick, familyCircle, privacy }

class _ParentMenu extends StatelessWidget {
  const _ParentMenu({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        30 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('家人怎麼參與？', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 5),
          const Text(
            '只做三件事：留一句、回一個表情、保護家庭資料。',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          _ParentActionTile(
            icon: Icons.auto_stories_rounded,
            color: AppColors.coral,
            title: '用幾行話留一張短句',
            subtitle: '本機模板先整理，家人確認原句後才保存',
            onTap: () => Navigator.pop(context, _ParentAction.quick),
          ),
          const SizedBox(height: 10),
          _ParentActionTile(
            icon: Icons.add_reaction_outlined,
            color: AppColors.berry,
            title: unreadCount == 0 ? '回應孩子的故事卡' : '回應孩子的故事卡（$unreadCount）',
            subtitle: '加一個貼圖，或留一句讓孩子下次看到',
            onTap: () => Navigator.pop(context, _ParentAction.familyCircle),
          ),
          const SizedBox(height: 10),
          _ParentActionTile(
            icon: Icons.shield_outlined,
            color: AppColors.jade,
            title: '隱私與家庭資料',
            subtitle: '匯出或清除保存在這個裝置的內容',
            onTap: () => Navigator.pop(context, _ParentAction.privacy),
          ),
        ],
      ),
    );
  }
}

class _ParentActionTile extends StatelessWidget {
  const _ParentActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .12),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorySeedIntentSheet extends StatelessWidget {
  const _StorySeedIntentSheet({
    required this.idea,
    required this.childName,
  });

  final StoryIdea idea;
  final String childName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('story-seed-intent-${idea.id}'),
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        26 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.sunSoft,
                foregroundColor: AppColors.coral,
                child: Icon(Icons.looks_one_rounded),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$childName的第一棒',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '先選今天真正想說的「${idea.title}」故事。',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final choice in idea.choices) ...[
            FilledButton.tonalIcon(
              key: ValueKey('story-seed-choice-${idea.id}-${choice.id}'),
              onPressed: () => Navigator.pop(context, choice),
              style: FilledButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(62),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(
                choice.label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 17, color: AppColors.muted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '選擇只保存在這台裝置；家人接棒前仍會要求管理碼。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
