import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'crypto_service.dart';

class AuthResult {
  final String sessionToken;
  final int expiresIn;

  AuthResult({required this.sessionToken, required this.expiresIn});
}

class OverrideResult {
  final String status;
  final int timeoutMs;

  OverrideResult({required this.status, required this.timeoutMs});
}

class DeviceException implements Exception {
  final String message;
  final int? attemptsRemaining;
  final bool isLockout;
  final bool isSessionExpired;

  DeviceException(
    this.message, {
    this.attemptsRemaining,
    this.isLockout = false,
    this.isSessionExpired = false,
  });

  @override
  String toString() => message;
}

class DeviceClient {
  static final DeviceClient instance = DeviceClient._internal();
  DeviceClient._internal();

  String _host = 'doorlock.local';
  static const String _prefKeyHost = 'last_successful_device_host';

  String get host => _host;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyHost);
    if (saved != null && saved.trim().isNotEmpty) {
      _host = saved.trim();
    }
  }

  Future<void> setHost(String newHost) async {
    final clean = newHost
        .trim()
        .replaceAll(RegExp(r'^https?:\/\/'), '')
        .replaceAll(RegExp(r'\/+$'), '');
    _host = clean.isNotEmpty ? clean : 'doorlock.local';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyHost, _host);
  }

  /// Section 4: PIN Challenge-Response
  Future<String> authenticateWithPin(String pin) async {
    // 1. GET /challenge
    final nonce = await _getChallenge();

    // 2. Compute response
    final responseHex = CryptoService.computePinResponse(pin, nonce);

    // 3. POST /auth
    final authResult = await _postAuth(nonce, responseHex);
    return authResult.sessionToken;
  }

  Future<String> _getChallenge() async {
    final url = Uri.parse('http://$_host/challenge');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final nonce = data['nonce'] as String?;
        if (nonce != null && nonce.isNotEmpty) {
          return nonce;
        }
      }
      throw DeviceException('Invalid response from doorlock device.');
    } on TimeoutException {
      throw DeviceException(
          'Connection timed out. Confirm your phone is on the same local Wi-Fi as the door lock.');
    } catch (e) {
      if (e is DeviceException) rethrow;
      throw DeviceException(
          'Could not find door lock at "$_host". Ensure both phone and lock are on the same Wi-Fi.');
    }
  }

  Future<AuthResult> _postAuth(String nonce, String responseHex) async {
    final url = Uri.parse('http://$_host/auth');
    try {
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'nonce': nonce, 'response': responseHex}),
          )
          .timeout(const Duration(seconds: 4));

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        return AuthResult(
          sessionToken: data['session_token'] as String,
          expiresIn: (data['expires_in'] as num?)?.toInt() ?? 120,
        );
      } else if (res.statusCode == 401) {
        final error = data['error'] as String? ?? 'invalid_pin';
        final remaining = (data['attempts_remaining'] as num?)?.toInt();

        if (error == 'locked_out' || remaining == 0) {
          throw DeviceException(
            'Too many incorrect attempts. Try again in a few minutes.',
            isLockout: true,
            attemptsRemaining: 0,
          );
        }

        throw DeviceException(
          remaining != null
              ? 'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.'
              : 'Incorrect PIN. Please try again.',
          attemptsRemaining: remaining,
        );
      } else {
        throw DeviceException(
            'Authentication failed with HTTP ${res.statusCode}');
      }
    } on TimeoutException {
      throw DeviceException('Network timed out reaching door lock.');
    } catch (e) {
      if (e is DeviceException) rethrow;
      throw DeviceException(
          'Could not reach door lock. Check local Wi-Fi network.');
    }
  }

  /// Section 5.1 Override: POST /override?token=<session_token>
  Future<OverrideResult> postOverride(String sessionToken) async {
    final url = Uri.parse(
        'http://$_host/override?token=${Uri.encodeComponent(sessionToken)}');
    try {
      final res = await http.post(url).timeout(const Duration(seconds: 4));
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        return OverrideResult(
          status: data['status'] as String? ?? 'awaiting_fingerprint',
          timeoutMs: (data['timeout_ms'] as num?)?.toInt() ?? 90000,
        );
      } else if (res.statusCode == 401) {
        throw DeviceException('Session expired. Please re-enter your PIN.',
            isSessionExpired: true);
      } else {
        throw DeviceException('Override request failed: ${res.statusCode}');
      }
    } catch (e) {
      if (e is DeviceException) rethrow;
      throw DeviceException('Failed to communicate with lock at $_host');
    }
  }

  /// Section 5.2 & 5.3: WebSocket Session
  WebSocketChannel openSessionWebSocket(String sessionToken) {
    final wsUri = Uri.parse(
        'ws://$_host/session?token=${Uri.encodeComponent(sessionToken)}');
    return WebSocketChannel.connect(wsUri);
  }
}
