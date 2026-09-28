import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/olutech_logo.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  String _statusText = 'Initializing secure firmware handshake...';
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    const totalTicks = 50;
    int currentTick = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      currentTick++;
      final pct = currentTick / totalTicks;

      setState(() {
        _progress = pct.clamp(0.0, 1.0);
        if (pct < 0.3) {
          _statusText = 'Establishing encrypted Wi-Fi channel...';
        } else if (pct < 0.6) {
          _statusText = 'Resolving doorlock.local (mDNS)...';
        } else if (pct < 0.85) {
          _statusText = 'Verifying biometric secure enclave...';
        } else {
          _statusText = 'Hardware armed & ready.';
        }
      });

      if (currentTick >= totalTicks) {
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const HomeScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Cyber Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'CYBER-ENCLAVE V2.4',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF10B981),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'PORT 80 · WS/TLS',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),

              // Central Brand Presentation
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131722),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const OlutechLogo(size: 80, glow: true),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'ESP32-S3 Biometric Lock',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Neural Biometric Access Controller',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Powered by Olutech Cyberworld
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 14, color: Color(0xFF34D399)),
                        SizedBox(width: 6),
                        Text(
                          'Powered by Olutech Cyberworld',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6EE7B7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Bottom Progress & Telemetry
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade900,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF10B981)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _statusText,
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
