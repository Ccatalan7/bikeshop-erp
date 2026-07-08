import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bug_report.dart';

/// Service for CRUD operations on bug reports + screenshot uploads.
class BugReportService {
  final _supabase = Supabase.instance.client;

  // ─── Available modules for the dropdown ─────────────────────────
  /// Returns a flat list of module names matching the ERP sidebar structure.
  /// Format: "Parent → SubItem" for expandable modules.
  static List<String> get availableModules => const [
        // Contabilidad
        'Contabilidad → Plan de cuentas',
        'Contabilidad → Gastos',
        'Contabilidad → Asientos contables',
        'Contabilidad → Reportes Financieros',
        'Contabilidad → Estado de Resultados',
        'Contabilidad → Balance General',
        // Impuestos
        'Impuestos → Declaraciones F29',
        // Clientes
        'Clientes → Lista de clientes',
        'Clientes → Nuevo cliente',
        // Mensajería
        'Mensajería → Meson de ayuda',
        // Taller
        'Taller → Trabajos',
        'Taller → Nuevo trabajo',
        'Taller → Bicicletas registradas',
        'Taller → Marcas y modelos',
        'Taller → Calendario',
        'Taller → Estados personalizados',
        // Smart Features
        'Smart Features → Wheel Builder',
        'Smart Features → Spoke Calculator',
        'Smart Features → Bike Encyclopedia',
        'Smart Features → Hubs',
        'Smart Features → Rims',
        'Smart Features → Spokes',
        // Inventario
        'Inventario → Productos',
        'Inventario → Categorías',
        'Inventario → Marcas',
        'Inventario → Movimientos',
        // Ventas
        'Ventas → Facturas de venta',
        'Ventas → Nueva factura',
        'Ventas → Pagos',
        'Ventas → Informes',
        // Compras
        'Compras → Lista Inteligente',
        'Compras → Proveedores',
        'Compras → Facturas de compra',
        'Compras → Nueva factura',
        'Compras → Pagos',
        // POS
        'POS → Panel POS',
        'POS → Carrito',
        'POS → Cobrar',
        // RR.HH.
        'RR.HH. → Trabajadores',
        'RR.HH. → Planificación',
        'RR.HH. → Asistencias',
        'RR.HH. → Modo Kiosko',
        'RR.HH. → Licencias Médicas',
        'RR.HH. → Contratos',
        'RR.HH. → Liquidaciones',
        // Herramientas
        'Herramientas → WhatsApp Web',
        'Herramientas → Google Sheets',
        'Herramientas → Notion',
        'Herramientas → Analytics',
        // Standalone
        'Sitio Web',
        'Correo',
        'Configuración',
        'Dashboard',
        'Otro',
      ];

  // ─── Fetch bugs ─────────────────────────────────────────────────

  /// Fetches bug reports with optional filtering.
  Future<List<BugReport>> fetchBugs({
    String? statusFilter, // 'active', 'resolved', or null for all
    String? typeFilter, // 'bug', 'suggestion', or null for all
    String? moduleFilter,
    String? searchQuery,
  }) async {
    try {
      var query = _supabase
          .from('bug_reports')
          .select()
          .order('created_at', ascending: false);

      final data = await query;

      List<BugReport> bugs =
          (data as List).map((e) => BugReport.fromJson(e)).toList();

      // Apply client-side filters (Supabase PostgREST chaining can be tricky)
      if (statusFilter != null && statusFilter.isNotEmpty) {
        bugs = bugs.where((b) => b.status == statusFilter).toList();
      }
      if (typeFilter != null && typeFilter.isNotEmpty) {
        bugs = bugs.where((b) => b.type == typeFilter).toList();
      }
      if (moduleFilter != null && moduleFilter.isNotEmpty) {
        bugs = bugs.where((b) => b.module == moduleFilter).toList();
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        bugs = bugs
            .where((b) =>
                (b.title.toLowerCase().contains(q)) ||
                (b.description?.toLowerCase().contains(q) ?? false) ||
                (b.module?.toLowerCase().contains(q) ?? false) ||
                (b.reportedByName?.toLowerCase().contains(q) ?? false))
            .toList();
      }

      return bugs;
    } catch (e) {
      debugPrint('❌ [BugReportService] fetchBugs error: $e');
      rethrow;
    }
  }

  // ─── Create bug ─────────────────────────────────────────────────

  Future<BugReport> createBug({
    required String title,
    String type = 'bug',
    String? description,
    String? module,
    List<String> imageUrls = const [],
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      final tenantId = await _getTenantId();

      // Try to get the user's display name
      String? displayName;
      if (user != null) {
        try {
          final profile = await _supabase
              .from('user_profiles')
              .select('display_name, full_name')
              .eq('user_id', user.id)
              .maybeSingle();
          displayName = profile?['display_name'] as String? ??
              profile?['full_name'] as String? ??
              user.email?.split('@').first;
        } catch (_) {
          displayName = user.email?.split('@').first;
        }
      }

      final payload = {
        'tenant_id': tenantId,
        'title': title,
        'type': type,
        'description': description,
        'module': module,
        'status': 'active',
        'image_urls': imageUrls,
        'reported_by': user?.id,
        'reported_by_name': displayName,
      };

      final response =
          await _supabase.from('bug_reports').insert(payload).select().single();

      return BugReport.fromJson(response);
    } catch (e) {
      debugPrint('❌ [BugReportService] createBug error: $e');
      rethrow;
    }
  }

  // ─── Update bug ─────────────────────────────────────────────────

  Future<BugReport> updateBug(String id, Map<String, dynamic> updates) async {
    try {
      // If marking as resolved, set resolved_at
      if (updates['status'] == 'resolved') {
        updates['resolved_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (updates['status'] == 'active') {
        updates['resolved_at'] = null;
      }

      final response = await _supabase
          .from('bug_reports')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return BugReport.fromJson(response);
    } catch (e) {
      debugPrint('❌ [BugReportService] updateBug error: $e');
      rethrow;
    }
  }

  // ─── Toggle status ──────────────────────────────────────────────

  Future<BugReport> toggleStatus(BugReport bug) async {
    final newStatus = bug.isResolved ? 'active' : 'resolved';
    return updateBug(bug.id, {'status': newStatus});
  }

  // ─── Delete bug ─────────────────────────────────────────────────

  Future<void> deleteBug(String id) async {
    try {
      await _supabase.from('bug_reports').delete().eq('id', id);
    } catch (e) {
      debugPrint('❌ [BugReportService] deleteBug error: $e');
      rethrow;
    }
  }

  // ─── Upload screenshot ──────────────────────────────────────────

  /// Uploads a screenshot to the bug-screenshots bucket.
  /// Returns the public URL of the uploaded image.
  Future<String> uploadScreenshot({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final tenantId = await _getTenantId();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = '$tenantId/${timestamp}_$safeName';

      await _supabase.storage.from('bug-screenshots').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl =
          _supabase.storage.from('bug-screenshots').getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      debugPrint('❌ [BugReportService] uploadScreenshot error: $e');
      rethrow;
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────

  Future<String> _getTenantId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user');

    final profile = await _supabase
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', user.id)
        .single();

    return profile['tenant_id'] as String;
  }
}
