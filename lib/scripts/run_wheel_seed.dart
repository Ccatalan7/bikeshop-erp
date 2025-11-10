import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'seed_wheel_building_data.dart';

/// Quick script to seed wheel building demo data
/// Run with: flutter run lib/scripts/run_wheel_seed.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://xzdvtzdqjeyqxnkqprtf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwNjQyMzUsImV4cCI6MjA3NTY0MDIzNX0.q5OswWMx6C00dbSHlFSOKlv6BA6GKx36VtVSy8ohxAM',
  );
  
  // Sign in
  print('🔐 Signing in as vinabikechile@gmail.com...');
  await Supabase.instance.client.auth.signInWithPassword(
    email: 'vinabikechile@gmail.com',
    password: '000000',
  );
  
  print('✅ Signed in successfully');
  
  // Run the seed
  await seedWheelBuildingData();
  
  print('');
  print('🎉 All done! You can close this now.');
}
