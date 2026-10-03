import 'dart:async';
import 'package:flutter/material.dart';
import '../services/device_client.dart';
import 'pin_screen.dart';

class OverrideScreen extends StatefulWidget {
  final String sessionToken;

  const OverrideScreen({super.key, required this.sessionToken});

  @override
  State<OverrideScreen> createState() => _OverrideScreenState();
}

class _OverrideScreenState extends State<OverrideScreen> {
  bool _isLoading = true;
  String? _error;
  int _secondsRemaining = 90;
  Timer? _countdownTimer;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _executeOverride(widget.sessionToken);
  }

  Future<void> _executeOverride(String token) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isExpired = false;
    });

    try {
      final res = await DeviceClient.instance.postOverride(token);
      final secs = (res.timeoutMs / 1000).round();
      setState(() {
        _isLoading = false;
        _secondsRemaining = secs;
      });

      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining <= 1) {
          timer.cancel();
          setState(() {
            _isExpired = true;
            _secondsRemaining = 0;
          });
        } else {
          setState(() {
            _secondsRemaining--;
          });
        }
      });
    } on DeviceException catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to trigger override. Check connection.';
      });
    }
  }

  void _restart() async {
    final newToken = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PinScreen(flowName: 'Override')),
    );
    if (newToken != null && mounted) {
      _executeOverride(newToken);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometric Override'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 54, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    if (_isExpired) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_off_outlined, size: 54, color: Colors.amberAccent),
          const SizedBox(height: 16),
          const Text('Time expired — try again', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'The 90-second sensor window has closed without an unlock attempt.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart Override'),
          ),
        ],
      );
    }

    // Active countdown state (Section 5.1 Step 5)
    return Column(
      children: [
        const Spacer(),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: _secondsRemaining / 90.0,
                strokeWidth: 8,
                color: Colors.amberAccent,
                backgroundColor: Colors.grey.shade900,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_secondsRemaining}s',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
                const Text('REMAINING', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: Colors.grey)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 36),
        const Text(
          'Place your finger on the sensor now.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'You have 90 seconds. The door lock mechanism will unlatch once your fingerprint matches.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
