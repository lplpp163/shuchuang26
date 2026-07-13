import 'dart:convert';

import 'family_circle.dart';

/// A slow, salted verifier for one invited adult's six-digit family PIN.
///
/// This record is local security state. It must never be included in the
/// portable family-data export.
class FamilyMemberPinCredential {
  const FamilyMemberPinCredential({
    required this.memberId,
    required this.algorithm,
    required this.iterations,
    required this.saltBase64,
    required this.verifierBase64,
    required this.createdAt,
  });

  static const supportedAlgorithm = 'pbkdf2-hmac-sha256';
  static const requiredIterations = 600000;

  final String memberId;
  final String algorithm;
  final int iterations;
  final String saltBase64;
  final String verifierBase64;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'algorithm': algorithm,
        'iterations': iterations,
        'salt': saltBase64,
        'verifier': verifierBase64,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FamilyMemberPinCredential.fromJson(Map<String, Object?> json) =>
      FamilyMemberPinCredential(
        memberId: _requiredString(json, 'memberId'),
        algorithm: _requiredString(json, 'algorithm'),
        iterations: _requiredInt(json, 'iterations'),
        saltBase64: _requiredString(json, 'salt'),
        verifierBase64: _requiredString(json, 'verifier'),
        createdAt: _requiredDate(json, 'createdAt'),
      );
}

/// Public-key challenge retained by the original circle until it is accepted.
/// The one-time private token exists only in the invitation package.
class PendingAdultInvitation {
  const PendingAdultInvitation({
    required this.id,
    required this.circleId,
    required this.memberId,
    required this.createdByMemberId,
    required this.issuedAt,
    required this.expiresAt,
    required this.publicKeyBase64,
  });

  final String id;
  final String circleId;
  final String memberId;
  final String createdByMemberId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String publicKeyBase64;

  Map<String, Object?> toJson() => {
        'id': id,
        'circleId': circleId,
        'memberId': memberId,
        'createdByMemberId': createdByMemberId,
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'publicKey': publicKeyBase64,
      };

  factory PendingAdultInvitation.fromJson(Map<String, Object?> json) =>
      PendingAdultInvitation(
        id: _requiredString(json, 'id'),
        circleId: _requiredString(json, 'circleId'),
        memberId: _requiredString(json, 'memberId'),
        createdByMemberId: _requiredString(json, 'createdByMemberId'),
        issuedAt: _requiredDate(json, 'issuedAt'),
        expiresAt: _requiredDate(json, 'expiresAt'),
        publicKeyBase64: _requiredString(json, 'publicKey'),
      );
}

/// Non-secret replay marker. The signing public key is discarded on success.
class ConsumedAdultInvitation {
  const ConsumedAdultInvitation({
    required this.id,
    required this.memberId,
    required this.consumedAt,
  });

  final String id;
  final String memberId;
  final DateTime consumedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'memberId': memberId,
        'consumedAt': consumedAt.toIso8601String(),
      };

  factory ConsumedAdultInvitation.fromJson(Map<String, Object?> json) =>
      ConsumedAdultInvitation(
        id: _requiredString(json, 'id'),
        memberId: _requiredString(json, 'memberId'),
        consumedAt: _requiredDate(json, 'consumedAt'),
      );
}

/// Per-member retry state. One adult being locked never locks another adult.
class FamilyMemberPinAttemptState {
  const FamilyMemberPinAttemptState({
    required this.memberId,
    required this.failedAttempts,
    this.lockedUntil,
  });

  final String memberId;
  final int failedAttempts;
  final DateTime? lockedUntil;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'failedAttempts': failedAttempts,
        'lockedUntil': lockedUntil?.toIso8601String(),
      };

  factory FamilyMemberPinAttemptState.fromJson(Map<String, Object?> json) =>
      FamilyMemberPinAttemptState(
        memberId: _requiredString(json, 'memberId'),
        failedAttempts: _requiredInt(json, 'failedAttempts'),
        lockedUntil: _optionalDate(json, 'lockedUntil'),
      );
}

enum FamilyMemberPinVerificationStatus {
  verified,
  incorrect,
  locked,
  invalidFormat,
  unavailable,
}

class FamilyMemberPinVerification {
  const FamilyMemberPinVerification({
    required this.status,
    required this.remainingAttempts,
    this.lockedUntil,
  });

  final FamilyMemberPinVerificationStatus status;
  final int remainingAttempts;
  final DateTime? lockedUntil;

  bool get isVerified => status == FamilyMemberPinVerificationStatus.verified;
}

/// The manually shared one-time package. It contains no stories, recordings or
/// PIN. [tokenBase64] is an Ed25519 private seed shown only in this package.
class FamilyInvitationPackage {
  const FamilyInvitationPackage({
    required this.invitationId,
    required this.circleId,
    required this.circleDisplayName,
    required this.invitedAdult,
    required this.issuedAt,
    required this.expiresAt,
    required this.publicKeyBase64,
    required this.tokenBase64,
  });

