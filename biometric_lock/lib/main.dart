import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'services/device_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved device IP/hostname fallback from SharedPreferences
  await DeviceClient.instance.init();

  // Android edge-to-edge transparent system bar configuration
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090B10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const BiometricDoorlockOwnerApp());
}

class BiometricDoorlockOwnerApp extends StatelessWidget {
  const BiometricDoorlockOwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doorlock Owner · Olutech Cyberworld',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090B10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Emerald
          surface: Color(0xFF11141D),
          error: Color(0xFFEF4444),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1018),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
