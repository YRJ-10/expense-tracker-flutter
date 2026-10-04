import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/presentation/screens/splash/splash_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/auth/login_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/auth/register_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/main_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/transaction/add_transaction_screen.dart';

import 'package:expense_tracker_flutter/presentation/screens/auth/biometric_lock_screen.dart';
import 'package:expense_tracker_flutter/data/services/biometric_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _isLockScreenShowing = false;
  DateTime? _pausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkResumeLock();
    }
  }

  Future<void> _checkResumeLock() async {
    // Kunci jika aplikasi berada di background minimal 2 detik
    if (_pausedTime != null && DateTime.now().difference(_pausedTime!).inSeconds >= 2) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !_isLockScreenShowing) {
        final isBioEnabled = await BiometricService.isBiometricEnabled();
        if (isBioEnabled) {
          _isLockScreenShowing = true;
          _navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => BiometricLockScreen(
                onUnlocked: () {
                  _isLockScreenShowing = false;
                  Navigator.pop(context);
                },
              ),
            ),
          );
        }
      }
    }
    _pausedTime = null;
  }

  void _setupAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          final existingProfile = await FirestoreService.getProfile(user.uid);
          if (existingProfile == null) {
            await FirestoreService.saveProfile(user.uid, {
              'id': user.uid,
              'email': user.email,
              'full_name': user.displayName ?? 'Pengguna',
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        } catch (e) {
          debugPrint("Error creating profile: $e");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFFFF6584),
          surface: Color(0xFF1A1A2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/biometric-lock': (context) => const BiometricLockScreen(),
        '/home': (context) => const MainScreen(),
        '/add-transaction': (context) => const AddTransactionScreen(),
      },
    );
  }
}