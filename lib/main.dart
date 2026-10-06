import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'core/theme/app_theme.dart';
import 'core/widgets/zuno_loader.dart';
import 'features/auth/presentation/blocked_screen.dart';
import 'providers/purchase_provider.dart';
import 'providers/user_provider.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'features/root_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    // App Check (Play Integrity) proves requests come from the genuine app.
    // The backend enforces it when APP_CHECK_ENFORCE=true. In debug builds a
    // debug provider is used (register its token in the Firebase console).
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      );
    } catch (e) {
      debugPrint("App Check activation failed: $e");
    }
    // Register background messaging handler
    FirebaseMessaging.onBackgroundMessage(NotificationService.handleBackgroundMessage);
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );

  // Ads (incl. the consent form) start after the first frame so a slow ad SDK
  // never delays app launch.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await AdService().init();
    } catch (e) {
      debugPrint("AdService initialization failed: $e");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zuno AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userAsync = ref.watch(userProvider);
    // Keep the store connection alive while signed in so purchases that finish
    // later (or are re-delivered after a restart) are still verified.
    if (authState.valueOrNull != null) ref.watch(purchaseCoordinatorProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          return userAsync.when(
            data: (userData) {
              if (userData == null) return const ZunoLoadingScreen();
              if (userData.isBlocked) {
                return const BlockedScreen();
              }
              return const RootScreen();
            },
            loading: () => const ZunoLoadingScreen(),
            error: (err, _) => Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "We couldn't load your profile.",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Check your connection and try again.",
                        style: TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => ref.read(userProvider.notifier).retryProfile(),
                        child: const Text("Retry"),
                      ),
                      TextButton(
                        onPressed: () => ref.read(firebaseServiceProvider).signOut(),
                        child: const Text("Log out"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          // Deferred Authentication: Allow guest users to explore Dashboard directly
          return const RootScreen();
        }
      },
      loading: () => const ZunoLoadingScreen(),
      error: (err, _) => Scaffold(
        body: Center(child: Text("Auth Error: $err")),
      ),
    );
  }
}
