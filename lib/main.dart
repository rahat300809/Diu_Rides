import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/theme/app_theme.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/auth/presentation/screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init fallback: $e');
  }

  try {
    // Initialize App Configuration pointing to self-hosted API & WebSockets
    AppConfig.initialize(
      environment: Environment.production,
      useMockData: false,
    );
  } catch (e) {
    debugPrint('AppConfig init error: $e');
  }

  PreferencesService? preferencesService;
  try {
    // Initialize SharedPreferences (keeps login persistent until manual logout)
    preferencesService = await PreferencesService.init();
    await preferencesService.seedDefaultAccounts();
  } catch (e) {
    debugPrint('PreferencesService init error: $e');
  }

  try {
    // Set transparent system navigation & status bars
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        if (preferencesService != null)
          preferencesProvider.overrideWithValue(preferencesService),
      ],
      child: const DiuRideApp(),
    ),
  );
}

class DiuRideApp extends StatelessWidget {
  const DiuRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DIU Ride',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
