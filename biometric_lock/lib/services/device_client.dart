import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'crypto_service.dart';
import 'discovery_service.dart';

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

class PinStatus {
  final bool pinSet;
  final int lockedMs;

  PinStatus({required this.pinSet, required this.lockedMs});
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

  Future<bool> _answersWhoami(String host) async {
    try {
      final res = await http
          .get(Uri.parse('http://$host/whoami'))
          .timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        return m['device'] == 'doorlock';
      }
    } catch (_) {}
    return false;
  }

  /// Makes sure [host] actually reaches the lock. The lock's IP depends on the network it joined and can change,
  /// so when the saved address does not answer, scan the local network and save whatever address the lock has now.
  Future<bool> ensureReachable({bool force = false}) async {
    if (!force && await _answersWhoami(_host)) return true;
    final d = await DiscoveryService.discover();
    if (d == null) return false;
    await setHost(d.port == 80 ? d.ip : '${d.ip}:${d.port}');
    return true;
  }

  /// Section 4: PIN Challenge-Response
  Future<String> authenticateWithPin(String pin) async {
    await ensureReachable();

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
      if (res.statusCode == 409) {
        throw DeviceException(
            'No PIN is set on the lock yet. Use "Set PIN" on the home screen first.');
      }
      throw DeviceException('Invalid response from doorlock device.');
    } on TimeoutException {
      throw DeviceException(
          'Connection timed out. Confirm your phone is on the same local Wi-Fi as the door lock.');
    } catch (e) {
      if (e is DeviceException) rethrow;
      throw DeviceException(
          'Could not find the door lock. Make sure it is powered and joined to the same Wi-Fi as this phone.');
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
          final retryMs = (data['retry_after_ms'] as num?)?.toInt();
          throw DeviceException(
            retryMs != null && retryMs > 0
                ? 'Too many incorrect attempts. Try again in ${(retryMs / 1000).ceil()} s.'
                : 'Too many incorrect attempts. Try again in a few minutes.',
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
      } else if (res.statusCode == 409) {
        throw DeviceException(
            'No PIN is set on the lock yet. Use "Set PIN" on the home screen first.');
      } else if (res.statusCode == 400) {
        throw DeviceException(
            'The lock rejected the request (expired challenge). Please try again.');
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

  /// GET /pin/status - whether the lock has a PIN yet (null = lock not reachable).
  Future<PinStatus?> getPinStatus() async {
    await ensureReachable();
    try {
      final res = await http
          .get(Uri.parse('http://$_host/pin/status'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return PinStatus(
        pinSet: m['pin_set'] == true,
        lockedMs: (m['locked_ms'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// First-time PIN. The lock then waits (up to ~20 s) for an enrolled finger on its sensor before it accepts it.
  Future<void> setupPin(String pin) async {
    await ensureReachable();
    await _pinRequest(
      Uri.parse('http://$_host/pin/setup'),
      {'pin_hash': CryptoService.pinVerifierHex(pin)},
    );
  }

  /// Change PIN: needs the session token from logging in with the OLD PIN, plus an enrolled finger at the lock.
  Future<void> changePin(String sessionToken, String newPin) async {
    await _pinRequest(
      Uri.parse(
          'http://$_host/pin/change?token=${Uri.encodeComponent(sessionToken)}'),
      {'new_pin_hash': CryptoService.pinVerifierHex(newPin)},
    );
  }

  Future<void> _pinRequest(Uri url, Map<String, String> body) async {
    try {
      final res = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 30)); // the lock waits for the finger before it answers
      if (res.statusCode == 200) return;
      String error = '';
      try {
        error = (jsonDecode(res.body) as Map<String, dynamic>)['error']
                as String? ??
            '';
      } catch (_) {}
      switch (error) {
        case 'no_finger':
          throw DeviceException(
              'No finger was read. Try again and touch the lock\'s fingerprint sensor right after pressing Save.');
        case 'fingerprint_mismatch':
          throw DeviceException(
              'That fingerprint is not enrolled on the lock. If none is enrolled yet, enroll one first.');
        case 'sensor_busy':
          throw DeviceException(
              'The lock is busy. Wait a few seconds and try again.');
        case 'sensor_error':
          throw DeviceException(
              'The lock\'s fingerprint sensor reported an error.');
        case 'pin_already_set':
          throw DeviceException('A PIN is already set. Use "Change PIN".');
        case 'too_soon':
          throw DeviceException('Please wait 10 seconds and try again.');
        case 'session_expired':
          throw DeviceException(
              'Session expired. Go back and enter your current PIN again.',
              isSessionExpired: true);
        default:
          throw DeviceException('PIN request failed (HTTP ${res.statusCode}).');
      }
    } on TimeoutException {
      throw DeviceException(
          'The lock did not answer in time. Check the connection and try again.');
    } catch (e) {
      if (e is DeviceException) rethrow;
      throw DeviceException('Could not reach the lock at $_host.');
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
      } else if (res.statusCode == 409) {
        final err = data['error'] as String? ?? '';
        throw DeviceException(err == 'override_active'
            ? 'An override window is already open. Touch the lock\'s fingerprint sensor.'
            : 'The lock is busy right now. Wait a few seconds and try again.');
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
