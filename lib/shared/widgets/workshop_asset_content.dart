import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/bikeshop/services/workshop_asset_service.dart';

/// Adaptador de los consumidores existentes. No cambia el vínculo guardado ni
/// deja un archivo privado expuesto al fallar su lectura autorizada.
class WorkshopAssetContent extends StatefulWidget {
  const WorkshopAssetContent({
    super.key,
    required this.reference,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String reference;
  final Widget Function(BuildContext context, String url) builder;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? errorBuilder;

  @override
  State<WorkshopAssetContent> createState() => _WorkshopAssetContentState();
}

class _WorkshopAssetContentState extends State<WorkshopAssetContent> {
  Future<String>? _url;
  StreamSubscription<AuthState>? _auth;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    _auth?.cancel();
    _refresh?.cancel();
    _auth = null;
    _url = null;
    if (!WorkshopAssetService.needsResolution(widget.reference)) return;
    final client = Supabase.instance.client;
    _load(client);
    _auth = client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() {
        _load(client);
      });
    });
  }

  void _load(SupabaseClient client) {
    _refresh?.cancel();
    _url = WorkshopAssetService(client).resolve(widget.reference);
    _refresh = Timer(const Duration(minutes: 4), () {
      if (mounted) setState(() => _load(client));
    });
  }

  @override
  void didUpdateWidget(WorkshopAssetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) _prepare();
  }

  @override
  void dispose() {
    _auth?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) return widget.builder(context, widget.reference);
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context) ??
              const Tooltip(
                message: 'No se pudo abrir el archivo del trabajo',
                child: Center(child: Icon(Icons.lock_outline)),
              );
        }
        final url = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || url == null) {
          return widget.loadingBuilder?.call(context) ??
              const Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        }
        return widget.builder(context, url);
      },
    );
  }
}
