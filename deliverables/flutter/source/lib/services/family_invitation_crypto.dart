import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/family_invitation.dart';

typedef FamilySecureRandomBytes = List<int> Function(int length);

class FamilyInvitationKeyMaterial {
  const FamilyInvitationKeyMaterial({
    required this.tokenBase64,
    required this.publicKeyBase64,
  });

  final String tokenBase64;
  final String publicKeyBase64;
}

/// Reviewed cryptographic primitives for the manual invitation handshake.
///
/// Ed25519 means the original circle retains only a public challenge; the
/// private one-time token exists in the invitation package. PBKDF2 slows down
/// offline guessing of the necessarily low-entropy six-digit family PIN.
class FamilyInvitationCrypto {
  FamilyInvitationCrypto({FamilySecureRandomBytes? randomBytes})
      : _randomBytes = randomBytes ?? _secureRandomBytes;

  static const pinPattern = r'^\d{6}$';
  static const _pinDomain = 'hometongue/invited-adult-pin/v1\u0000';
  static const _saltLength = 16;
  static const _tokenLength = 32;
  static const _verifierLength = 32;

  final FamilySecureRandomBytes _randomBytes;
  final Ed25519 _signatureAlgorithm = Ed25519();
  final Pbkdf2 _pinKdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: FamilyMemberPinCredential.requiredIterations,
    bits: _verifierLength * 8,
  );

  String randomId() => _randomBytes(16)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();

  Future<FamilyInvitationKeyMaterial> createInvitationKeyMaterial() async {
    final token = _randomBytes(_tokenLength);
    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(token);
    final publicKey = await keyPair.extractPublicKey();
    return FamilyInvitationKeyMaterial(
      tokenBase64: base64UrlEncode(token),
      publicKeyBase64: base64UrlEncode(publicKey.bytes),
    );
  }

  Future<String> publicKeyForToken(String tokenBase64) async {
    final token = _decodeBytes(tokenBase64, '邀請 token');
    if (token.length != _tokenLength) {
      throw const FormatException('邀請 token 長度不正確。');
    }
    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(token);
    final publicKey = await keyPair.extractPublicKey();
    return base64UrlEncode(publicKey.bytes);
  }

  Future<FamilyMemberPinCredential> derivePinCredential({
    required String memberId,
    required String pin,
    required DateTime createdAt,
  }) async {
    if (!RegExp(pinPattern).hasMatch(pin)) {
      throw ArgumentError('受邀成人家人碼必須是六位數。');
    }
    final salt = _randomBytes(_saltLength);
    final key = await _pinKdf.deriveKey(
      secretKey: SecretKey(utf8.encode('$_pinDomain$pin')),
      nonce: salt,
    );
    final verifier = await key.extractBytes();
    return FamilyMemberPinCredential(
      memberId: memberId,
      algorithm: FamilyMemberPinCredential.supportedAlgorithm,
      iterations: FamilyMemberPinCredential.requiredIterations,
      saltBase64: base64UrlEncode(salt),
      verifierBase64: base64UrlEncode(verifier),
      createdAt: createdAt,
    );
  }

  Future<bool> verifyPin(
    String pin,
    FamilyMemberPinCredential credential,
  ) async {
    if (!RegExp(pinPattern).hasMatch(pin)) return false;
    validatePinCredential(credential);
    final salt = _decodeBytes(credential.saltBase64, 'PIN salt');
    final expected = _decodeBytes(credential.verifierBase64, 'PIN verifier');
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: credential.iterations,
      bits: expected.length * 8,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode('$_pinDomain$pin')),
      nonce: salt,
    );
    final actual = await key.extractBytes();
    return _constantTimeEquals(actual, expected);
  }

  Future<String> signReceipt(
    FamilyInvitationReceipt receipt,
    String tokenBase64,
  ) async {
    final token = _decodeBytes(tokenBase64, '邀請 token');
    if (token.length != _tokenLength) {
      throw const FormatException('邀請 token 長度不正確。');
    }
    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(token);
    final signature = await _signatureAlgorithm.sign(
      receipt.signingBytes,
      keyPair: keyPair,
    );
    return base64UrlEncode(signature.bytes);
  }

  Future<bool> verifyReceipt(
    FamilyInvitationReceipt receipt,
    String publicKeyBase64,
  ) async {
    try {
      final publicKeyBytes = _decodeBytes(publicKeyBase64, '邀請 public key');
      final signatureBytes =
          _decodeBytes(receipt.signatureBase64, '邀請回條 signature');
      if (publicKeyBytes.length != _tokenLength) return false;
      return _signatureAlgorithm.verify(
        receipt.signingBytes,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(
            publicKeyBytes,
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } on FormatException {
      return false;
    }
  }

  void validatePinCredential(FamilyMemberPinCredential credential) {
    if (credential.memberId.trim().isEmpty ||
        credential.algorithm != FamilyMemberPinCredential.supportedAlgorithm ||
        credential.iterations != FamilyMemberPinCredential.requiredIterations) {
      throw const FormatException('受邀成人 PIN verifier 參數不受支援。');
    }
    final salt = _decodeBytes(credential.saltBase64, 'PIN salt');
    final verifier = _decodeBytes(credential.verifierBase64, 'PIN verifier');
    if (salt.length != _saltLength || verifier.length != _verifierLength) {
      throw const FormatException('受邀成人 PIN verifier 長度不正確。');
    }
  }

  void validatePublicKey(String publicKeyBase64) {
    final bytes = _decodeBytes(publicKeyBase64, '邀請 public key');
    if (bytes.length != _tokenLength) {
      throw const FormatException('邀請 public key 長度不正確。');
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Uint8List _decodeBytes(String source, String label) {
    try {
      return base64Url.decode(source);
    } on FormatException {
      throw FormatException('$label 不是有效的 base64url。');
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      final leftByte = index < left.length ? left[index] : 0;
      final rightByte = index < right.length ? right[index] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }
}
