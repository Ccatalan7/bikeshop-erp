import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/payment_terminal_profile.dart';
import 'database_service.dart';

class PaymentTerminalProfileService extends ChangeNotifier {
  PaymentTerminalProfileService({required DatabaseService database})
      : _database = database;

  final DatabaseService _database;
  final List<PaymentTerminalProfile> _profiles = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<PaymentTerminalProfile> get profiles => List.unmodifiable(_profiles);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final profileRows = await _database.supabase
          .from('payment_terminal_profiles')
          .select()
          .order('provider_name')
          .order('terminal_name');
      final termRows = await _database.supabase
          .from('payment_terminal_terms')
          .select(
            '*, payment_methods!payment_terminal_terms_method_fk(code,name)',
          )
          .order('effective_from', ascending: false);
      final termsByProfile = <String, List<Map<String, dynamic>>>{};
      for (final raw in termRows) {
        final term = Map<String, dynamic>.from(raw);
        final method = term.remove('payment_methods');
        if (method is Map) {
          term['payment_method_code'] = method['code'];
          term['payment_method_name'] = method['name'];
        }
        final profileId = term['terminal_profile_id']?.toString() ?? '';
        termsByProfile.putIfAbsent(profileId, () => []).add(term);
      }
      _profiles
        ..clear()
        ..addAll(profileRows.map((raw) {
          final json = Map<String, dynamic>.from(raw);
          json['terms'] = termsByProfile[json['id']?.toString()] ?? const [];
          return PaymentTerminalProfile.fromJson(json);
        }));
    } catch (error, stack) {
      debugPrint('PaymentTerminalProfileService.load: $error\n$stack');
      _error = 'No se pudieron cargar los terminales de pago.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<PaymentTerminalProfile?> save(PaymentTerminalProfile profile) async {
    if (_isSaving) return null;
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final receipt = await _database.supabase.rpc(
        'save_payment_terminal_profile_v1',
        params: <String, dynamic>{
          'p_operation_key': const Uuid().v4(),
          'p_profile': profile.toProfileRpcJson(),
          'p_terms': profile.terms
              .map((term) => term.toRpcJson())
              .toList(growable: false),
        },
      );
      final receiptMap = Map<String, dynamic>.from(receipt as Map);
      final saved = PaymentTerminalProfile.fromJson(
        Map<String, dynamic>.from(receiptMap['profile'] as Map),
      );
      await load();
      return saved;
    } catch (error, stack) {
      debugPrint('PaymentTerminalProfileService.save: $error\n$stack');
      _error = _messageFor(error);
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('payment_terminal_profile_conflict')) {
      return 'Este terminal cambió en otra sesión. Recarga antes de guardar.';
    }
    if (text.contains('payment_terminal_account_invalid')) {
      return 'Selecciona una cuenta bancaria activa para recibir los abonos.';
    }
    if (text.contains('payment_terminal_ledger_account_invalid')) {
      return 'Las cuentas puente del terminal ya no están activas.';
    }
    if (text.contains('payment_terminal_ledger_accounts_immutable')) {
      return 'Las cuentas contables de un terminal con historial no se pueden '
          'reemplazar. Crea otro perfil para un contrato distinto.';
    }
    if (text.contains('payment_terminal_settlement_account_immutable')) {
      return 'Este terminal ya tiene cobros registrados. Para recibir abonos '
          'en otra cuenta bancaria, crea un perfil nuevo.';
    }
    return 'No se pudo guardar el terminal de pago.';
  }
}
