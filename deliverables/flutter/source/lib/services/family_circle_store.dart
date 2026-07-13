import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_circle.dart';
import '../models/family_invitation.dart';
import 'family_invitation_crypto.dart';

typedef FamilyCircleClock = DateTime Function();

abstract interface class FamilyCircleStorage {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

/// Default on-device persistence. This is intentionally not a sync service.
class SharedPreferencesFamilyCircleStorage implements FamilyCircleStorage {
  const SharedPreferencesFamilyCircleStorage({
    this.key = 'hometongue.family-circle.v1',
  });

  final String key;

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, value);
    if (!saved) throw StateError('家庭圈無法儲存在這台裝置上。');
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    final cleared = await preferences.remove(key);
    if (!cleared && preferences.containsKey(key)) {
      throw StateError('無法刪除這台裝置上的家庭圈。');
    }
  }
}

/// Small deterministic storage useful for tests, demos and dependency injection.
class MemoryFamilyCircleStorage implements FamilyCircleStorage {
  MemoryFamilyCircleStorage([this.value]);

  String? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class FamilyCircleAccessException implements Exception {
  const FamilyCircleAccessException(this.message);

  final String message;

  @override
  String toString() => 'FamilyCircleAccessException: $message';
}

enum FamilyInvitationFailure {
  invalid,
  expired,
  used,
  wrongCircle,
  tampered,
  revoked,
}

class FamilyInvitationException implements Exception {
  const FamilyInvitationException(this.failure, this.message);

  final FamilyInvitationFailure failure;
  final String message;

  @override
  String toString() => 'FamilyInvitationException: $message';
}

class FamilyCircleStore extends ChangeNotifier {
  FamilyCircleStore._({
    required FamilyCircleStorage storage,
    required FamilyCircleClock clock,
    required String circleId,
    required String displayName,
    required DateTime createdAt,
    required String? managerMemberId,
    required List<FamilyMember> members,
    required List<FamilyCircleStoryCard> cards,
    required List<FamilyEpisodeVoice> episodeVoices,
    required List<FamilyMemberPinCredential> memberPinCredentials,
    required List<PendingAdultInvitation> pendingAdultInvitations,
    required List<ConsumedAdultInvitation> consumedAdultInvitations,
    required List<FamilyMemberPinAttemptState> memberPinAttemptStates,
    required FamilyInvitationCrypto invitationCrypto,
  })  : _storage = storage,
        _clock = clock,
        _invitationCrypto = invitationCrypto,
        _circleId = circleId,
        _displayName = displayName,
        _createdAt = createdAt,
        _managerMemberId = managerMemberId,
        _members = members,
        _cards = cards,
        _episodeVoices = episodeVoices,
        _memberPinCredentials = memberPinCredentials,
        _pendingAdultInvitations = pendingAdultInvitations,
        _consumedAdultInvitations = consumedAdultInvitations,
        _memberPinAttemptStates = memberPinAttemptStates;

  static const schema = 'hometongue-family-circle-v1';
  static const localOnlyNotice =
      '目前只儲存在這台裝置；沒有遠端同步、公開動態、私訊或排行榜。資料包不含錄音檔或這台裝置的錄音位置。';

  final FamilyCircleStorage _storage;
  final FamilyCircleClock _clock;
  final FamilyInvitationCrypto _invitationCrypto;
  String _circleId;
  String _displayName;
  DateTime _createdAt;
  String? _managerMemberId;
  List<FamilyMember> _members;
  List<FamilyCircleStoryCard> _cards;
  List<FamilyEpisodeVoice> _episodeVoices;
  List<FamilyMemberPinCredential> _memberPinCredentials;
  List<PendingAdultInvitation> _pendingAdultInvitations;
  List<ConsumedAdultInvitation> _consumedAdultInvitations;
  List<FamilyMemberPinAttemptState> _memberPinAttemptStates;
  final Map<String, Future<void>> _memberPinVerificationQueues = {};

  String get circleId => _circleId;
  String get displayName => _displayName;
  DateTime get createdAt => _createdAt;
  String? get managerMemberId => _managerMemberId;
  List<FamilyMember> get members => List.unmodifiable(_members);
  List<FamilyCircleStoryCard> get cards => List.unmodifiable(_cards);
  List<FamilyEpisodeVoice> get episodeVoices =>
      List.unmodifiable(_episodeVoices);
  List<PendingAdultInvitation> get pendingAdultInvitations =>
      List.unmodifiable(_pendingAdultInvitations);

  bool memberHasIndividualPin(String memberId) => _memberPinCredentials
      .any((credential) => credential.memberId == memberId);

  static Future<FamilyCircleStore> load({
    FamilyCircleStorage? storage,
    FamilyCircleClock? clock,
    FamilyInvitationCrypto? invitationCrypto,
    String circleId = 'local-family',
    String displayName = '我們家',
  }) async {
    final effectiveStorage =
        storage ?? const SharedPreferencesFamilyCircleStorage();
    final effectiveClock = clock ?? DateTime.now;
    final effectiveInvitationCrypto =
        invitationCrypto ?? FamilyInvitationCrypto();
    final raw = await effectiveStorage.read();
    if (raw == null || raw.trim().isEmpty) {
      return FamilyCircleStore._(
        storage: effectiveStorage,
        clock: effectiveClock,
        circleId: circleId,
        displayName: displayName,
        createdAt: effectiveClock(),
        managerMemberId: null,
        members: [],
        cards: [],
        episodeVoices: [],
        memberPinCredentials: [],
        pendingAdultInvitations: [],
        consumedAdultInvitations: [],
        memberPinAttemptStates: [],
        invitationCrypto: effectiveInvitationCrypto,
      );
    }

    final snapshot = _decodeSnapshot(raw);
    _validateSnapshot(snapshot);
    return FamilyCircleStore._(
      storage: effectiveStorage,
      clock: effectiveClock,
      circleId: snapshot.circleId,
      displayName: snapshot.displayName,
      createdAt: snapshot.createdAt,
      managerMemberId: snapshot.managerMemberId,
      members: snapshot.members,
      cards: snapshot.cards,
      episodeVoices: snapshot.episodeVoices,
      memberPinCredentials: snapshot.memberPinCredentials,
      pendingAdultInvitations: snapshot.pendingAdultInvitations,
      consumedAdultInvitations: snapshot.consumedAdultInvitations,
      memberPinAttemptStates: snapshot.memberPinAttemptStates,
      invitationCrypto: effectiveInvitationCrypto,
    );
  }

  FamilyMember? memberById(String memberId) {
    for (final member in _members) {
      if (member.id == memberId) return member;
    }
    return null;
  }

