import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/device_client.dart';

class BoundingBox {
  final double x;
  final double y;
  final double w;
  final double h;

  BoundingBox(
      {required this.x, required this.y, required this.w, required this.h});
}

class EnrollScreen extends StatefulWidget {
  final String sessionToken;

  const EnrollScreen({super.key, required this.sessionToken});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

enum _EnrollStep { nameInput, awaitingFingerprint, streaming, newFingerprint, success, error }

class _EnrollScreenState extends State<EnrollScreen> {
  _EnrollStep _step = _EnrollStep.nameInput;
  final TextEditingController _nameController = TextEditingController();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  Uint8List? _latestJpegBytes;
  bool _faceFound = false;
  BoundingBox? _bbox;
  // Set from each detection message (docs/APP_PROTOCOL.md): the device's actual detector frame is 240x240,
  // but this is read from the message, not assumed, so it can never silently drift out of sync again.
  double _frameW = 240;
  double _frameH = 240;

  Timer? _watchdog;
  bool _heardFromLock = false;

  // New person's fingerprint (after the 5 face captures): the lock asks for the same finger twice.
  String _fpStep = 'place1';

  int _frameIndex = 0;
  int _framesNeeded = 5;
  String _hintText = 'Center your face in the frame.';
  String? _errorMessage;

  @override
  void dispose() {
    _channel?.sink.close();
    _watchdog?.cancel();
    _subscription?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _startEnrollmentSession() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _step = _EnrollStep.awaitingFingerprint;
      _errorMessage = null;
    });

    _channel = DeviceClient.instance.openSessionWebSocket(widget.sessionToken);
    _heardFromLock = false;

