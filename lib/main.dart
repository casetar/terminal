import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'services/localization_service.dart';
import 'services/key_storage_service.dart';

// flutter_background is Android-only — import conditionally
import 'background_init_stub.dart'
    if (dart.library.io) 'background_init_android.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wrap in try/catch with timeout — on macOS unsigned builds, Keychain
  // access may block or throw; we skip gracefully to avoid black screen.
  try {
    await LocalizationService.init().timeout(const Duration(seconds: 3));
  } catch (_) {}

  try {
    await KeyStorageService.seedDefaultKey().timeout(const Duration(seconds: 3));
  } catch (_) {}

  // Enable background execution on Android only
  if (Platform.isAndroid) {
    await initBackgroundExecution();
  }

  runApp(const VpnGateApp());
}

class VpnGateApp extends StatelessWidget {
  const VpnGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LocalizationService.language,
      builder: (context, lang, child) {
        return MaterialApp(
          title: LocalizationService.translate('app_title'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: const HomeScreen(),
        );
      },
    );
  }
}
