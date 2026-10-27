import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Cryptographic PIN Challenge-Response implementation per Section 4 Firmware Contract:
/// response = HEX(HMAC-SHA256(key = SHA-256(PIN as UTF-8 bytes), message = nonce as UTF-8 bytes))
class CryptoService {
  /// Computes the HMAC-SHA256 challenge response.
  /// The PIN string and intermediate key are discarded immediately.
  static String computePinResponse(String pin, String nonceHex) {
    // 1. Compute SHA-256 hash of PIN UTF-8 bytes
    final pinBytes = utf8.encode(pin);
    final pinHashDigest = sha256.convert(pinBytes);

    // 2. Use pinHash bytes as HMAC-SHA256 key
    final hmacKey = pinHashDigest.bytes;
    final hmac = Hmac(sha256, hmacKey);

    // 3. Compute HMAC over the nonce as UTF-8 bytes
    final nonceBytes = utf8.encode(nonceHex);
    final responseDigest = hmac.convert(nonceBytes);

    // 4. Return lowercase hex representation
    return responseDigest.toString();
  }

  /// What the lock stores for a PIN: lowercase hex of SHA-256(PIN as UTF-8 bytes). It is the HMAC key above, so it is
  /// sent only when setting or changing the PIN, never when logging in.
  static String pinVerifierHex(String pin) => sha256.convert(utf8.encode(pin)).toString();
}
