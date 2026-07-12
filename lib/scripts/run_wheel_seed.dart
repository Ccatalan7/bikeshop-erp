import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'seed_wheel_building_data.dart';

/// Quick script to seed wheel building demo data
/// Run with: flutter run lib/scripts/run_wheel_seed.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final anonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
  final email = Platform.environment['SEED_USER_EMAIL'] ?? '';
  final password = Platform.environment['SEED_USER_PASSWORD'] ?? '';
  if (anonKey.isEmpty || email.isEmpty || password.isEmpty) {
    throw StateError(
      'SUPABASE_ANON_KEY, SEED_USER_EMAIL, and SEED_USER_PASSWORD are required.',
    );
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://xzdvtzdqjeyqxnkqprtf.supabase.co',
    anonKey: anonKey,
  );

  // Sign in
  print('🔐 Signing in as $email');
  await Supabase.instance.client.auth.signInWithPassword(
    email: email,
    password: password,
  );

  print('✅ Signed in successfully');

  // Run the seed
  await seedWheelBuildingData();

  print('');
  print('🎉 All done! You can close this now.');
}
