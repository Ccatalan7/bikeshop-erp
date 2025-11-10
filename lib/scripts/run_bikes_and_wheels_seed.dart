import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'seed_bikes_and_wheels.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://xzdvtzdqjeyqxnkqprtf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjcyODY1NDksImV4cCI6MjA0Mjg2MjU0OX0.z1fZMoSzPL8Dt03d7i-xC4JFBxgIvXXBrYzpH9M3afo',
  );
  
  print('🔐 Logging in as vinabikechile@gmail.com...');
  
  // Sign in
  await Supabase.instance.client.auth.signInWithPassword(
    email: 'vinabikechile@gmail.com',
    password: '000000',
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
