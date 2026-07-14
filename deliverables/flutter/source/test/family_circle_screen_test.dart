import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/core/app_theme.dart';
import 'package:hometongue_tags/models/conversation_episode.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/models/family_invitation.dart';
import 'package:hometongue_tags/screens/family_circle_screen.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';
import 'package:hometongue_tags/services/family_invitation_crypto.dart';
import 'package:hometongue_tags/services/local_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 7, 13, 5);

  Future<FamilyCircleStore> circleWithFamily() async {
    final store = await FamilyCircleStore.load(
      storage: MemoryFamilyCircleStorage(),
      clock: () => now,
    );
    await store.bootstrapAdult(
      FamilyMember(
        id: 'grandma',
        relationship: '外婆',
        nickname: '阿嬤',
        isAdult: true,
        avatarEmoji: 'elder-woman',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      ),
    );
    await store.inviteMember(
      actorMemberId: 'grandma',
      member: FamilyMember(
        id: 'child',
        relationship: '孩子',
        nickname: '小米',
        isAdult: false,
        avatarEmoji: 'child',
        roleColorValue: 0xFFDDEEFF,
        createdAt: now,
      ),
    );
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    return store;
  }

  FamilyCircleStoryCard storyCard() => FamilyCircleStoryCard(
        id: 'homecoming-card',
        episode: '放學回家',
        createdByMemberId: 'child',
        childMemberId: 'child',
        childChoice: '我回來了。',
        childUtterance: 'Cháu về rồi ạ.',
        sceneOutcome: '門打開了',
        createdAt: now.add(const Duration(minutes: 1)),
      );

  testWidgets(
    'latest local reactions and recorded replies appear before story cards',
    (tester) async {
      final store = await circleWithFamily();
      await store.addStoryCard(
        actorMemberId: 'child',
        card: storyCard(),
      );
      await store.addOrReplaceReaction(
        actorMemberId: 'grandma',
        cardId: 'homecoming-card',
        sticker: FamilySticker.proud,
        at: now.add(const Duration(minutes: 2)),
      );
      await store.appendContinuation(
        actorMemberId: 'grandma',
        cardId: 'homecoming-card',
        continuation: AdultStoryContinuation(
          id: 'reply-1',
          adultMemberId: 'grandma',
          kind: StoryContinuationKind.familyNote,
          text: '明天再說一個新故事給阿嬤聽！',
          createdAt: now.add(const Duration(minutes: 3)),
          localRecordingReference: 'idb://family/reply-1.webm',
        ),
      );
      final media = _SilentMediaService();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: FamilyCircleScreen(
              store: store,
              viewerMemberId: 'child',
              childMemberId: 'child',
              media: media,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('family-activity-feed')), findsOneWidget);
      expect(find.text('這台裝置上的最新互動'), findsOneWidget);
      expect(find.text('1 張未讀'), findsOneWidget);
      expect(find.text('阿嬤 留了一句'), findsOneWidget);
      expect(find.text('明天再說一個新故事給阿嬤聽！'), findsWidgets);
      expect(find.text('阿嬤 送來「以你為榮」'), findsOneWidget);

      final outerList = find.byKey(const ValueKey('child-family-circle'));
      final storyCardFinder =
          find.byKey(const ValueKey('family-card-homecoming-card'));
      for (var attempt = 0;
          attempt < 4 && storyCardFinder.evaluate().isEmpty;
          attempt++) {
        await tester.drag(outerList, const Offset(0, -100));
        await tester.pumpAndSettle();
      }

      final feedTop = tester.getTopLeft(
        find.byKey(const ValueKey('family-activity-feed')),
      );
      final storyTop = tester.getTopLeft(storyCardFinder);
      expect(feedTop.dy, lessThan(storyTop.dy));

      await tester.tap(
        find.byKey(
          const ValueKey('play-activity-continuation-reply-1'),
        ),
      );
      await tester.pump();
      expect(media.played, ['idb://family/reply-1.webm']);

      await tester.tap(
        find.byKey(
          const ValueKey('family-activity-continuation-reply-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.unreadCardsFor('child'), isEmpty);
      expect(find.byKey(const ValueKey('family-unread-count')), findsNothing);
      expect(
        find.byKey(
          const ValueKey('family-activity-unread-continuation-reply-1'),
        ),
        findsNothing,
      );
      expect(find.text('本機家庭圈'), findsWidgets);
    },
  );

  testWidgets('empty activity feed does not pretend another device replied',
      (tester) async {
    final store = await circleWithFamily();
    final media = _SilentMediaService();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'child',
            childMemberId: 'child',
            media: media,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-activity-empty')), findsOneWidget);
    expect(find.textContaining('這台裝置留下表情或一句話'), findsOneWidget);
    expect(find.textContaining('即時'), findsNothing);
    expect(find.textContaining('同步'), findsNothing);
    expect(
      find.byKey(const ValueKey('family-story-chapter-progress')),
      findsOneWidget,
    );
    expect(find.text('0/3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-chapter-complete')),
      findsNothing,
    );
  });

  testWidgets('pending adult stays out of the child member list',
      (tester) async {
    final store = await circleWithFamily();
    await store.createAdultInvitationPackage(
      actorMemberId: 'grandma',
      invitedAdult: FamilyMember(
        id: 'grandpa',
        relationship: '外公',
        nickname: '阿公',
        isAdult: true,
        avatarEmoji: 'elder-man',
        roleColorValue: 0xFFDCEDE8,
        createdAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'child',
            childMemberId: 'child',
            media: _SilentMediaService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阿公'), findsNothing);
    expect(
      find.byKey(const ValueKey('pending-family-invitations')),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'grandma',
            childMemberId: 'child',
            media: _SilentMediaService(),
            adultActions: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-family-invitations')),
      findsNothing,
    );
    await _expandAdultTools(tester);
    expect(
      find.byKey(const ValueKey('pending-family-invitations')),
      findsOneWidget,
    );
    expect(find.text('阿公'), findsOneWidget);
    expect(find.textContaining('回覆以前'), findsOneWidget);
  });

  testWidgets('adult invitation UI requires a signed receipt before approval',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await circleWithFamily();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'grandma',
            childMemberId: 'child',
            media: _SilentMediaService(),
            adultActions: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandAdultTools(tester);
    final addMember = find.byKey(const ValueKey('add-family-member'));
    await tester.scrollUntilVisible(
      addMember,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(addMember);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('family-member-nickname')),
      '阿公',
    );
    await tester.enterText(
      find.byKey(const ValueKey('family-member-relationship')),
      '外公',
    );
    await tester.tap(find.widgetWithText(FilledButton, '做一份邀請包'));
    await tester.pumpAndSettle();

    final packageText = tester.widget<SelectableText>(
      find.byKey(const ValueKey('adult-invitation-package-output')),
    );
    final package = packageText.data!;
    expect(package, isNot(contains('storyCards')));
    expect(
        store.members
            .where((member) => member.nickname == '阿公')
            .single
            .isApproved,
        isFalse);
    await tester.tap(find.text('關閉（遺失就重做）'));
    await tester.pumpAndSettle();

    final receipt = await FamilyCircleStore.acceptAdultInvitationPackage(
      package,
      pin: '135790',
      clock: () => now,
      invitationCrypto: _FastInvitationAcceptanceCrypto(),
    );
    final importReceipt =
        find.byKey(const ValueKey('import-adult-invitation-receipt'));
    await tester.scrollUntilVisible(
      importReceipt,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(importReceipt);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('adult-invitation-receipt-input')),
      receipt,
    );
    await tester.tap(
      find.byKey(const ValueKey('approve-adult-invitation-receipt')),
    );
    await tester.pumpAndSettle();

    final grandpa =
        store.members.where((member) => member.nickname == '阿公').single;
    expect(grandpa.isApproved, isTrue);
    expect(store.memberHasIndividualPin(grandpa.id), isTrue);
    expect(store.pendingAdultInvitations, isEmpty);
    expect(find.textContaining('家人已正式加入'), findsOneWidget);
  });

  testWidgets('partial family chapter stays optional and leaves story visible',
      (tester) async {
    final store = await circleWithFamily();
    await store.addStoryCard(
      actorMemberId: 'child',
      card: storyCard(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'child',
            childMemberId: 'child',
            media: _SilentMediaService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-chapter-complete')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('family-card-homecoming-card')),
      findsOneWidget,
    );

    final chapter = find.byKey(const ValueKey('family-story-chapter-progress'));
    await tester.ensureVisible(chapter);
    await tester.tap(chapter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('family-chapter-task-story')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('family-chapter-task-voice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('family-chapter-task-memory')),
      findsOneWidget,
    );
    expect(find.textContaining('不影響孩子繼續玩'), findsOneWidget);
  });

  testWidgets('complete family chapter requires story recording and memory',
      (tester) async {
    final store = await circleWithFamily();
    await store.addStoryCard(
      actorMemberId: 'child',
      card: storyCard(),
    );
    await store.upsertEpisodeVoice(
      actorMemberId: 'grandma',
      voice: FamilyEpisodeVoice(
        episodeId: ConversationEpisodeCatalog.homecoming.id,
        promptId: ConversationEpisodeCatalog.homecoming.openingPromptId,
        adultMemberId: 'grandma',
        targetText: 'Cháu về rồi à?',
        translationZh: '你回來了嗎？',
        romanization: 'Cháu về rồi à?',
        updatedAt: now.add(const Duration(minutes: 2)),
        localRecordingReference: 'idb://family/chapter-voice.webm',
      ),
    );
    await store.appendContinuation(
      actorMemberId: 'grandma',
      cardId: 'homecoming-card',
      continuation: AdultStoryContinuation(
        id: 'chapter-memory',
        adultMemberId: 'grandma',
        kind: StoryContinuationKind.familyNote,
        text: '阿嬤小時候回家，也會先說這一句。',
        createdAt: now.add(const Duration(minutes: 3)),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'child',
            childMemberId: 'child',
            media: _SilentMediaService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3/3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-chapter-complete')),
      findsOneWidget,
    );
    expect(find.text('家庭故事章完成'), findsOneWidget);

    final outerList = find.byKey(const ValueKey('child-family-circle'));
    final storyCardFinder =
        find.byKey(const ValueKey('family-card-homecoming-card'));
    for (var attempt = 0;
        attempt < 6 && storyCardFinder.evaluate().isEmpty;
        attempt++) {
      await tester.drag(outerList, const Offset(0, -100));
      await tester.pumpAndSettle();
    }
    expect(
      storyCardFinder,
      findsOneWidget,
    );

    final chapter = find.byKey(const ValueKey('family-story-chapter-progress'));
    await tester.ensureVisible(chapter);
    await tester.tap(chapter);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('family-chapter-task-story')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('family-chapter-task-voice')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('family-chapter-task-memory')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('adult voice studio exposes every prompt across three turns',
      (tester) async {
    final store = await circleWithFamily();
    final media = _SilentMediaService();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FamilyCircleScreen(
            store: store,
            viewerMemberId: 'grandma',
            childMemberId: 'child',
            media: media,
            adultActions: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('family-voice-studio')),
      findsNothing,
    );
    await _expandAdultTools(tester);
    final studio = find.byKey(const ValueKey('family-voice-studio'));
    expect(studio, findsOneWidget);

    final episode = ConversationEpisodeCatalog.homecoming;
    final episodeTile =
        find.byKey(ValueKey('family-voice-episode-${episode.id}'));
    await tester.ensureVisible(episodeTile);
    await tester.pumpAndSettle();
    await tester.tap(episodeTile);
    await tester.pumpAndSettle();

    expect(find.text('第 1 回合'), findsOneWidget);
    expect(find.text('第 2 回合'), findsOneWidget);
    expect(find.text('第 3 回合'), findsOneWidget);
    for (final prompt in episode.prompts) {
      expect(
        find.byKey(
          ValueKey('edit-family-voice-${episode.id}-${prompt.id}'),
        ),
        findsOneWidget,
        reason: prompt.id,
      );
    }
  });
}

Future<void> _expandAdultTools(WidgetTester tester) async {
  final disclosure = find.byKey(const ValueKey('family-tools-disclosure'));
  await tester.ensureVisible(disclosure);
  await tester.pumpAndSettle();
  await tester.tap(disclosure);
  await tester.pumpAndSettle();
}

class _FastInvitationAcceptanceCrypto extends FamilyInvitationCrypto {
  @override
  Future<FamilyMemberPinCredential> derivePinCredential({
    required String memberId,
    required String pin,
    required DateTime createdAt,
  }) async {
    return FamilyMemberPinCredential(
      memberId: memberId,
      algorithm: FamilyMemberPinCredential.supportedAlgorithm,
      iterations: FamilyMemberPinCredential.requiredIterations,
      saltBase64: base64UrlEncode(List<int>.filled(16, 1)),
      verifierBase64: base64UrlEncode(List<int>.filled(32, 2)),
      createdAt: createdAt,
    );
  }
}

class _SilentMediaService extends LocalMediaService {
  final List<String> played = [];

  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    played.add(path);
  }

  @override
  Future<void> dispose() async {}
}