  FamilyCircleStoryCard? cardById(String cardId) {
    for (final card in _cards) {
      if (card.id == cardId) return card;
    }
    return null;
  }

  FamilyEpisodeVoice? episodeVoiceFor(
    String episodeId, {
    String? promptId,
  }) {
    for (final voice in _episodeVoices) {
      if (voice.episodeId == episodeId && voice.promptId == promptId) {
        return voice;
      }
    }
    return null;
  }

  List<FamilyEpisodeVoice> episodeVoicesFor(String episodeId) =>
      List.unmodifiable(
        _episodeVoices.where((voice) => voice.episodeId == episodeId),
      );

  Future<void> bootstrapAdult(FamilyMember member) async {
    if (_members.isNotEmpty) {
      throw StateError('家庭圈已建立，請由已核准成人邀請新成員。');
    }
    _validateMemberBasics(member);
    if (!member.isAdult) {
      throw ArgumentError('第一位成員必須是負責核准的成人。');
    }
    final approved = member.approve(
      approvedByMemberId: member.id,
      approvedAt: member.approvedAt ?? _clock(),
    );
    await _commit(
      members: [approved],
      cards: _cards,
      managerMemberId: approved.id,
    );
  }

  Future<void> inviteMember({
    required String actorMemberId,
    required FamilyMember member,
  }) async {
    _requireCircleManager(actorMemberId);
    _validateMemberBasics(member);
    if (member.isAdult) {
      throw const FamilyCircleAccessException(
        '成人家人必須使用一次性邀請包，由本人接受後再核准。',
      );
    }
    if (member.isApproved) {
      throw ArgumentError('邀請的新成員不得自行標記為已核准。');
    }
    if (memberById(member.id) != null) {
      throw StateError('家庭成員 ID 已存在：${member.id}');
    }
    await _commit(members: [..._members, member], cards: _cards);
  }

  /// Creates a manually shared, one-time invitation package for an adult.
  ///
  /// The returned JSON contains the private signing token exactly once. Only
  /// the corresponding public key is persisted in this circle.
  Future<String> createAdultInvitationPackage({
    required String actorMemberId,
    required FamilyMember invitedAdult,
    Duration validFor = const Duration(hours: 24),
  }) async {
    _requireCircleManager(actorMemberId);
    _validateMemberBasics(invitedAdult);
    if (!invitedAdult.isAdult) {
      throw ArgumentError('手動邀請包只能邀請成人家人。');
    }
    if (invitedAdult.isApproved) {
      throw ArgumentError('受邀成人必須先保持待核准狀態。');
    }
    if (memberById(invitedAdult.id) != null) {
      throw StateError('家庭成員 ID 已存在：${invitedAdult.id}');
    }
    if (validFor <= Duration.zero || validFor > const Duration(days: 7)) {
      throw ArgumentError('家庭邀請期限必須大於零且不超過七天。');
    }

    final now = _clock();
    final expiresAt = now.add(validFor);
    final invitationId = _invitationCrypto.randomId();
    final keyMaterial = await _invitationCrypto.createInvitationKeyMaterial();
    final pending = PendingAdultInvitation(
      id: invitationId,
      circleId: _circleId,
      memberId: invitedAdult.id,
      createdByMemberId: actorMemberId,
      issuedAt: now,
      expiresAt: expiresAt,
      publicKeyBase64: keyMaterial.publicKeyBase64,
    );
    final package = FamilyInvitationPackage(
      invitationId: invitationId,
      circleId: _circleId,
      circleDisplayName: _displayName,
      invitedAdult: invitedAdult,
      issuedAt: now,
      expiresAt: expiresAt,
      publicKeyBase64: keyMaterial.publicKeyBase64,
      tokenBase64: keyMaterial.tokenBase64,
    );
    await _commit(
      members: [..._members, invitedAdult],
      cards: _cards,
      pendingAdultInvitations: [..._pendingAdultInvitations, pending],
    );
    return package.encode();
  }

