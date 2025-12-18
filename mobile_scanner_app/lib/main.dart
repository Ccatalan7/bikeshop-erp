import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/pairing_screen.dart';
import 'screens/scanner_screen.dart';
import 'services/scanner_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No hardcoded Supabase.initialize here!
  // Config acts dynamically via ScannerService.
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
    _initService();
  }

  Future<void> _initService() async {
    // Initialize service (load config & pairing)
    final scannerService = context.read<ScannerService>();
    await scannerService.initialize();
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

        // If not configured OR not paired -> Show Pairing/Config Screen
        if (!service.isConfigured || !service.isPaired) {
          return const PairingScreen();
        }

        return const ScannerScreen();
      },
    );
  }
}
