import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'screens/pairing_screen.dart';
import 'screens/scanner_screen.dart';
import 'services/scanner_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Replace with your Supabase credentials from the main ERP project
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL_HERE',
    anonKey: 'YOUR_SUPABASE_ANON_KEY_HERE',
  );

  runApp(const VinabikeScannerApp());
}

class VinabikeScannerApp extends StatelessWidget {
  const VinabikeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScannerService(),
      child: MaterialApp(
        title: 'Vinabike Scanner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const AppRouter(),
      ),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  @override
  void initState() {
    super.initState();
    _checkPairing();
  }

  Future<void> _checkPairing() async {
    final scannerService = context.read<ScannerService>();
    await scannerService.loadPairedDevice();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScannerService>(
      builder: (context, service, _) {
        if (service.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (service.pairedDeviceId == null) {
          return const PairingScreen();
        }

        return const ScannerScreen();
      },
    );
  }
}
