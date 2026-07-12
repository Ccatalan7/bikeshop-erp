import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'seed_bikes_and_wheels.dart';

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

  print('🔐 Logging in as $email');

  // Sign in
  await Supabase.instance.client.auth.signInWithPassword(
    email: email,
    password: password,
  );

  print('✅ Logged in successfully');
  print('');

  // Run seed
  try {
    await seedBikesAndWheels();
    print('');
    print('🎉 All done! Press Ctrl+C to exit.');
  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
  }
}
