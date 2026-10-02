import 'package:flutter_background/flutter_background.dart';

// Android-only background execution via flutter_background
Future<void> initBackgroundExecution() async {
  try {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Savun Terminal",
      notificationText: "Running SSH session in background...",
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    );
    bool initialized = await FlutterBackground.initialize(androidConfig: androidConfig);
    if (initialized) {
      await FlutterBackground.enableBackgroundExecution();
    }
  } catch (e) {
    // Ignore — background mode not critical
  }
}
