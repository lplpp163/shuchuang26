import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/conversation_episode.dart' as theater;
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 7, 13, 3);
  late MemoryFamilyCircleStorage storage;
  late FamilyCircleStore store;

  FamilyMember adult({
    String id = 'grandma',
    String relationship = '外婆',
    String nickname = '阿嬤',
  }) {
    return FamilyMember(
      id: id,
      relationship: relationship,
      nickname: nickname,
      isAdult: true,
      avatarEmoji: '👵',
      roleColorValue: 0xFFFF8A65,
      createdAt: now,
    );
  }

  FamilyMember child({
    String id = 'child',
    String relationship = '外孫',
    String nickname = '小安',
  }) {
    return FamilyMember(
      id: id,
      relationship: relationship,
      nickname: nickname,
      isAdult: false,
      avatarEmoji: '🧒',
      roleColorValue: 0xFF5C9DED,
      createdAt: now,
    );
  }

  FamilyCircleStoryCard homecomingCard({
    String id = 'card-homecoming',
    String createdBy = 'child',
    String childId = 'child',
    String? relayId,
    String? familyRecordingReference,
  }) {
    return FamilyCircleStoryCard(
      id: id,
      episode: '放學回家',
      createdByMemberId: createdBy,
      childMemberId: childId,
      childChoice: '跟外婆打招呼',
      childUtterance: 'Con chào bà.',
      sceneOutcome: '門打開了，外婆笑著歡迎孩子回家。',
      createdAt: now,
      localRecordingReference: 'idb://family/card-homecoming.webm',
      relayId: relayId,
      familyRecordingReference: familyRecordingReference,
    );
  }

  setUp(() async {
    storage = MemoryFamilyCircleStorage();
    store = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
    );
    await store.bootstrapAdult(adult());
  });

  test('portable model JSON clears recording references without mutating data',
      () {
    final continuation = AdultStoryContinuation(
      id: 'continue-with-audio',
      adultMemberId: 'grandma',
      kind: StoryContinuationKind.nextLine,
      text: 'Bà chào con.',
      createdAt: now,
      localRecordingReference: 'idb://family/grandma-reply.webm',
    );
    final card = homecomingCard().copyWith(continuations: [continuation]);

    final localJson = card.toJson();
    final portableJson = card.toJson(includeLocalRecordingReferences: false);

    expect(
      localJson['localRecordingReference'],
      'idb://family/card-homecoming.webm',
    );
    expect(portableJson['localRecordingReference'], isNull);
    final portableContinuation =
        (portableJson['continuations'] as List<dynamic>).single
            as Map<String, Object?>;
    expect(portableContinuation['localRecordingReference'], isNull);
    expect(card.localRecordingReference, isNotNull);
    expect(card.continuations.single.localRecordingReference, isNotNull);
  });

  test(
      'relay card round-trip keeps baton identity but portable JSON strips audio',
      () {
    final card = FamilyCircleStoryCard(
      id: 'relay-club-1',
      episode: '社團',
      createdByMemberId: 'child',
      childMemberId: 'child',
      childChoice: '我今天第一次參加社團。',
      childUtterance: 'Hôm nay con tham gia câu lạc bộ.',
      sceneOutcome: '孩子接住家人確認過的社團短句。',
      createdAt: now,
      localRecordingReference: 'idb://family/child-club.webm',
      relayId: 'relay-record-club-1',
      familyRecordingReference: 'idb://family/grandma-club.webm',
    );

    final restored = FamilyCircleStoryCard.fromJson(card.toJson());
    expect(restored.relayId, 'relay-record-club-1');
    expect(
      restored.familyRecordingReference,
      'idb://family/grandma-club.webm',
    );
    expect(restored.localRecordingReference, 'idb://family/child-club.webm');

    final portable = card.toJson(includeLocalRecordingReferences: false);
    expect(portable['relayId'], 'relay-record-club-1');
    expect(portable['familyRecordingReference'], isNull);
    expect(portable['localRecordingReference'], isNull);
    expect(card.familyRecordingReference, isNotNull);
    expect(card.localRecordingReference, isNotNull);
  });

  test('episode family voice persists locally and exports only portable text',
      () async {
    const recording = 'media://episode-homecoming-grandma';
    await store.upsertEpisodeVoice(
      actorMemberId: 'grandma',
      voice: FamilyEpisodeVoice(
        episodeId: 'theater-homecoming',
        adultMemberId: 'grandma',
        targetText: 'Con về rồi nè.',
        translationZh: '我回來囉。',
        romanization: 'con / về rồi / nè',
        updatedAt: now,
        localRecordingReference: recording,
      ),
    );
    await store.upsertEpisodeVoice(
      actorMemberId: 'grandma',
      voice: FamilyEpisodeVoice(
        episodeId: 'theater-homecoming',
        promptId: 'home-happy-day',
        adultMemberId: 'grandma',
        targetText: 'Hôm nay vui không con?',
        translationZh: '今天開心嗎？',
        romanization: 'hôm nay / vui không con',
        updatedAt: now,
        localRecordingReference: 'media://episode-homecoming-happy',
      ),
    );

    expect(
      store.episodeVoiceFor('theater-homecoming')?.localRecordingReference,
      recording,
    );
    expect(
      store
          .episodeVoiceFor(
            'theater-homecoming',
            promptId: 'home-happy-day',
          )
          ?.targetText,
      'Hôm nay vui không con?',
    );
    expect(store.episodeVoicesFor('theater-homecoming'), hasLength(2));
    final persisted = jsonDecode(storage.value!) as Map<String, dynamic>;
    final persistedVoices = (persisted['episodeVoices'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final persistedVoice = persistedVoices.singleWhere(
      (voice) => voice['promptId'] == null,
    );
    expect(persistedVoice['localRecordingReference'], recording);
    final legacyVoiceJson = Map<String, Object?>.from(persistedVoice)
      ..remove('promptId');
    expect(FamilyEpisodeVoice.fromJson(legacyVoiceJson).promptId, isNull);
    expect(
      persistedVoices.singleWhere(
        (voice) => voice['promptId'] == 'home-happy-day',
      )['localRecordingReference'],
      'media://episode-homecoming-happy',
    );

    final portable = jsonDecode(store.exportJson()) as Map<String, dynamic>;
    final portableVoices = (portable['episodeVoices'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final portableVoice = portableVoices.singleWhere(
      (voice) => voice['promptId'] == null,
    );
    expect(portableVoice['targetText'], 'Con về rồi nè.');
    expect(
      portableVoices.map((voice) => voice['localRecordingReference']),
      everyElement(isNull),
    );

    final reloaded = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
    );
    expect(
      reloaded.episodeVoiceFor('theater-homecoming')?.targetText,
      'Con về rồi nè.',
    );
    expect(
      reloaded.episodeVoiceFor('theater-homecoming')?.localRecordingReference,
      recording,
    );
    expect(
      reloaded
          .episodeVoiceFor(
            'theater-homecoming',
            promptId: 'home-happy-day',
          )
          ?.localRecordingReference,
      'media://episode-homecoming-happy',
    );
  });

  test('pending members cannot enter until an approved adult approves them',
      () async {
    await store.inviteMember(actorMemberId: 'grandma', member: child());

    expect(store.memberById('child')?.isApproved, isFalse);
    expect(
      () => store.addStoryCard(
        actorMemberId: 'child',
        card: homecomingCard(),
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
    expect(
      () => store.approveMember(
        actorMemberId: 'child',
        memberId: 'child',
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );

    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    expect(store.memberById('child')?.isApproved, isTrue);
    expect(store.memberById('child')?.approvedByMemberId, 'grandma');

    await store.addStoryCard(
      actorMemberId: 'child',
      card: homecomingCard(),
    );
    expect(store.cards, hasLength(1));
  });

  test('story card supports unread, one limited sticker and adult continuation',
      () async {
    await store.inviteMember(actorMemberId: 'grandma', member: child());
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    await store.addStoryCard(
      actorMemberId: 'child',
      card: homecomingCard(),
    );

    expect(store.unreadCardsFor('grandma'), hasLength(1));
    expect(store.unreadCardsFor('child'), isEmpty);

    await store.addOrReplaceReaction(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
      sticker: FamilySticker.heart,
    );
    await store.addOrReplaceReaction(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
      sticker: FamilySticker.proud,
    );
    expect(store.cardById('card-homecoming')?.reactions, hasLength(1));
    expect(
      store.cardById('card-homecoming')?.reactions.single.sticker,
      FamilySticker.proud,
    );
    expect(store.unreadCardsFor('grandma'), isEmpty);
    expect(store.unreadCardsFor('child'), hasLength(1));

    await store.markRead(
      actorMemberId: 'child',
      cardId: 'card-homecoming',
    );
    expect(store.unreadCardsFor('child'), isEmpty);

    final continuation = AdultStoryContinuation(
      id: 'continue-1',
      adultMemberId: 'grandma',
      kind: StoryContinuationKind.familyNote,
      text: '下次見面，把今天學校最開心的事告訴外婆。',
      createdAt: now,
    );
    await store.appendContinuation(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
      continuation: continuation,
    );
    expect(
      store.cardById('card-homecoming')?.continuations.single.text,
      contains('下次見面'),
    );
    expect(store.unreadCardsFor('child'), hasLength(1));

    await store.retractReaction(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
    );
    expect(store.cardById('card-homecoming')?.reactions, isEmpty);
  });

  test('children cannot forge adult continuations or delete another card',
      () async {
    await store.inviteMember(actorMemberId: 'grandma', member: child());
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    await store.inviteMember(
      actorMemberId: 'grandma',
      member: child(id: 'sibling', nickname: '小美'),
    );
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'sibling',
    );
    await store.addStoryCard(
      actorMemberId: 'child',
      card: homecomingCard(),
    );

    final forgedContinuation = AdultStoryContinuation(
      id: 'forged',
      adultMemberId: 'grandma',
      kind: StoryContinuationKind.nextLine,
      text: '外婆說的下一句',
      createdAt: now,
    );
    expect(
      () => store.appendContinuation(
        actorMemberId: 'child',
        cardId: 'card-homecoming',
        continuation: forgedContinuation,
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
    expect(
      () => store.deleteStoryCard(
        actorMemberId: 'sibling',
        cardId: 'card-homecoming',
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );

    await store.deleteStoryCard(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
    );
    expect(store.cards, isEmpty);
  });

  test('adult can revoke an added role and its reactions are removed',
      () async {
    await store.inviteMember(actorMemberId: 'grandma', member: child());
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    final invitation = await store.createAdultInvitationPackage(
      actorMemberId: 'grandma',
      invitedAdult: adult(id: 'uncle', relationship: '舅舅', nickname: '阿明舅舅'),
    );
    final receipt = await FamilyCircleStore.acceptAdultInvitationPackage(
      invitation,
      pin: '135790',
      clock: () => now,
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'grandma',
      source: receipt,
    );
    await store.addStoryCard(
      actorMemberId: 'child',
      card: homecomingCard(),
    );
    await store.addOrReplaceReaction(
      actorMemberId: 'uncle',
      cardId: 'card-homecoming',
      sticker: FamilySticker.proud,
    );

    await store.removeMember(
      actorMemberId: 'grandma',
      memberId: 'uncle',
    );

    expect(store.memberById('uncle'), isNull);
    expect(store.cards.single.reactions, isEmpty);
    expect(
      () => store.removeMember(
        actorMemberId: 'grandma',
        memberId: 'grandma',
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
  });

  test(
      'portable JSON round-trip keeps social state but clears device recording references',
      () async {
    await store.inviteMember(actorMemberId: 'grandma', member: child());
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    await store.addStoryCard(
      actorMemberId: 'child',
      card: homecomingCard(
        relayId: 'relay-homecoming-1',
        familyRecordingReference: 'idb://family/grandma-relay.webm',
      ),
    );
    await store.addOrReplaceReaction(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
      sticker: FamilySticker.hug,
    );
    await store.appendContinuation(
      actorMemberId: 'grandma',
      cardId: 'card-homecoming',
      continuation: AdultStoryContinuation(
        id: 'continue-1',
        adultMemberId: 'grandma',
        kind: StoryContinuationKind.nextLine,
        text: 'Bà chào con.',
        createdAt: now,
        localRecordingReference: 'idb://family/grandma-next-line.webm',
      ),
    );

    final exported = store.exportJson();
    final json = jsonDecode(exported) as Map<String, dynamic>;
    expect(json['schema'], FamilyCircleStore.schema);
    expect(json['scope'], 'local-private-family-circle');
    expect(json['localOnlyNotice'], contains('沒有遠端同步'));
    expect(json['localOnlyNotice'], contains('不含錄音檔'));
    expect(exported, isNot(contains('publicFeed')));
    expect(exported, isNot(contains('directMessage')));
    expect(exported, isNot(contains('idb://')));
    final exportedCard =
        (json['storyCards'] as List<dynamic>).single as Map<String, dynamic>;
    expect(exportedCard['relayId'], 'relay-homecoming-1');
    expect(exportedCard['localRecordingReference'], isNull);
    expect(exportedCard['familyRecordingReference'], isNull);
    final exportedContinuation =
        (exportedCard['continuations'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(exportedContinuation['localRecordingReference'], isNull);

    final persisted = jsonDecode(storage.value!) as Map<String, dynamic>;
    final persistedCard = (persisted['storyCards'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(
      persistedCard['localRecordingReference'],
      'idb://family/card-homecoming.webm',
    );
    expect(persistedCard['relayId'], 'relay-homecoming-1');
    expect(
      persistedCard['familyRecordingReference'],
      'idb://family/grandma-relay.webm',
    );
    expect(
      ((persistedCard['continuations'] as List<dynamic>).single
          as Map<String, dynamic>)['localRecordingReference'],
      'idb://family/grandma-next-line.webm',
    );

    final restoredStorage = MemoryFamilyCircleStorage();
    final restored = await FamilyCircleStore.load(
      storage: restoredStorage,
      clock: () => now,
    );
    await restored.importJson(exported);

    expect(restored.members, hasLength(2));
    expect(restored.cards, hasLength(1));
    final card = restored.cards.single;
    expect(card.childUtterance, 'Con chào bà.');
    expect(card.relayId, 'relay-homecoming-1');
    expect(card.localRecordingReference, isNull);
    expect(card.familyRecordingReference, isNull);
    expect(card.reactions.single.sticker, FamilySticker.hug);
    expect(card.continuations.single.kind, StoryContinuationKind.nextLine);
    expect(
      card.continuations.single.localRecordingReference,
      isNull,
    );

    final reloaded = await FamilyCircleStore.load(
      storage: restoredStorage,
      clock: () => now,
    );
    expect(reloaded.exportJson(), restored.exportJson());
  });

  test('conversation theater card keeps its complete three-turn choice path',
      () async {
    final theaterCard = theater.ConversationStoryCard(
      id: 'theater-card-1',
      episodeId: 'theater-homecoming',
      title: '放學回家',
      elderName: '外婆',
      completedAt: now,
      endingTitleZh: '先送外婆一個大抱抱',
      endingEmoji: '🫂',
      moments: const [
        theater.ConversationStoryMoment(
          choiceId: 'came-home',
          emoji: '🙋🏻',
          childLine: 'Cháu về rồi ạ.',
          translationZh: '我回來了。',
          storyBeatZh: '門打開了。',
          transcript: 'Cháu về rồi ạ',
        ),
        theater.ConversationStoryMoment(
          choiceId: 'happy-today',
          emoji: '😄',
          childLine: 'Hôm nay vui ạ.',
          translationZh: '今天很開心。',
          storyBeatZh: '快樂冒出小星星。',
        ),
        theater.ConversationStoryMoment(
          choiceId: 'hug-first',
          emoji: '🫂',
          childLine: 'Cháu ôm bà trước ạ.',
          translationZh: '我想先抱抱外婆。',
          storyBeatZh: '屋裡變得暖暖的。',
        ),
      ],
    );
    final familyCard = FamilyCircleStoryCard.fromConversationCard(
      theaterCard,
      createdByMemberId: 'child',
      childMemberId: 'child',
      localRecordingReference: 'idb://family/theater-card-1.webm',
    );

    expect(familyCard.episode, 'theater-homecoming');
    expect(familyCard.childUtterance, 'Cháu ôm bà trước ạ.');
    expect(familyCard.sourceConversationCard?.moments, hasLength(3));

    final roundTrip = FamilyCircleStoryCard.fromJson(familyCard.toJson());
    expect(roundTrip.sourceConversationCard?.title, '放學回家');
    expect(
      roundTrip.sourceConversationCard?.moments
          .map((moment) => moment.choiceId),
      ['came-home', 'happy-today', 'hug-first'],
    );
    expect(
      roundTrip.sourceConversationCard?.moments.first.transcript,
      'Cháu về rồi ạ',
    );
  });

  test('successful persisted mutations notify listeners exactly once',
      () async {
    var notifications = 0;
    store.addListener(() => notifications += 1);

    await store.inviteMember(actorMemberId: 'grandma', member: child());
    expect(notifications, 1);
    await store.approveMember(
      actorMemberId: 'grandma',
      memberId: 'child',
    );
    expect(notifications, 2);

    expect(
      () => store.addStoryCard(
        actorMemberId: 'unknown',
        card: homecomingCard(),
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
    expect(notifications, 2);
  });

  test('invalid import is rejected without replacing current local data',
      () async {
    final before = store.exportJson();
    final invalid = jsonDecode(before) as Map<String, dynamic>;
    final members = invalid['members'] as List<dynamic>;
    (members.single as Map<String, dynamic>)['approvedByMemberId'] = 'stranger';

    expect(
      () => store.importJson(
        jsonEncode(invalid),
        actorMemberId: 'grandma',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(store.exportJson(), before);
    expect(storage.value, before);
  });

  test('default storage is on-device SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final localStore = await FamilyCircleStore.load(clock: () => now);
    await localStore.bootstrapAdult(adult());

    final reloaded = await FamilyCircleStore.load(clock: () => now);
    expect(reloaded.memberById('grandma')?.nickname, '阿嬤');
    expect(reloaded.cards, isEmpty);

    await reloaded.deleteLocalCircle(actorMemberId: 'grandma');
    final empty = await FamilyCircleStore.load(clock: () => now);
    expect(empty.members, isEmpty);
  });
}