  static const schema = 'hometongue-family-invitation-v1';

  final String invitationId;
  final String circleId;
  final String circleDisplayName;
  final FamilyMember invitedAdult;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String publicKeyBase64;
  final String tokenBase64;

  Map<String, Object?> toJson() => {
        'schema': schema,
        'scope': 'manual-one-time-family-invitation',
        'localOnlyNotice': '這是手動交換的一次性邀請，不是雲端同步或即時帳號。',
        'invitation': {
          'id': invitationId,
          'circleId': circleId,
          'circleDisplayName': circleDisplayName,
          'invitedAdult': invitedAdult.toJson(),
          'issuedAt': issuedAt.toIso8601String(),
          'expiresAt': expiresAt.toIso8601String(),
          'publicKey': publicKeyBase64,
          'token': tokenBase64,
        },
      };

  String encode() => jsonEncode(toJson());

  factory FamilyInvitationPackage.decode(String source) {
    final root = _decodeRoot(source, label: '家庭邀請包');
    if (root['schema'] != schema) {
      throw const FormatException('不支援的家庭邀請包版本。');
    }
    final invitation = _requiredObject(root, 'invitation');
    return FamilyInvitationPackage(
      invitationId: _requiredString(invitation, 'id'),
      circleId: _requiredString(invitation, 'circleId'),
      circleDisplayName: _requiredString(invitation, 'circleDisplayName'),
      invitedAdult: FamilyMember.fromJson(
        _requiredObject(invitation, 'invitedAdult'),
      ),
      issuedAt: _requiredDate(invitation, 'issuedAt'),
      expiresAt: _requiredDate(invitation, 'expiresAt'),
      publicKeyBase64: _requiredString(invitation, 'publicKey'),
      tokenBase64: _requiredString(invitation, 'token'),
    );
  }
}

/// A signed acceptance receipt. It deliberately carries a verifier, not the
/// six-digit PIN, and never contains family stories or media references.
class FamilyInvitationReceipt {
  const FamilyInvitationReceipt({
    required this.invitationId,
    required this.circleId,
    required this.memberId,
    required this.acceptedAt,
    required this.pinCredential,
    required this.signatureBase64,
  });

  static const schema = 'hometongue-family-invitation-receipt-v1';

  final String invitationId;
  final String circleId;
  final String memberId;
  final DateTime acceptedAt;
  final FamilyMemberPinCredential pinCredential;
  final String signatureBase64;

  Map<String, Object?> get signedPayload => {
        'schema': schema,
        'invitationId': invitationId,
        'circleId': circleId,
        'memberId': memberId,
        'acceptedAt': acceptedAt.toIso8601String(),
        'pinCredential': pinCredential.toJson(),
      };

  List<int> get signingBytes => utf8.encode(jsonEncode(signedPayload));

  Map<String, Object?> toJson() => {
        'schema': schema,
        'scope': 'manual-family-invitation-acceptance',
        'localOnlyNotice': '這是手動交換的接受回條，不代表雲端帳號已同步。',
        'receipt': signedPayload,
        'signature': signatureBase64,
      };

  String encode() => jsonEncode(toJson());

  FamilyInvitationReceipt withSignature(String signature) =>
      FamilyInvitationReceipt(
        invitationId: invitationId,
        circleId: circleId,
        memberId: memberId,
        acceptedAt: acceptedAt,
        pinCredential: pinCredential,
        signatureBase64: signature,
      );

  factory FamilyInvitationReceipt.decode(String source) {
    final root = _decodeRoot(source, label: '家庭邀請接受回條');
    if (root['schema'] != schema) {
      throw const FormatException('不支援的家庭邀請接受回條版本。');
    }
    final receipt = _requiredObject(root, 'receipt');
    if (receipt['schema'] != schema) {
      throw const FormatException('家庭邀請接受回條內容版本不一致。');
    }
    return FamilyInvitationReceipt(
      invitationId: _requiredString(receipt, 'invitationId'),
      circleId: _requiredString(receipt, 'circleId'),
      memberId: _requiredString(receipt, 'memberId'),
      acceptedAt: _requiredDate(receipt, 'acceptedAt'),
      pinCredential: FamilyMemberPinCredential.fromJson(
        _requiredObject(receipt, 'pinCredential'),
      ),
      signatureBase64: _requiredString(root, 'signature'),
    );
  }
}

Map<String, Object?> _decodeRoot(String source, {required String label}) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('$label JSON 無法讀取：${error.message}');
  }
  if (decoded is! Map) throw FormatException('$label必須是 JSON 物件。');
  return Map<String, Object?>.from(decoded);
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key 必須是 JSON 物件。');
  return Map<String, Object?>.from(value);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必須是非空白字串。');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key 必須是整數。');
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是 ISO-8601 時間。');
  return parsed;
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key 必須是 ISO-8601 時間。');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key 必須是 ISO-8601 時間。');
  return parsed;
}
