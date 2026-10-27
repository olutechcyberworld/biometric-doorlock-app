import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/device_client.dart';

/// First-time PIN setup ([sessionToken] == null) or PIN change ([sessionToken] from logging in with the old PIN).
/// Either way the lock only accepts the new PIN after an ENROLLED finger is read at the door.
class PinSetupScreen extends StatefulWidget {
  final String? sessionToken;

  const PinSetupScreen({super.key, this.sessionToken});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _waiting = false;
  String? _error;

  bool get _isChange => widget.sessionToken != null;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    final p = _pin.text;
    if (!RegExp(r'^\d{6,8}$').hasMatch(p)) {
      return 'The PIN must be 6 to 8 digits.';
    }
    if (p != _confirm.text) return 'The two PINs do not match.';
    if (RegExp(r'^(\d)\1+$').hasMatch(p) ||
        const ['123456', '1234567', '12345678', '654321', '7654321', '87654321']
            .contains(p)) {
      return 'That PIN is too easy to guess. Pick something less obvious.';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _waiting = true;
      _error = null;
    });
    try {
      if (_isChange) {
        await DeviceClient.instance.changePin(widget.sessionToken!, _pin.text);
      } else {
        await DeviceClient.instance.setupPin(_pin.text);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isChange
              ? 'PIN changed. Use the new PIN from now on.'
              : 'PIN set on the lock.')));
      Navigator.pop(context, true);
    } on DeviceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the lock.');
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  Widget _field(TextEditingController c, String label) {
    return TextField(
      controller: c,
      enabled: !_waiting,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isChange ? 'Change PIN' : 'Set PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isChange
                    ? 'Choose a new 6-8 digit PIN.'
                    : 'Choose a 6-8 digit owner PIN for this lock.',
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'To confirm you are at the door, the lock will ask for an enrolled fingerprint after you press Save.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              _field(_pin, _isChange ? 'New PIN' : 'PIN'),
              const SizedBox(height: 12),
              _field(_confirm, 'Confirm PIN'),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade800),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),
              if (_waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Touch the fingerprint sensor on the lock now (within 20 seconds).',
                          style: TextStyle(color: Color(0xFF6EE7B7)),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _waiting ? null : _submit,
                child: const Text('Save PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
