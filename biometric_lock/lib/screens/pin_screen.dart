import 'package:flutter/material.dart';
import '../services/device_client.dart';

class PinScreen extends StatefulWidget {
  final String flowName;

  const PinScreen({super.key, required this.flowName});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const int _minPinLength = 6;
  static const int _maxPinLength = 8;

  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;

  void _onDigit(String d) {
    if (_isLoading || _pin.length >= _maxPinLength) return;
    setState(() {
      _pin += d;
      _errorMessage = null;
    });
  }

  void _onBackspace() {
    if (_isLoading || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _submit() async {
    if (_isLoading || _pin.length < _minPinLength) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final entered = _pin;
    // Discard PIN state from UI
    setState(() {
      _pin = '';
    });

    try {
      final token = await DeviceClient.instance.authenticateWithPin(entered);
      if (mounted) {
        Navigator.pop(context, token);
      }
    } on DeviceException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Authentication error. Please check connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Authentication'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.lock_outline,
                  size: 40, color: Color(0xFF10B981)),
              const SizedBox(height: 12),
              Text(
                'Authorize ${widget.flowName}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter your owner PIN. The PIN is never saved or transmitted in plain text.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              const SizedBox(height: 20),

              // PIN Indicator dots - a 6-8 digit PIN, so this must track the actual length, not a fixed 4.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_maxPinLength, (index) {
                  final filled = index < _pin.length;
                  final required = index < _minPinLength;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? const Color(0xFF10B981)
                          : (required
                              ? Colors.grey.shade600
                              : Colors.grey.shade800),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                _pin.length < _minPinLength
                    ? '$_minPinLength-$_maxPinLength digits ($_minPinLength minimum)'
                    : '${_pin.length}/$_maxPinLength digits',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),

              const SizedBox(height: 16),

              if (_errorMessage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade800),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(),
                ),

              const Spacer(),

              // 3x4 Numeric Keypad
              _buildKeypad(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        Row(children: [_key('1'), _key('2'), _key('3')]),
        const SizedBox(height: 12),
        Row(children: [_key('4'), _key('5'), _key('6')]),
        const SizedBox(height: 12),
        Row(children: [_key('7'), _key('8'), _key('9')]),
        const SizedBox(height: 12),
        Row(
          children: [
            _actionKey(
              icon: Icons.backspace_outlined,
              onTap: _onBackspace,
            ),
            _key('0'),
            _actionKey(
              icon: Icons.check,
              color: _pin.length >= _minPinLength
                  ? const Color(0xFF10B981)
                  : Colors.grey.shade800,
              onTap: _pin.length >= _minPinLength ? _submit : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(String digit) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: () => _onDigit(digit),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Text(
              digit,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(
      {required IconData icon, VoidCallback? onTap, Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color ?? Colors.grey.shade900,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