    // The lock answers a new session immediately ("awaiting_fingerprint"). Silence means the socket never opened.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 8), () {
      if (!_heardFromLock && mounted && _step == _EnrollStep.awaitingFingerprint) {
        setState(() {
          _step = _EnrollStep.error;
          _errorMessage =
              'The lock did not answer the live session. Check that the lock firmware is up to date and on the same Wi-Fi.';
        });
      }
    });

    _subscription = _channel!.stream.listen(
      (data) {
        _heardFromLock = true;
        _watchdog?.cancel();
        if (data is String) {
          _handleTextMessage(data);
        } else if (data is Uint8List) {
          setState(() {
            _latestJpegBytes = data;
          });
        } else if (data is List<int>) {
          setState(() {
            _latestJpegBytes = Uint8List.fromList(data);
          });
        }
      },
      onError: (err) {
        setState(() {
          _step = _EnrollStep.error;
          _errorMessage = 'WebSocket connection failed. Verify Wi-Fi network.';
        });
      },
      onDone: () {
        if (_step != _EnrollStep.success && _step != _EnrollStep.error) {
          setState(() {
            _step = _EnrollStep.error;
            _errorMessage = 'Connection closed prematurely.';
          });
        }
      },
    );
  }

  void _handleTextMessage(String jsonStr) {
    try {
      final msg = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'state') {
        final state = msg['state'] as String?;
        if (state == 'awaiting_fingerprint') {
          // Waiting for owner physical sensor tap
        } else if (state == 'fingerprint_confirmed') {
          setState(() {
            _step = _EnrollStep.streaming;
          });
          // Section 5.2 Step 7: Send select_mode
          _channel?.sink.add(jsonEncode({
            'type': 'select_mode',
            'mode': 'enroll',
            'name': _nameController.text.trim(),
          }));
        } else if (state == 'awaiting_new_fingerprint') {
          setState(() {
            _step = _EnrollStep.newFingerprint;
            _fpStep = 'place1';
          });
        } else if (state == 'unauthorized' || state == 'busy') {
          setState(() {
            _step = _EnrollStep.error;
            _errorMessage = state == 'busy'
                ? 'The lock is already in an owner session. Try again in a moment.'
                : 'The lock rejected the session. Go back and enter your PIN again.';
          });
        } else if (state == 'fingerprint_failed' || state == 'timeout') {
          setState(() {
            _step = _EnrollStep.error;
            _errorMessage = state == 'timeout'
                ? 'Timed out waiting for fingerprint.'
                : 'Fingerprint authorization failed.';
          });
        }
      } else if (type == 'detection') {
        final found = msg['face_found'] as bool? ?? false;
        setState(() {
          _faceFound = found;
          _frameW = (msg['frame_w'] as num?)?.toDouble() ?? _frameW;
          _frameH = (msg['frame_h'] as num?)?.toDouble() ?? _frameH;
          if (found && msg['bbox'] != null) {
            final b = msg['bbox'] as Map<String, dynamic>;
            _bbox = BoundingBox(
              x: (b['x'] as num).toDouble(),
              y: (b['y'] as num).toDouble(),
              w: (b['w'] as num).toDouble(),
              h: (b['h'] as num).toDouble(),
            );
          } else {
            _bbox = null;
          }
        });
      } else if (type == 'capture_result') {
        final success = msg['success'] as bool? ?? false;
        if (success) {
          setState(() {
            _frameIndex =
                (msg['frame_index'] as num?)?.toInt() ?? (_frameIndex + 1);
            _framesNeeded = (msg['frames_needed'] as num?)?.toInt() ?? 5;
            _hintText = 'Great! Now turn your head slightly and capture again.';
          });
        } else {
          final reason = msg['reason'] as String? ?? 'capture_failed';
          setState(() {
            _hintText = reason == 'no_face_detected'
                ? 'No face detected. Keep steady.'
                : 'Capture failed. Try again.';
          });
        }
      } else if (type == 'fingerprint_progress') {
        setState(() => _fpStep = (msg['step'] as String?) ?? _fpStep);
      } else if (type == 'enrollment_failed') {
        final reason = msg['reason'] as String? ?? '';
        setState(() {
          _step = _EnrollStep.error;
          _errorMessage = switch (reason) {
            'fingerprint_timeout' =>
              'No finger was read in time. Nothing was saved - start again.',
            'fingerprint_mismatch' =>
              'The two fingerprint scans did not match. Nothing was saved - start again.',
            'fingerprint_library_full' =>
              'The lock\'s fingerprint memory is full.',
            'user_table_full' => 'The lock already has the maximum number of users.',
            'sensor_busy' => 'The lock\'s sensor is busy. Try again in a moment.',
            'bad_name' => 'That name cannot be used. Use 1-23 plain characters.',
            _ => 'The lock could not finish enrollment ($reason). Nothing was saved.',
          };
        });
      } else if (type == 'enrollment_complete') {
        setState(() {
          _step = _EnrollStep.success;
        });
      }
    } catch (e) {
      debugPrint('Unexpected JSON from device: $jsonStr');
    }
  }

  void _capture() {
    if (!_faceFound) return;
    _channel?.sink.add(jsonEncode({'type': 'capture'}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Enrollment'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _EnrollStep.nameInput:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Enroll New Face',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the person\'s name or identifier:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Alice',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _startEnrollmentSession,
              child: const Text('Next: Sensor Verification'),
            ),
          ],
        );

      case _EnrollStep.awaitingFingerprint:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint, size: 72, color: Color(0xFF10B981)),
              SizedBox(height: 20),
              Text(
                'Place your finger on the sensor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Owner verification required to begin camera enrollment.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        );

      case _EnrollStep.streaming:
        return Column(
          children: [
            // Progress Indicator
            LinearProgressIndicator(
              value: _frameIndex / _framesNeeded.toDouble(),
              backgroundColor: Colors.grey.shade900,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 12),
            Text(
              'Capture $_frameIndex of $_framesNeeded',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 16),

            // Live Camera View with Bounding Box Overlay
            AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_latestJpegBytes != null)
                        Image.memory(
                          _latestJpegBytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        const Center(child: Text('Connecting camera...')),

                      // Bounding box overlay (Section 5.2 Step 8)
                      if (_faceFound && _bbox != null)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Scale from the device's reported detector frame size to the displayed view.
                            final scaleX = constraints.maxWidth / _frameW;
                            final scaleY = constraints.maxHeight / _frameH;

                            return Positioned(
                              left: _bbox!.x * scaleX,
                              top: _bbox!.y * scaleY,
                              width: _bbox!.w * scaleX,
                              height: _bbox!.h * scaleY,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.lightGreenAccent, width: 3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Text(
              _faceFound ? _hintText : 'Center your face in the frame.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _faceFound ? Colors.white : Colors.amberAccent,
                fontSize: 13,
              ),
            ),

            const Spacer(),

            // Capture Button (Section 5.2 Step 9)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _faceFound ? _capture : null,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Capture'),
              ),
            ),
          ],
        );

      case _EnrollStep.newFingerprint:
        final msg = switch (_fpStep) {
          'remove' => 'Lift your finger',
          'place2' => 'Place the SAME finger again',
          'storing' => 'Saving...',
          _ => 'Place the new person\'s finger on the sensor',
        };
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, size: 72, color: Color(0xFF10B981)),
              const SizedBox(height: 20),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${_nameController.text.trim()}\'s face is captured. The same person\'s finger is read twice and stored with it.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        );

      case _EnrollStep.success:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 72, color: Color(0xFF10B981)),
              const SizedBox(height: 20),
              const Text(
                'Enrollment Complete',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${_nameController.text.trim()} can now unlock the door with this finger and this face.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );

      case _EnrollStep.error:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 72, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text('Enrollment Aborted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Network interrupted.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return Home'),
              ),
            ],
          ),
        );
    }
  }
}
