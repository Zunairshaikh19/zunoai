import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/zuno_loader.dart';
import 'features/auth/presentation/blocked_screen.dart';
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
    // Register background messaging handler
    FirebaseMessaging.onBackgroundMessage(NotificationService.handleBackgroundMessage);
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  
  // Initialize Ads
  try {
    await AdService().init();
  } catch (e) {
    debugPrint("AdService initialization failed: $e");
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
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
            error: (err, _) => Scaffold(body: Center(child: Text("Data Error: $err"))),
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
