import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'app_theme.dart';
import 'booking_notification_service.dart';
import 'mongodb_service.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppTheme.initThemeMode();
  await BookingNotificationService.instance.init();
  // Connect to MongoDB Atlas in background without blocking app startup
  MongoDbService.instance.connect().catchError((_) => false);
  runApp(const MediCareApp());
}

class MediCareApp extends StatelessWidget {
  const MediCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppTheme.themeModeNotifier,
        AppTheme.themePresetNotifier,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: 'MediCare',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: AppTheme.themeModeNotifier.value,
          home: const SplashScreen(),
        );
      },
    );
  }
}