  /// Runs on the invited adult's device and produces a signed acceptance
  /// receipt. It does not import stories or claim that a cloud account exists.
  static Future<String> acceptAdultInvitationPackage(
    String source, {
    required String pin,
    FamilyCircleClock? clock,
    FamilyInvitationCrypto? invitationCrypto,
  }) async {
    final effectiveClock = clock ?? DateTime.now;
    final crypto = invitationCrypto ?? FamilyInvitationCrypto();
    final package = FamilyInvitationPackage.decode(source);
    final now = effectiveClock();
    if (!package.invitedAdult.isAdult || package.invitedAdult.isApproved) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.invalid,
        '邀請包裡的成人角色狀態不正確。',
      );
    }
    if (!package.expiresAt.isAfter(package.issuedAt)) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.invalid,
        '邀請包的期限不正確。',
      );
    }
    if (now.isAfter(package.expiresAt)) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.expired,
        '這份家庭邀請已過期。',
      );
    }
    final derivedPublicKey =
        await crypto.publicKeyForToken(package.tokenBase64);
    if (derivedPublicKey != package.publicKeyBase64) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.tampered,
        '家庭邀請包的安全資訊不一致。',
      );
    }
    final credential = await crypto.derivePinCredential(
      memberId: package.invitedAdult.id,
      pin: pin,
      createdAt: now,
    );
    final unsigned = FamilyInvitationReceipt(
      invitationId: package.invitationId,
      circleId: package.circleId,
      memberId: package.invitedAdult.id,
      acceptedAt: now,
      pinCredential: credential,
      signatureBase64: 'pending',
    );
    final signature = await crypto.signReceipt(
      unsigned,
      package.tokenBase64,
    );
    return unsigned.withSignature(signature).encode();
  }

  /// Verifies a signed receipt on the original device and only then approves
  /// the invited adult. Successful invitations are consumed atomically.
  Future<void> importAdultInvitationReceipt({
    required String actorMemberId,
    required String source,
  }) async {
    _requireCircleManager(actorMemberId);
    final receipt = FamilyInvitationReceipt.decode(source);
    if (_consumedAdultInvitations
        .any((invitation) => invitation.id == receipt.invitationId)) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.used,
        '這份家庭邀請已經使用過。',
      );
    }
    PendingAdultInvitation? pending;
    for (final invitation in _pendingAdultInvitations) {
      if (invitation.id == receipt.invitationId) {
        pending = invitation;
        break;
      }
    }
    if (pending == null) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.revoked,
        '找不到可用的家庭邀請，可能已撤銷。',
      );
    }
    final invitation = pending;
    final now = _clock();
    if (now.isAfter(invitation.expiresAt)) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.expired,
        '這份家庭邀請已過期。',
      );
    }
    if (receipt.circleId != _circleId || invitation.circleId != _circleId) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.wrongCircle,
        '這份接受回條不屬於目前的家庭圈。',
      );
    }
    if (receipt.memberId != invitation.memberId ||
        receipt.pinCredential.memberId != invitation.memberId) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.tampered,
        '接受回條的家庭成員不一致。',
      );
    }
    if (receipt.acceptedAt.isBefore(invitation.issuedAt) ||
        receipt.acceptedAt.isAfter(invitation.expiresAt) ||
        receipt.acceptedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.tampered,
        '接受回條的時間不合理。',
      );
    }
    _invitationCrypto.validatePinCredential(receipt.pinCredential);
    final signatureIsValid = await _invitationCrypto.verifyReceipt(
      receipt,
      invitation.publicKeyBase64,
    );
    if (!signatureIsValid) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.tampered,
        '接受回條簽章不正確。',
      );
    }
    final memberIndex =
        _members.indexWhere((member) => member.id == invitation.memberId);
    if (memberIndex < 0 ||
        _members[memberIndex].isApproved ||
        !_members[memberIndex].isAdult) {
      throw const FamilyInvitationException(
        FamilyInvitationFailure.invalid,
        '受邀成人的待核准狀態不正確。',
      );
    }

    final nextMembers = [..._members];
    nextMembers[memberIndex] = nextMembers[memberIndex].approve(
      approvedByMemberId: actorMemberId,
      approvedAt: now,
    );
    final nextCredentials = _memberPinCredentials
        .where((credential) => credential.memberId != invitation.memberId)
        .toList()
      ..add(receipt.pinCredential);
    final nextPending = _pendingAdultInvitations
        .where((item) => item.id != invitation.id)
        .toList(growable: false);
    final nextConsumed = [
      ..._consumedAdultInvitations,
      ConsumedAdultInvitation(
        id: invitation.id,
        memberId: invitation.memberId,
        consumedAt: now,
      ),
    ];
    await _commit(
      members: nextMembers,
      cards: _cards,
      memberPinCredentials: nextCredentials,
      pendingAdultInvitations: nextPending,
      consumedAdultInvitations: nextConsumed,
      memberPinAttemptStates: _memberPinAttemptStates
          .where((state) => state.memberId != invitation.memberId)
          .toList(growable: false),
    );
  }

  Future<void> revokeAdultInvitation({
    required String actorMemberId,
    required String invitationId,
  }) async {
    _requireCircleManager(actorMemberId);
    PendingAdultInvitation? pending;
    for (final invitation in _pendingAdultInvitations) {
      if (invitation.id == invitationId) {
        pending = invitation;
        break;
      }
    }
    if (pending == null) {
      final used = _consumedAdultInvitations
          .any((invitation) => invitation.id == invitationId);
      throw FamilyInvitationException(
        used ? FamilyInvitationFailure.used : FamilyInvitationFailure.revoked,
        used ? '這份家庭邀請已經使用過。' : '找不到可撤銷的家庭邀請。',
      );
    }
    final memberId = pending.memberId;
    await _commit(
      members: _members
          .where((member) => member.id != memberId || member.isApproved)
          .toList(growable: false),
      cards: _cards,
      memberPinCredentials: _memberPinCredentials
          .where((credential) => credential.memberId != memberId)
          .toList(growable: false),
      pendingAdultInvitations: _pendingAdultInvitations
          .where((invitation) => invitation.id != invitationId)
          .toList(growable: false),
      memberPinAttemptStates: _memberPinAttemptStates
          .where((state) => state.memberId != memberId)
          .toList(growable: false),
    );
  }

  /// Verifies one invited adult independently with persistent per-member
  /// retry state. The bootstrap owner intentionally has no individual PIN.
  Future<FamilyMemberPinVerification> verifyMemberPin({
    required String memberId,
    required String pin,
  }) {
    final result = Completer<FamilyMemberPinVerification>();
    final previous = _memberPinVerificationQueues[memberId] ?? Future.value();
    final current = previous.then((_) async {
      try {
        result.complete(
          await _verifyMemberPinSerial(memberId: memberId, pin: pin),
        );
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _memberPinVerificationQueues[memberId] = current;
    unawaited(
      current.whenComplete(() {
        if (identical(_memberPinVerificationQueues[memberId], current)) {
          _memberPinVerificationQueues.remove(memberId);
        }
      }),
    );
    return result.future;
  }

  Future<FamilyMemberPinVerification> _verifyMemberPinSerial({
    required String memberId,
    required String pin,
  }) async {
    FamilyMemberPinCredential? credential;
    for (final item in _memberPinCredentials) {
      if (item.memberId == memberId) {
        credential = item;
        break;
      }
    }
    if (credential == null) {
      return const FamilyMemberPinVerification(
        status: FamilyMemberPinVerificationStatus.unavailable,
        remainingAttempts: 0,
      );
    }
    if (!RegExp(FamilyInvitationCrypto.pinPattern).hasMatch(pin)) {
      return const FamilyMemberPinVerification(
        status: FamilyMemberPinVerificationStatus.invalidFormat,
        remainingAttempts: 5,
      );
    }
    final now = _clock();
    FamilyMemberPinAttemptState? current;
    for (final state in _memberPinAttemptStates) {
      if (state.memberId == memberId) {
        current = state;
        break;
      }
    }
    if (current?.lockedUntil case final lockedUntil?
        when now.isBefore(lockedUntil)) {
      return FamilyMemberPinVerification(
        status: FamilyMemberPinVerificationStatus.locked,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
      );
    }
    final effectiveFailures =
        current?.lockedUntil != null ? 0 : current?.failedAttempts ?? 0;
    final matches = await _invitationCrypto.verifyPin(pin, credential);
    if (matches) {
      await _commit(
        members: _members,
        cards: _cards,
        memberPinAttemptStates: _memberPinAttemptStates
            .where((state) => state.memberId != memberId)
            .toList(growable: false),
      );
      return const FamilyMemberPinVerification(
        status: FamilyMemberPinVerificationStatus.verified,
        remainingAttempts: 5,
      );
    }

    final failedAttempts = effectiveFailures + 1;
    final lockedUntil =
        failedAttempts >= 5 ? now.add(const Duration(seconds: 30)) : null;
    final nextState = FamilyMemberPinAttemptState(
      memberId: memberId,
      failedAttempts: failedAttempts,
      lockedUntil: lockedUntil,
    );
    await _commit(
      members: _members,
      cards: _cards,
      memberPinAttemptStates: [
        ..._memberPinAttemptStates.where((state) => state.memberId != memberId),
        nextState,
      ],
    );
    return FamilyMemberPinVerification(
      status: lockedUntil == null
          ? FamilyMemberPinVerificationStatus.incorrect
          : FamilyMemberPinVerificationStatus.locked,
      remainingAttempts: (5 - failedAttempts).clamp(0, 5),
      lockedUntil: lockedUntil,
    );
  }

  Future<void> approveMember({
    required String actorMemberId,
    required String memberId,
  }) async {
    _requireCircleManager(actorMemberId);
    final index = _members.indexWhere((member) => member.id == memberId);
    if (index < 0) throw StateError('找不到要核准的家庭成員。');
    if (_members[index].isApproved) return;
    if (_members[index].isAdult) {
      throw const FamilyCircleAccessException(
        '成人家人必須帶回本人簽署的接受回條，不能直接核准。',
      );
    }
    if (_pendingAdultInvitations
        .any((invitation) => invitation.memberId == memberId)) {
      throw const FamilyCircleAccessException('這位受邀成人必須先帶回已簽署的接受回條。');
    }

    final nextMembers = [..._members];
    nextMembers[index] = _members[index].approve(
      approvedByMemberId: actorMemberId,
      approvedAt: _clock(),
    );
    await _commit(members: nextMembers, cards: _cards);
  }

  Future<void> removeMember({
    required String actorMemberId,
    required String memberId,
  }) async {
    _requireCircleManager(actorMemberId);
    if (actorMemberId == memberId) {
      throw const FamilyCircleAccessException('家庭圈管理者不能移除自己。');
    }
    final target = memberById(memberId);
    if (target == null) throw StateError('找不到要移除的家庭成員。');
    if (_cards.any((card) => card.childMemberId == memberId)) {
      throw const FamilyCircleAccessException('先刪除這位孩子的故事卡，才能移除角色。');
    }

    final nextMembers = _members
        .where((member) => member.id != memberId)
        .toList(growable: false);
    final nextCards = _cards
        .map(
          (card) => card.copyWith(
            reactions: card.reactions
                .where((reaction) => reaction.memberId != memberId)
                .toList(growable: false),
            continuations: card.continuations
                .where((continuation) => continuation.adultMemberId != memberId)
                .toList(growable: false),
            readByMemberIds: card.readByMemberIds
                .where((readerId) => readerId != memberId)
                .toSet(),
          ),
        )
        .toList(growable: false);
    final nextVoices = _episodeVoices
        .where((voice) => voice.adultMemberId != memberId)
        .toList(growable: false);
    await _commit(
      members: nextMembers,
      cards: nextCards,
      episodeVoices: nextVoices,
      memberPinCredentials: _memberPinCredentials
          .where((credential) => credential.memberId != memberId)
          .toList(growable: false),
      pendingAdultInvitations: _pendingAdultInvitations
          .where((invitation) => invitation.memberId != memberId)
          .toList(growable: false),
      consumedAdultInvitations: _consumedAdultInvitations
          .where((invitation) => invitation.memberId != memberId)
          .toList(growable: false),
      memberPinAttemptStates: _memberPinAttemptStates
          .where((state) => state.memberId != memberId)
          .toList(growable: false),
    );
  }

  Future<void> addStoryCard({
    required String actorMemberId,
    required FamilyCircleStoryCard card,
  }) async {
    _requireApprovedMember(actorMemberId);
    if (card.createdByMemberId != actorMemberId) {
      throw const FamilyCircleAccessException('不能冒用其他家庭成員建立故事卡。');
    }
    if (cardById(card.id) != null) {
      throw StateError('家庭故事卡 ID 已存在：${card.id}');
    }
    final child = _requireApprovedMember(card.childMemberId);
    if (child.isAdult) {
      throw ArgumentError('childMemberId 必須指向已核准的孩子。');
    }
    if (card.reactions.isNotEmpty || card.continuations.isNotEmpty) {
      throw ArgumentError('新故事卡不得預先冒用家人的貼圖或追加內容。');
    }

    final normalized = card.copyWith(
      reactions: const [],
      continuations: const [],
      readByMemberIds: {actorMemberId, card.childMemberId},
    );
    _validateCard(normalized, _approvedMembersById(_members));
    await _commit(members: _members, cards: [normalized, ..._cards]);
  }

  Future<void> addOrReplaceReaction({
    required String actorMemberId,
    required String cardId,
    required FamilySticker sticker,
    DateTime? at,
  }) async {
    _requireApprovedMember(actorMemberId);
    final cardIndex = _requiredCardIndex(cardId);
    final card = _cards[cardIndex];
    final reactions = card.reactions
        .where((reaction) => reaction.memberId != actorMemberId)
        .toList();
    reactions.add(
      FamilyStickerReaction(
        memberId: actorMemberId,
        sticker: sticker,
        createdAt: at ?? _clock(),
      ),
    );
    // A new family response is new content: everyone except its author should
    // see the card as unread again.
    final readBy = {actorMemberId};
    await _replaceCard(
      cardIndex,
      card.copyWith(reactions: reactions, readByMemberIds: readBy),
    );
  }

  Future<void> retractReaction({
    required String actorMemberId,
    required String cardId,
  }) async {
    _requireApprovedMember(actorMemberId);
    final cardIndex = _requiredCardIndex(cardId);
    final card = _cards[cardIndex];
    final reactions = card.reactions
        .where((reaction) => reaction.memberId != actorMemberId)
        .toList();
    if (reactions.length == card.reactions.length) return;
    await _replaceCard(
      cardIndex,
      card.copyWith(
        reactions: reactions,
        readByMemberIds: {actorMemberId},
      ),
    );
  }

  Future<void> appendContinuation({
    required String actorMemberId,
    required String cardId,
    required AdultStoryContinuation continuation,
  }) async {
    _requireApprovedAdult(actorMemberId);
    if (continuation.adultMemberId != actorMemberId) {
      throw const FamilyCircleAccessException('不能冒用其他成人追加故事。');
    }
    if (continuation.text.trim().isEmpty) {
      throw ArgumentError('家人留下的話不能是空白。');
    }
    final duplicate = _cards.any(
      (card) => card.continuations.any((item) => item.id == continuation.id),
    );
    if (duplicate) throw StateError('故事追加 ID 已存在。');

    final cardIndex = _requiredCardIndex(cardId);
    final card = _cards[cardIndex];
    await _replaceCard(
      cardIndex,
      card.copyWith(
        continuations: [...card.continuations, continuation],
        readByMemberIds: {actorMemberId},
      ),
    );
  }

  Future<void> markRead({
    required String actorMemberId,
    required String cardId,
  }) async {
    _requireApprovedMember(actorMemberId);
    final cardIndex = _requiredCardIndex(cardId);
    final card = _cards[cardIndex];
    if (card.readByMemberIds.contains(actorMemberId)) return;
    await _replaceCard(
      cardIndex,
      card.copyWith(
        readByMemberIds: {...card.readByMemberIds, actorMemberId},
      ),
    );
  }

  List<FamilyCircleStoryCard> unreadCardsFor(String actorMemberId) {
    _requireApprovedMember(actorMemberId);
    return List.unmodifiable(
      _cards.where((card) => card.isUnreadFor(actorMemberId)),
    );
  }

  Future<void> deleteStoryCard({
    required String actorMemberId,
    required String cardId,
  }) async {
    final actor = _requireApprovedMember(actorMemberId);
    final cardIndex = _requiredCardIndex(cardId);
    final card = _cards[cardIndex];
    if (!actor.isAdult && card.createdByMemberId != actorMemberId) {
      throw const FamilyCircleAccessException(
        '只有卡片建立者或已核准成人可以刪除這張故事卡。',
      );
    }
    final nextCards = [..._cards]..removeAt(cardIndex);
    await _commit(members: _members, cards: nextCards);
  }

  Future<void> upsertEpisodeVoice({
    required String actorMemberId,
    required FamilyEpisodeVoice voice,
  }) async {
    _requireApprovedAdult(actorMemberId);
    if (voice.adultMemberId != actorMemberId) {
      throw const FamilyCircleAccessException('不能冒用其他家人設定家庭原音。');
    }
    final existing = episodeVoiceFor(
      voice.episodeId,
      promptId: voice.promptId,
    );
    if (existing != null && existing.adultMemberId != actorMemberId) {
      throw const FamilyCircleAccessException('不能覆蓋其他家人留下的家庭原音。');
    }
    _validateEpisodeVoice(voice, _approvedMembersById(_members));
    final nextVoices = _episodeVoices
        .where(
          (item) =>
              item.episodeId != voice.episodeId ||
              item.promptId != voice.promptId,
        )
        .toList();
    nextVoices.add(voice);
    await _commit(
      members: _members,
      cards: _cards,
      episodeVoices: nextVoices,
    );
  }

  Future<void> removeEpisodeVoice({
    required String actorMemberId,
    required String episodeId,
    String? promptId,
  }) async {
    _requireApprovedAdult(actorMemberId);
    final existing = episodeVoiceFor(episodeId, promptId: promptId);
    if (existing == null) return;
    if (existing.adultMemberId != actorMemberId) {
      throw const FamilyCircleAccessException('不能移除其他家人留下的家庭原音。');
    }
    final nextVoices = _episodeVoices
        .where(
          (voice) => voice.episodeId != episodeId || voice.promptId != promptId,
        )
        .toList(growable: false);
    if (nextVoices.length == _episodeVoices.length) return;
    await _commit(
      members: _members,
      cards: _cards,
      episodeVoices: nextVoices,
    );
  }

  String exportJson() => jsonEncode(
        _snapshotJson(
          circleId: _circleId,
          displayName: _displayName,
          createdAt: _createdAt,
          managerMemberId: _managerMemberId,
          members: _members,
          cards: _cards,
          episodeVoices: _episodeVoices,
          includeLocalRecordingReferences: false,
          includePrivateSecurityState: false,
          memberPinCredentials: _memberPinCredentials,
          pendingAdultInvitations: _pendingAdultInvitations,
          consumedAdultInvitations: _consumedAdultInvitations,
          memberPinAttemptStates: _memberPinAttemptStates,
        ),
      );

  /// Replaces the complete local circle with a validated local backup.
  ///
  /// An existing circle requires an approved adult. An empty device can restore
  /// a backup only if that backup contains an approved adult.
  Future<void> importJson(
    String source, {
    String? actorMemberId,
  }) async {
    if (_members.isNotEmpty) {
      if (actorMemberId == null) {
        throw const FamilyCircleAccessException('匯入完整備份需要已核准成人。');
      }
      _requireCircleManager(actorMemberId);
    }
    final snapshot = _decodeSnapshot(source);
    _validateSnapshot(snapshot);
    if (_members.isNotEmpty &&
        (snapshot.circleId != _circleId ||
            snapshot.managerMemberId != _managerMemberId)) {
      throw const FamilyCircleAccessException(
        '完整備份必須屬於同一個家庭圈，且不能更換家庭管理者。',
      );
    }
    await _storage.write(
      jsonEncode(
        _snapshotJson(
          circleId: snapshot.circleId,
          displayName: snapshot.displayName,
          createdAt: snapshot.createdAt,
          managerMemberId: snapshot.managerMemberId,
          members: snapshot.members,
          cards: snapshot.cards,
          episodeVoices: snapshot.episodeVoices,
          memberPinCredentials: const [],
          pendingAdultInvitations: const [],
          consumedAdultInvitations: const [],
          memberPinAttemptStates: const [],
        ),
      ),
    );
    _circleId = snapshot.circleId;
    _displayName = snapshot.displayName;
    _createdAt = snapshot.createdAt;
    _managerMemberId = snapshot.managerMemberId;
    _members = snapshot.members;
    _cards = snapshot.cards;
    _episodeVoices = snapshot.episodeVoices;
    // Family-data packages are portable content, not credential backups.
    _memberPinCredentials = [];
    _pendingAdultInvitations = [];
    _consumedAdultInvitations = [];
    _memberPinAttemptStates = [];
    notifyListeners();
  }

  Future<void> deleteLocalCircle({required String actorMemberId}) async {
    _requireCircleManager(actorMemberId);
    await _storage.clear();
    _circleId = 'local-family';
    _displayName = '我們家';
    _createdAt = _clock();
    _managerMemberId = null;
    _members = [];
    _cards = [];
    _episodeVoices = [];
    _memberPinCredentials = [];
    _pendingAdultInvitations = [];
    _consumedAdultInvitations = [];
    _memberPinAttemptStates = [];
    notifyListeners();
  }

  FamilyMember _requireApprovedMember(String memberId) {
    final member = memberById(memberId);
    if (member == null || !member.isApproved) {
      throw const FamilyCircleAccessException('只有已核准的家庭成員可以進入這個私密家庭圈。');
    }
    return member;
  }

  FamilyMember _requireApprovedAdult(String memberId) {
    final member = _requireApprovedMember(memberId);
    if (!member.isAdult) {
      throw const FamilyCircleAccessException('這個動作只能由已核准成人執行。');
    }
    return member;
  }

  FamilyMember _requireCircleManager(String memberId) {
    final member = _requireApprovedAdult(memberId);
    if (_managerMemberId == null || member.id != _managerMemberId) {
      throw const FamilyCircleAccessException('這個動作只能由家庭管理者執行。');
    }
    return member;
  }

  int _requiredCardIndex(String cardId) {
    final index = _cards.indexWhere((card) => card.id == cardId);
    if (index < 0) throw StateError('找不到家庭故事卡：$cardId');
    return index;
  }

  Future<void> _replaceCard(
    int index,
    FamilyCircleStoryCard card,
  ) async {
    final nextCards = [..._cards];
    nextCards[index] = card;
    await _commit(members: _members, cards: nextCards);
  }

  Future<void> _commit({
    required List<FamilyMember> members,
    required List<FamilyCircleStoryCard> cards,
    String? managerMemberId,
    List<FamilyEpisodeVoice>? episodeVoices,
    List<FamilyMemberPinCredential>? memberPinCredentials,
    List<PendingAdultInvitation>? pendingAdultInvitations,
    List<ConsumedAdultInvitation>? consumedAdultInvitations,
    List<FamilyMemberPinAttemptState>? memberPinAttemptStates,
  }) async {
    final nextEpisodeVoices = episodeVoices ?? _episodeVoices;
    final nextMemberPinCredentials =
        memberPinCredentials ?? _memberPinCredentials;
    final nextPendingAdultInvitations =
        pendingAdultInvitations ?? _pendingAdultInvitations;
    final nextConsumedAdultInvitations =
        consumedAdultInvitations ?? _consumedAdultInvitations;
    final nextMemberPinAttemptStates =
        memberPinAttemptStates ?? _memberPinAttemptStates;
    final snapshot = _FamilyCircleSnapshot(
      circleId: _circleId,
      displayName: _displayName,
      createdAt: _createdAt,
      managerMemberId: managerMemberId ?? _managerMemberId,
      members: List.of(members),
      cards: List.of(cards),
      episodeVoices: List.of(nextEpisodeVoices),
      memberPinCredentials: List.of(nextMemberPinCredentials),
      pendingAdultInvitations: List.of(nextPendingAdultInvitations),
      consumedAdultInvitations: List.of(nextConsumedAdultInvitations),
      memberPinAttemptStates: List.of(nextMemberPinAttemptStates),
    );
    _validateSnapshot(snapshot);
    await _storage.write(
      jsonEncode(
        _snapshotJson(
          circleId: snapshot.circleId,
          displayName: snapshot.displayName,
          createdAt: snapshot.createdAt,
          managerMemberId: snapshot.managerMemberId,
          members: snapshot.members,
          cards: snapshot.cards,
          episodeVoices: snapshot.episodeVoices,
          memberPinCredentials: snapshot.memberPinCredentials,
          pendingAdultInvitations: snapshot.pendingAdultInvitations,
          consumedAdultInvitations: snapshot.consumedAdultInvitations,
          memberPinAttemptStates: snapshot.memberPinAttemptStates,
        ),
      ),
    );
    _members = snapshot.members;
    _managerMemberId = snapshot.managerMemberId;
    _cards = snapshot.cards;
    _episodeVoices = snapshot.episodeVoices;
    _memberPinCredentials = snapshot.memberPinCredentials;
    _pendingAdultInvitations = snapshot.pendingAdultInvitations;
    _consumedAdultInvitations = snapshot.consumedAdultInvitations;
    _memberPinAttemptStates = snapshot.memberPinAttemptStates;
    notifyListeners();
  }
}

class _FamilyCircleSnapshot {
  const _FamilyCircleSnapshot({
    required this.circleId,
    required this.displayName,
    required this.createdAt,
    required this.managerMemberId,
    required this.members,
    required this.cards,
    required this.episodeVoices,
    required this.memberPinCredentials,
    required this.pendingAdultInvitations,
    required this.consumedAdultInvitations,
    required this.memberPinAttemptStates,
  });

  final String circleId;
  final String displayName;
  final DateTime createdAt;
  final String? managerMemberId;
  final List<FamilyMember> members;
  final List<FamilyCircleStoryCard> cards;
  final List<FamilyEpisodeVoice> episodeVoices;
  final List<FamilyMemberPinCredential> memberPinCredentials;
  final List<PendingAdultInvitation> pendingAdultInvitations;
  final List<ConsumedAdultInvitation> consumedAdultInvitations;
  final List<FamilyMemberPinAttemptState> memberPinAttemptStates;
}

Map<String, Object?> _snapshotJson({
  required String circleId,
  required String displayName,
  required DateTime createdAt,
  required String? managerMemberId,
  required List<FamilyMember> members,
  required List<FamilyCircleStoryCard> cards,
  required List<FamilyEpisodeVoice> episodeVoices,
  required List<FamilyMemberPinCredential> memberPinCredentials,
  required List<PendingAdultInvitation> pendingAdultInvitations,
  required List<ConsumedAdultInvitation> consumedAdultInvitations,
  required List<FamilyMemberPinAttemptState> memberPinAttemptStates,
  bool includeLocalRecordingReferences = true,
  bool includePrivateSecurityState = true,
}) {
  return {
    'schema': FamilyCircleStore.schema,
    'scope': 'local-private-family-circle',
    'localOnlyNotice': FamilyCircleStore.localOnlyNotice,
    'circle': {
      'id': circleId,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      if (managerMemberId != null) 'managerMemberId': managerMemberId,
    },
    'members': members.map((member) => member.toJson()).toList(),
    'storyCards': cards
        .map(
          (card) => card.toJson(
            includeLocalRecordingReferences: includeLocalRecordingReferences,
          ),
        )
        .toList(),
    'episodeVoices': episodeVoices
        .map(
          (voice) => voice.toJson(
            includeLocalRecordingReference: includeLocalRecordingReferences,
          ),
        )
        .toList(),
    if (includePrivateSecurityState &&
        (memberPinCredentials.isNotEmpty ||
            pendingAdultInvitations.isNotEmpty ||
            consumedAdultInvitations.isNotEmpty ||
            memberPinAttemptStates.isNotEmpty)) ...{
      'memberPinCredentials': memberPinCredentials
          .map((credential) => credential.toJson())
          .toList(),
      'pendingAdultInvitations': pendingAdultInvitations
          .map((invitation) => invitation.toJson())
          .toList(),
      'consumedAdultInvitations': consumedAdultInvitations
          .map((invitation) => invitation.toJson())
          .toList(),
      'memberPinAttemptStates':
          memberPinAttemptStates.map((state) => state.toJson()).toList(),
    },
  };
}

_FamilyCircleSnapshot _decodeSnapshot(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('家庭圈 JSON 無法讀取：${error.message}');
  }
  if (decoded is! Map) throw const FormatException('家庭圈備份必須是 JSON 物件。');
  final root = Map<String, Object?>.from(decoded);
  if (root['schema'] != FamilyCircleStore.schema) {
    throw const FormatException('不支援的家庭圈備份版本。');
  }
  final circleValue = root['circle'];
  if (circleValue is! Map) throw const FormatException('家庭圈缺少 circle 物件。');
  final circle = Map<String, Object?>.from(circleValue);
  final members = _jsonObjectList(root, 'members')
      .map(FamilyMember.fromJson)
      .toList(growable: false);
  final storedManagerMemberId = circle['managerMemberId'];
  String? managerMemberId;
  if (storedManagerMemberId == null) {
    // Backward-compatible migration for snapshots written before the manager
    // identity was explicit. bootstrapAdult has always self-approved the first
    // trusted adult, so that is the only safe legacy authority to inherit.
    for (final member in members) {
      if (member.isAdult &&
          member.isApproved &&
          member.approvedByMemberId == member.id) {
        managerMemberId = member.id;
        break;
      }
    }
  } else if (storedManagerMemberId is String &&
      storedManagerMemberId.trim().isNotEmpty) {
    managerMemberId = storedManagerMemberId;
  } else {
    throw const FormatException('managerMemberId 必須是非空白字串。');
  }
  final cards = _jsonObjectList(root, 'storyCards')
      .map(FamilyCircleStoryCard.fromJson)
      .toList(growable: false);
  final episodeVoices = root['episodeVoices'] == null
      ? const <FamilyEpisodeVoice>[]
      : _jsonObjectList(root, 'episodeVoices')
          .map(FamilyEpisodeVoice.fromJson)
          .toList(growable: false);
  final memberPinCredentials = root['memberPinCredentials'] == null
      ? const <FamilyMemberPinCredential>[]
      : _jsonObjectList(root, 'memberPinCredentials')
          .map(FamilyMemberPinCredential.fromJson)
          .toList(growable: false);
  final pendingAdultInvitations = root['pendingAdultInvitations'] == null
      ? const <PendingAdultInvitation>[]
      : _jsonObjectList(root, 'pendingAdultInvitations')
          .map(PendingAdultInvitation.fromJson)
          .toList(growable: false);
  final consumedAdultInvitations = root['consumedAdultInvitations'] == null
      ? const <ConsumedAdultInvitation>[]
      : _jsonObjectList(root, 'consumedAdultInvitations')
          .map(ConsumedAdultInvitation.fromJson)
          .toList(growable: false);
  final memberPinAttemptStates = root['memberPinAttemptStates'] == null
      ? const <FamilyMemberPinAttemptState>[]
      : _jsonObjectList(root, 'memberPinAttemptStates')
          .map(FamilyMemberPinAttemptState.fromJson)
          .toList(growable: false);
  return _FamilyCircleSnapshot(
    circleId: _nonBlankString(circle, 'id'),
    displayName: _nonBlankString(circle, 'displayName'),
    createdAt: _isoDate(circle, 'createdAt'),
    managerMemberId: managerMemberId,
    members: members,
    cards: cards,
    episodeVoices: episodeVoices,
    memberPinCredentials: memberPinCredentials,
    pendingAdultInvitations: pendingAdultInvitations,
    consumedAdultInvitations: consumedAdultInvitations,
    memberPinAttemptStates: memberPinAttemptStates,
  );
}

void _validateSnapshot(_FamilyCircleSnapshot snapshot) {
  if (snapshot.circleId.trim().isEmpty || snapshot.displayName.trim().isEmpty) {
    throw const FormatException('家庭圈 ID 與名稱不能是空白。');
  }
  final memberIds = <String>{};
  for (final member in snapshot.members) {
    _validateMemberBasics(member);
    if (!memberIds.add(member.id)) {
      throw FormatException('重複的家庭成員 ID：${member.id}');
    }
    if (member.isApproved &&
        (member.approvedByMemberId == null ||
            member.approvedByMemberId!.trim().isEmpty)) {
      throw FormatException('已核准成員 ${member.id} 缺少核准人。');
    }
    if (!member.isApproved && member.approvedByMemberId != null) {
      throw FormatException('待核准成員 ${member.id} 不得擁有核准人。');
    }
  }

  final approved = _approvedMembersById(snapshot.members);
  if (snapshot.members.isNotEmpty &&
      !approved.values.any((member) => member.isAdult)) {
    throw const FormatException('家庭圈至少需要一位已核准成人。');
  }
  if (snapshot.members.isEmpty && snapshot.managerMemberId != null) {
    throw const FormatException('空白家庭圈不得指定管理者。');
  }
  if (snapshot.members.isNotEmpty) {
    final manager = approved[snapshot.managerMemberId];
    if (manager == null ||
        !manager.isAdult ||
        manager.approvedByMemberId != manager.id) {
      throw const FormatException('家庭圈管理者必須是最初自我核准的成人。');
    }
  }
  for (final member in approved.values) {
    final approver = approved[member.approvedByMemberId];
    final isSelfBootstrap =
        member.id == member.approvedByMemberId && member.isAdult;
    if (!isSelfBootstrap && (approver == null || !approver.isAdult)) {
      throw FormatException('成員 ${member.id} 並非由已核准成人核准。');
    }
  }

  final credentialMemberIds = <String>{};
  for (final credential in snapshot.memberPinCredentials) {
    final member = approved[credential.memberId];
    if (member == null || !member.isAdult) {
      throw FormatException(
        '受邀成人 PIN verifier 指向無效成員：${credential.memberId}',
      );
    }
    if (!credentialMemberIds.add(credential.memberId)) {
      throw FormatException('成員 ${credential.memberId} 有重複的 PIN verifier。');
    }
    if (credential.algorithm != FamilyMemberPinCredential.supportedAlgorithm ||
        credential.iterations != FamilyMemberPinCredential.requiredIterations ||
        !_hasBase64UrlLength(credential.saltBase64, 16) ||
        !_hasBase64UrlLength(credential.verifierBase64, 32)) {
      throw FormatException('成員 ${credential.memberId} 的 PIN verifier 無效。');
    }
  }

  final pendingInvitationIds = <String>{};
  for (final invitation in snapshot.pendingAdultInvitations) {
    FamilyMember? member;
    for (final item in snapshot.members) {
      if (item.id == invitation.memberId) {
        member = item;
        break;
      }
    }
    final creator = approved[invitation.createdByMemberId];
    if (!pendingInvitationIds.add(invitation.id)) {
      throw FormatException('重複的待接受家庭邀請：${invitation.id}');
    }
    if (invitation.circleId != snapshot.circleId ||
        member == null ||
        !member.isAdult ||
        member.isApproved ||
        creator == null ||
        !creator.isAdult ||
        !invitation.expiresAt.isAfter(invitation.issuedAt) ||
        !_hasBase64UrlLength(invitation.publicKeyBase64, 32)) {
      throw FormatException('待接受家庭邀請 ${invitation.id} 無效。');
    }
  }

  final consumedInvitationIds = <String>{};
  for (final invitation in snapshot.consumedAdultInvitations) {
    final member = approved[invitation.memberId];
    if (!consumedInvitationIds.add(invitation.id) ||
        pendingInvitationIds.contains(invitation.id) ||
        member == null ||
        !member.isAdult) {
      throw FormatException('已使用家庭邀請 ${invitation.id} 無效。');
    }
  }

  final attemptMemberIds = <String>{};
  for (final state in snapshot.memberPinAttemptStates) {
    if (!attemptMemberIds.add(state.memberId) ||
        !credentialMemberIds.contains(state.memberId) ||
        state.failedAttempts < 1 ||
        state.failedAttempts > 5 ||
        (state.failedAttempts < 5 && state.lockedUntil != null) ||
        (state.failedAttempts == 5 && state.lockedUntil == null)) {
      throw FormatException('成員 ${state.memberId} 的 PIN 重試狀態無效。');
    }
  }

  final cardIds = <String>{};
  final continuationIds = <String>{};
  for (final card in snapshot.cards) {
    if (!cardIds.add(card.id)) {
      throw FormatException('重複的家庭故事卡 ID：${card.id}');
    }
    _validateCard(card, approved, continuationIds: continuationIds);
  }
  final episodePromptKeys = <String>{};
  for (final voice in snapshot.episodeVoices) {
    final key = '${voice.episodeId}::${voice.promptId ?? '<opening>'}';
    if (!episodePromptKeys.add(key)) {
      throw FormatException('同一對話節點有重複的家庭原音：$key');
    }
    _validateEpisodeVoice(voice, approved);
  }
}

Map<String, FamilyMember> _approvedMembersById(List<FamilyMember> members) {
  return {
    for (final member in members)
      if (member.isApproved) member.id: member,
  };
}

void _validateMemberBasics(FamilyMember member) {
  if (member.id.trim().isEmpty ||
      member.relationship.trim().isEmpty ||
      member.nickname.trim().isEmpty ||
      member.avatarEmoji.trim().isEmpty) {
    throw const FormatException('家庭成員的 ID、關係、暱稱與 emoji 不能是空白。');
  }
  if (member.roleColorValue < 0 || member.roleColorValue > 0xFFFFFFFF) {
    throw const FormatException('角色顏色必須是有效的 32-bit ARGB 整數。');
  }
}

void _validateEpisodeVoice(
  FamilyEpisodeVoice voice,
  Map<String, FamilyMember> approved,
) {
  if (voice.episodeId.trim().isEmpty ||
      voice.targetText.trim().isEmpty ||
      voice.translationZh.trim().isEmpty ||
      voice.romanization.trim().isEmpty) {
    throw const FormatException('家庭原音的劇集、說法、中文意思與拼音不能是空白。');
  }
  if (voice.promptId != null && voice.promptId!.trim().isEmpty) {
    throw const FormatException('家庭原音的 promptId 不能是空白。');
  }
  final adult = approved[voice.adultMemberId];
  if (adult == null || !adult.isAdult) {
    throw const FormatException('家庭原音必須由已核准成人設定。');
  }
}

void _validateCard(
  FamilyCircleStoryCard card,
  Map<String, FamilyMember> approved, {
  Set<String>? continuationIds,
}) {
  if (card.id.trim().isEmpty ||
      card.episode.trim().isEmpty ||
      card.sceneOutcome.trim().isEmpty) {
    throw const FormatException('家庭故事卡的 ID、劇集與場景結果不能是空白。');
  }
  final source = card.sourceConversationCard;
  if (source != null &&
      (source.id != card.id ||
          source.episodeId != card.episode ||
          source.completedAt != card.createdAt)) {
    throw FormatException(
      '故事卡 ${card.id} 與對話劇場的原始記錄不一致。',
    );
  }
  if (!approved.containsKey(card.createdByMemberId)) {
    throw FormatException('故事卡 ${card.id} 並非由已核准成員建立。');
  }
  final child = approved[card.childMemberId];
  if (child == null || child.isAdult) {
    throw FormatException('故事卡 ${card.id} 的孩子成員無效。');
  }
  if (card.readByMemberIds.any((memberId) => !approved.containsKey(memberId))) {
    throw FormatException('故事卡 ${card.id} 含有未核准成員的已讀狀態。');
  }

  final reactingMembers = <String>{};
  for (final reaction in card.reactions) {
    if (!approved.containsKey(reaction.memberId)) {
      throw FormatException('故事卡 ${card.id} 含有未核准成員的貼圖。');
    }
    if (!reactingMembers.add(reaction.memberId)) {
      throw FormatException('成員 ${reaction.memberId} 在同一張卡有多個貼圖。');
    }
  }
  for (final continuation in card.continuations) {
    final adult = approved[continuation.adultMemberId];
    if (adult == null || !adult.isAdult) {
      throw FormatException('故事卡 ${card.id} 含有非成人追加內容。');
    }
    if (continuation.id.trim().isEmpty || continuation.text.trim().isEmpty) {
      throw FormatException('故事卡 ${card.id} 含有空白的追加內容。');
    }
    if (continuationIds != null && !continuationIds.add(continuation.id)) {
      throw FormatException('重複的故事追加 ID：${continuation.id}');
    }
  }
}

List<Map<String, Object?>> _jsonObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List) throw FormatException('$key 必須是 JSON 陣列。');
  return value.map((item) {
    if (item is! Map) throw FormatException('$key 的項目必須是 JSON 物件。');
    return Map<String, Object?>.from(item);
  }).toList(growable: false);
}

String _nonBlankString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必須是非空白字串。');
  }
  return value;
}

DateTime _isoDate(Map<String, Object?> json, String key) {
  final value = _nonBlankString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是 ISO-8601 時間。');
  return parsed;
}

bool _hasBase64UrlLength(String source, int expectedLength) {
  try {
    return base64Url.decode(source).length == expectedLength;
  } on FormatException {
    return false;
  }
}
