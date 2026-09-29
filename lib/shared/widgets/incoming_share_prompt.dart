import 'dart:async';

import 'package:flutter/material.dart';

import '../../modules/messaging/widgets/incoming_share_page.dart';
import '../services/incoming_share_service.dart';

/// Host único de lo que llega desde el menú «Compartir» del teléfono.
///
/// Vive en el shell autenticado, junto a `AndroidUpdatePrompt`: sin sesión no
/// hay chats ni Archivos a los que mandar nada, así que un envío hecho antes
/// de entrar espera en [IncomingShareService] hasta que este host se monta.
/// Un envío nuevo con la pantalla abierta la reemplaza: lo último que el
/// operador compartió es lo que quiere mandar.
class IncomingSharePrompt extends StatefulWidget {
  const IncomingSharePrompt({super.key, this.service});

  final IncomingShareService? service;

  @override
  State<IncomingSharePrompt> createState() => _IncomingSharePromptState();
}

class _IncomingSharePromptState extends State<IncomingSharePrompt> {
  late final IncomingShareService _service =
      widget.service ?? IncomingShareService.instance;
  Route<void>? _openRoute;

  @override
  void initState() {
    super.initState();
    if (!_service.isSupported) return;
    _service.addListener(_presentPending);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_service.initialize());
      _presentPending();
    });
  }

  @override
  void dispose() {
    _service.removeListener(_presentPending);
    super.dispose();
  }

  void _presentPending() {
    if (!mounted || _service.pending == null) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return;
    final batch = _service.take();
    if (batch == null) return;

    final previous = _openRoute;
    if (previous != null && previous.isActive) {
      navigator.removeRoute(previous);
    }
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'incoming-share'),
      builder: (_) => IncomingSharePage(batch: batch, service: _service),
    );
    _openRoute = route;
    unawaited(
      navigator.push(route).whenComplete(() {
        if (identical(_openRoute, route)) _openRoute = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
