import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/models/family_invitation.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime.utc(2026, 7, 13, 8);

  FamilyMember owner() => FamilyMember(
        id: 'owner',
        relationship: '外婆',
        nickname: '阿嬤',
        isAdult: true,
        avatarEmoji: 'elder-woman',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      );

  FamilyMember invitedAdult(String id) => FamilyMember(
        id: id,
        relationship: '阿姨',
        nickname: id == 'aunt' ? '小阿姨' : '大阿姨',
        isAdult: true,
        avatarEmoji: 'adult-woman',
        roleColorValue: 0xFFDDEEFF,
        createdAt: now,
      );

  Future<FamilyCircleStore> createStore(
    MemoryFamilyCircleStorage storage,
  ) async {
    final store = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
      circleId: 'circle-home',
      displayName: '我們家',
    );
    if (store.members.isEmpty) await store.bootstrapAdult(owner());
    return store;
  }

  Future<String> issueAndAccept(
    FamilyCircleStore store, {
    required String memberId,
    required String pin,
  }) async {
    final package = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult(memberId),
    );
    return FamilyCircleStore.acceptAdultInvitationPackage(
      package,
      pin: pin,
      clock: () => now,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 7, 13, 8);
  });

  test('legacy direct member APIs cannot bypass adult acceptance', () async {
    final store = await createStore(MemoryFamilyCircleStorage());

    expect(
      () => store.inviteMember(
        actorMemberId: 'owner',
        member: invitedAdult('aunt'),
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
    expect(store.memberById('aunt'), isNull);
  });

  test('invited adult cannot use family-manager write operations', () async {
    final storage = MemoryFamilyCircleStorage();
    final store = await createStore(storage);
    final auntReceipt = await issueAndAccept(
      store,
      memberId: 'aunt',
      pin: '246810',
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: auntReceipt,
    );
    final child = FamilyMember(
      id: 'child',
      relationship: '孩子',
      nickname: '小米',
      isAdult: false,
      avatarEmoji: 'child',
      roleColorValue: 0xFFFFE5DE,
      createdAt: now,
    );
    await store.inviteMember(actorMemberId: 'owner', member: child);
    final unclePackage = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('uncle'),
    );
    final uncleInvitationId =
        FamilyInvitationPackage.decode(unclePackage).invitationId;
    final portableBackup = store.exportJson();

    Future<void> expectManagerOnly(Future<void> Function() action) async {
      await expectLater(
        action,
        throwsA(
          isA<FamilyCircleAccessException>().having(
            (error) => error.message,
            'message',
            contains('家庭管理者'),
          ),
        ),
      );
    }

    await expectManagerOnly(
      () => store.inviteMember(
        actorMemberId: 'aunt',
        member: FamilyMember(
          id: 'other-child',
          relationship: '孩子',
          nickname: '小華',
          isAdult: false,
          avatarEmoji: 'child',
          roleColorValue: 0xFFDDEEFF,
          createdAt: now,
        ),
      ),
    );
    await expectManagerOnly(
      () async {
        await store.createAdultInvitationPackage(
          actorMemberId: 'aunt',
          invitedAdult: invitedAdult('other-aunt'),
        );
      },
    );
    await expectManagerOnly(
      () => store.approveMember(
        actorMemberId: 'aunt',
        memberId: 'child',
      ),
    );
    await expectManagerOnly(
      () => store.revokeAdultInvitation(
        actorMemberId: 'aunt',
        invitationId: uncleInvitationId,
      ),
    );
    await expectManagerOnly(
      () => store.removeMember(
        actorMemberId: 'aunt',
        memberId: 'owner',
      ),
    );
    await expectManagerOnly(
      () => store.removeMember(
        actorMemberId: 'aunt',
        memberId: 'child',
      ),
    );
    await expectManagerOnly(
      () => store.importJson(
        portableBackup,
        actorMemberId: 'aunt',
      ),
    );
    await expectManagerOnly(
      () => store.deleteLocalCircle(actorMemberId: 'aunt'),
    );

    expect(store.managerMemberId, 'owner');
    expect(store.memberById('owner')?.isApproved, isTrue);
    expect(store.memberById('child')?.isApproved, isFalse);
    expect(store.pendingAdultInvitations, hasLength(1));
    expect(storage.value, isNotNull);
  });

  test('legacy snapshot derives and persists the self-approved manager',
      () async {
    final storage = MemoryFamilyCircleStorage();
    var store = await createStore(storage);
    final legacy = jsonDecode(storage.value!) as Map<String, dynamic>;
    final circle = Map<String, dynamic>.from(
      legacy['circle'] as Map<String, dynamic>,
    )..remove('managerMemberId');
    legacy['circle'] = circle;
    storage.value = jsonEncode(legacy);

    store = await FamilyCircleStore.load(storage: storage, clock: () => now);
    expect(store.managerMemberId, 'owner');
    await store.inviteMember(
      actorMemberId: 'owner',
      member: FamilyMember(
        id: 'child',
        relationship: '孩子',
        nickname: '小米',
        isAdult: false,
        avatarEmoji: 'child',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      ),
    );

    final migrated = jsonDecode(storage.value!) as Map<String, dynamic>;
    expect(
      (migrated['circle'] as Map<String, dynamic>)['managerMemberId'],
      'owner',
    );
  });

  test('portable import cannot replace the current family manager', () async {
    final store = await createStore(MemoryFamilyCircleStorage());
    final tampered = jsonDecode(store.exportJson()) as Map<String, dynamic>;
    final attacker = invitedAdult('attacker').approve(
      approvedByMemberId: 'attacker',
      approvedAt: now,
    );
    (tampered['members'] as List<Object?>).add(attacker.toJson());
    (tampered['circle'] as Map<String, dynamic>)['managerMemberId'] =
        'attacker';

    expect(
      () => store.importJson(
        jsonEncode(tampered),
        actorMemberId: 'owner',
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );
    expect(store.managerMemberId, 'owner');
    expect(store.memberById('attacker'), isNull);
  });

  test(
      'manual package and signed receipt approve once without exposing PIN or family data',
      () async {
    final storage = MemoryFamilyCircleStorage();
    final store = await createStore(storage);

    final packageSource = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('aunt'),
    );
    final package = FamilyInvitationPackage.decode(packageSource);
    final packageJson = jsonDecode(packageSource) as Map<String, dynamic>;
    final persistedBeforeAccept =
        jsonDecode(storage.value!) as Map<String, dynamic>;

    expect(package.circleId, 'circle-home');
    expect(package.invitedAdult.id, 'aunt');
    expect(base64Url.decode(package.tokenBase64), hasLength(32));
    expect(packageJson.keys, containsAll(['schema', 'scope', 'invitation']));
    expect(packageSource, isNot(contains('246810')));
    expect(packageSource, isNot(contains('storyCards')));
    expect(packageSource, isNot(contains('episodeVoices')));
    expect(packageSource, isNot(contains('localRecordingReference')));
    expect(storage.value, isNot(contains(package.tokenBase64)));
    expect(persistedBeforeAccept['pendingAdultInvitations'], hasLength(1));
    expect(store.memberById('aunt')?.isApproved, isFalse);

    expect(
      () => store.approveMember(
        actorMemberId: 'owner',
        memberId: 'aunt',
      ),
      throwsA(isA<FamilyCircleAccessException>()),
    );

    final receiptSource = await FamilyCircleStore.acceptAdultInvitationPackage(
      packageSource,
      pin: '246810',
      clock: () => now,
    );
    final receipt = FamilyInvitationReceipt.decode(receiptSource);
    final receiptJson = jsonDecode(receiptSource) as Map<String, dynamic>;

    expect(receipt.pinCredential.algorithm, 'pbkdf2-hmac-sha256');
    expect(receipt.pinCredential.iterations, 600000);
    expect(receiptSource, isNot(contains('246810')));
    expect(receiptSource, isNot(contains('storyCards')));
    expect(receiptSource, isNot(contains('episodeVoices')));
    expect(receiptSource, isNot(contains('localRecordingReference')));
    expect(receiptJson.keys, containsAll(['schema', 'receipt', 'signature']));

    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: receiptSource,
    );
    expect(store.memberById('aunt')?.isApproved, isTrue);
    expect(store.memberHasIndividualPin('aunt'), isTrue);
    expect(store.pendingAdultInvitations, isEmpty);

    final verified = await store.verifyMemberPin(
      memberId: 'aunt',
      pin: '246810',
    );
    expect(verified.status, FamilyMemberPinVerificationStatus.verified);
    expect(verified.remainingAttempts, 5);

    expect(
      () => store.importAdultInvitationReceipt(
        actorMemberId: 'owner',
        source: receiptSource,
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.used,
        ),
      ),
    );
  });

  test(
      'expired wrong-circle and tampered receipts are rejected without approval',
      () async {
    final store = await createStore(MemoryFamilyCircleStorage());
    final package = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('aunt'),
      validFor: const Duration(minutes: 10),
    );
    final receipt = await FamilyCircleStore.acceptAdultInvitationPackage(
      package,
      pin: '246810',
      clock: () => now,
    );

    final wrongCircle =
        Map<String, dynamic>.from(jsonDecode(receipt) as Map<String, dynamic>);
    final wrongCircleBody = Map<String, dynamic>.from(
      wrongCircle['receipt'] as Map<String, dynamic>,
    )..['circleId'] = 'another-circle';
    wrongCircle['receipt'] = wrongCircleBody;
    expect(
      () => store.importAdultInvitationReceipt(
        actorMemberId: 'owner',
        source: jsonEncode(wrongCircle),
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.wrongCircle,
        ),
      ),
    );

    final tampered =
        Map<String, dynamic>.from(jsonDecode(receipt) as Map<String, dynamic>);
    final tamperedBody = Map<String, dynamic>.from(
      tampered['receipt'] as Map<String, dynamic>,
    );
    final credential = Map<String, dynamic>.from(
      tamperedBody['pinCredential'] as Map<String, dynamic>,
    );
    final verifier = base64Url.decode(credential['verifier'] as String);
    verifier[0] ^= 0x01;
    credential['verifier'] = base64UrlEncode(verifier);
    tamperedBody['pinCredential'] = credential;
    tampered['receipt'] = tamperedBody;
    expect(
      () => store.importAdultInvitationReceipt(
        actorMemberId: 'owner',
        source: jsonEncode(tampered),
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.tampered,
        ),
      ),
    );
    expect(store.memberById('aunt')?.isApproved, isFalse);

    now = now.add(const Duration(minutes: 11));
    expect(
      () => store.importAdultInvitationReceipt(
        actorMemberId: 'owner',
        source: receipt,
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.expired,
        ),
      ),
    );
  });

  test('tampered package and four-digit invited PIN are rejected', () async {
    final store = await createStore(MemoryFamilyCircleStorage());
    final package = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('aunt'),
    );

    expect(
      () => FamilyCircleStore.acceptAdultInvitationPackage(
        package,
        pin: '1234',
        clock: () => now,
      ),
      throwsArgumentError,
    );

    final tampered =
        Map<String, dynamic>.from(jsonDecode(package) as Map<String, dynamic>);
    final invitation = Map<String, dynamic>.from(
      tampered['invitation'] as Map<String, dynamic>,
    );
    final publicKey = base64Url.decode(invitation['publicKey'] as String);
    publicKey[0] ^= 0x01;
    invitation['publicKey'] = base64UrlEncode(publicKey);
    tampered['invitation'] = invitation;
    expect(
      () => FamilyCircleStore.acceptAdultInvitationPackage(
        jsonEncode(tampered),
        pin: '246810',
        clock: () => now,
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.tampered,
        ),
      ),
    );
  });

  test('member PIN retries are isolated persisted and clear after timeout',
      () async {
    final storage = MemoryFamilyCircleStorage();
    var store = await createStore(storage);
    final auntReceipt = await issueAndAccept(
      store,
      memberId: 'aunt',
      pin: '246810',
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: auntReceipt,
    );
    final uncleReceipt = await issueAndAccept(
      store,
      memberId: 'uncle',
      pin: '135790',
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: uncleReceipt,
    );

    FamilyMemberPinVerification result = const FamilyMemberPinVerification(
      status: FamilyMemberPinVerificationStatus.unavailable,
      remainingAttempts: 0,
    );
    for (var attempt = 0; attempt < 5; attempt++) {
      result = await store.verifyMemberPin(memberId: 'aunt', pin: '000000');
    }
    expect(result.status, FamilyMemberPinVerificationStatus.locked);
    expect(result.remainingAttempts, 0);
    expect(result.lockedUntil, now.add(const Duration(seconds: 30)));

    final otherAdult = await store.verifyMemberPin(
      memberId: 'uncle',
      pin: '135790',
    );
    expect(otherAdult.status, FamilyMemberPinVerificationStatus.verified);

    store = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
    );
    final stillLocked = await store.verifyMemberPin(
      memberId: 'aunt',
      pin: '246810',
    );
    expect(stillLocked.status, FamilyMemberPinVerificationStatus.locked);

    now = now.add(const Duration(seconds: 31));
    final recovered = await store.verifyMemberPin(
      memberId: 'aunt',
      pin: '246810',
    );
    expect(recovered.status, FamilyMemberPinVerificationStatus.verified);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('portable export strips credentials invitations and retry state',
      () async {
    final storage = MemoryFamilyCircleStorage();
    final store = await createStore(storage);
    final receipt = await issueAndAccept(
      store,
      memberId: 'aunt',
      pin: '246810',
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: receipt,
    );
    await store.verifyMemberPin(memberId: 'aunt', pin: '000000');
    await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('uncle'),
    );

    final local = jsonDecode(storage.value!) as Map<String, dynamic>;
    expect(local['memberPinCredentials'], isNotEmpty);
    expect(local['pendingAdultInvitations'], isNotEmpty);
    expect(local['consumedAdultInvitations'], isNotEmpty);
    expect(local['memberPinAttemptStates'], isNotEmpty);

    final portableSource = store.exportJson();
    final portable = jsonDecode(portableSource) as Map<String, dynamic>;
    expect(portable, isNot(contains('memberPinCredentials')));
    expect(portable, isNot(contains('pendingAdultInvitations')));
    expect(portable, isNot(contains('consumedAdultInvitations')));
    expect(portable, isNot(contains('memberPinAttemptStates')));
    for (final privateKey in const [
      'token',
      'verifier',
      'salt',
      'publicKey',
    ]) {
      expect(_allKeys(portable), isNot(contains(privateKey)));
    }
    expect(portableSource, isNot(contains('246810')));

    final restored = await FamilyCircleStore.load(
      storage: MemoryFamilyCircleStorage(portableSource),
      clock: () => now,
    );
    expect(restored.memberHasIndividualPin('aunt'), isFalse);
    expect(restored.pendingAdultInvitations, isEmpty);
    expect(restored.memberById('aunt')?.isApproved, isTrue);
  });

  test('revoking invite or removing member clears local security state',
      () async {
    final storage = MemoryFamilyCircleStorage();
    final store = await createStore(storage);
    final package = await store.createAdultInvitationPackage(
      actorMemberId: 'owner',
      invitedAdult: invitedAdult('aunt'),
    );
    final invitationId = FamilyInvitationPackage.decode(package).invitationId;
    final receipt = await FamilyCircleStore.acceptAdultInvitationPackage(
      package,
      pin: '246810',
      clock: () => now,
    );

    await store.revokeAdultInvitation(
      actorMemberId: 'owner',
      invitationId: invitationId,
    );
    expect(store.memberById('aunt'), isNull);
    expect(store.pendingAdultInvitations, isEmpty);
    expect(
      () => store.importAdultInvitationReceipt(
        actorMemberId: 'owner',
        source: receipt,
      ),
      throwsA(
        isA<FamilyInvitationException>().having(
          (error) => error.failure,
          'failure',
          FamilyInvitationFailure.revoked,
        ),
      ),
    );

    final accepted = await issueAndAccept(
      store,
      memberId: 'aunt',
      pin: '246810',
    );
    await store.importAdultInvitationReceipt(
      actorMemberId: 'owner',
      source: accepted,
    );
    await store.verifyMemberPin(memberId: 'aunt', pin: '000000');
    await store.removeMember(actorMemberId: 'owner', memberId: 'aunt');
    final persisted = jsonDecode(storage.value!) as Map<String, dynamic>;
    expect(store.memberHasIndividualPin('aunt'), isFalse);
    expect(persisted['memberPinCredentials'], isNull);
    expect(persisted['consumedAdultInvitations'], isNull);
    expect(persisted['memberPinAttemptStates'], isNull);
  });
}

Set<String> _allKeys(Object? value) {
  final keys = <String>{};
  void visit(Object? item) {
    if (item is Map) {
      for (final entry in item.entries) {
        keys.add('${entry.key}');
        visit(entry.value);
      }
    } else if (item is Iterable) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return keys;
}
