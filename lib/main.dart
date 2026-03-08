import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://niuboxpvuazwgazdkobw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pdWJveHB2dWF6d2dhemRrb2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI5NTEwMTksImV4cCI6MjA4ODUyNzAxOX0.LnUCRaSAF5BW-lJcdE9dRcMKNanbV0RO3lyartySvA8',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}