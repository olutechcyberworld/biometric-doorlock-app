import 'package:flutter/material.dart';

/// Olutech Cyberworld brand mark.
///
/// Renders the actual brand logo asset supplied by Olutech Cyberworld
/// (place the file at assets/images/olutech_logo.png - see pubspec.yaml).
/// This widget does NOT redraw or reinterpret the logo; it only lays the
/// provided image out with an optional ambient glow behind it.
class OlutechLogo extends StatelessWidget {
  final double size;
  final bool glow;

  const OlutechLogo({
    super.key,
    this.size = 56,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glow)
            Container(
              width: size * 0.9,
              height: size * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    blurRadius: 18,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          Image.asset(
            'assets/images/olutech_logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}
