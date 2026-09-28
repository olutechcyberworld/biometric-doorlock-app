import 'package:flutter/material.dart';
import '../services/device_client.dart';
import '../widgets/olutech_logo.dart';
import 'pin_screen.dart';
import 'override_screen.dart';
import 'enroll_screen.dart';
import 'manage_users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceClient _client = DeviceClient.instance;

  void _showDeviceAddressDialog() {
    final controller = TextEditingController(text: _client.host);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        title:
            const Text('Device Address', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the mDNS hostname or local IP address of the ESP32-S3 lock:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'e.g. doorlock.local or 192.168.1.50',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              await _client.setHost(controller.text);
              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Device address set to ${_client.host}')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _startFlow(String flowType, String title) async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(flowName: title),
      ),
    );

    if (token == null || !mounted) return;

    if (flowType == 'override') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OverrideScreen(sessionToken: token)),
      );
    } else if (flowType == 'enroll') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EnrollScreen(sessionToken: token)),
      );
    } else if (flowType == 'manage') {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ManageUsersScreen(sessionToken: token)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1018),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF131722),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            ),
            child: const OlutechLogo(size: 24, glow: false),
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Doorlock Enclave',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Powered by Olutech Cyberworld',
                style: TextStyle(fontSize: 10, color: Color(0xFF6EE7B7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            tooltip: 'Device Address',
            onPressed: _showDeviceAddressDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              // Top Hero Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF131722),
                      Color(0xFF10131B),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const OlutechLogo(size: 48, glow: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ESP32-S3 Biometric Lock',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.wifi,
                                  size: 14, color: Color(0xFF10B981)),
                              const SizedBox(width: 6),
                              Text(
                                _client.host,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // The Three Flows (Section 6.1)
              _ActionButton(
                title: 'Override',
                badge: '90s WINDOW',
                subtitle: 'Arm physical sensor for emergency access',
                icon: Icons.shield_outlined,
                color: Colors.amber.shade600,
                onTap: () => _startFlow('override', 'Override'),
              ),
              const SizedBox(height: 14),

              _ActionButton(
                title: 'Enroll New Face',
                badge: 'AI CAM',
                subtitle: 'Live camera preview with 5-angle capture',
                icon: Icons.face_retouching_natural,
                color: const Color(0xFF10B981),
                onTap: () => _startFlow('enroll', 'Face Enrollment'),
              ),
              const SizedBox(height: 14),

              _ActionButton(
                title: 'Manage Users',
                badge: 'DATABASE',
                subtitle: 'Audit enrolled faces and revoke permissions',
                icon: Icons.people_outline,
                color: Colors.cyan.shade600,
                onTap: () => _startFlow('manage', 'User Management'),
              ),

              const Spacer(),

              // Brand footer
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 13, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text(
                    'Powered by Olutech Cyberworld',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6EE7B7),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Direct Local Network · No Cloud Dependency',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String title;
  final String badge;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF11141D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade800),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                              fontSize: 9,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
