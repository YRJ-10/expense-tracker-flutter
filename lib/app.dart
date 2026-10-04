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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
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
        '/home': (context) => const MainScreen(),
        '/add-transaction': (context) => const AddTransactionScreen(),
      },
    );
  }
}