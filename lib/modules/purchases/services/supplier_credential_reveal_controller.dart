import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/models/current_user_profile.dart';
import '../../../shared/services/current_user_profile_service.dart';
import 'supplier_credential_service.dart';

typedef SupplierCredentialRevealTimerFactory = Timer Function(
  Duration duration,
  VoidCallback callback,
);

@immutable
class SupplierCredentialRevealTarget {
  SupplierCredentialRevealTarget({
    required this.supplierId,
    required this.kind,
    required this.credentialKey,
  }) {
    if (supplierId.trim().isEmpty) {
      throw ArgumentError.value(supplierId, 'supplierId', 'Required');
    }
    if (!RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(credentialKey)) {
      throw ArgumentError.value(
        credentialKey,
        'credentialKey',
        'Use a lowercase stable key',
      );
    }
  }

  final String supplierId;
  final SupplierCredentialKind kind;
  final String credentialKey;

  @override
  String toString() =>
      'SupplierCredentialRevealTarget(supplierId: $supplierId, kind: ${kind.dbValue}, key: $credentialKey)';
}

/// Owns one short-lived revealed supplier credential for a UI consumer.
///
/// The controller deliberately exposes no serializable state object. The
/// secret is available only through [revealedSecret] while visible and while
/// the captured auth/profile authority is still current. Hiding, expiry,
/// disposal, logout, profile replacement, tenant change, or permission loss
/// destroys the in-memory credential and invalidates any delayed RPC result.
class SupplierCredentialRevealController extends ChangeNotifier {
  SupplierCredentialRevealController({
    required SupplierCredentialService credentialService,
    required CurrentUserProfileService profileService,
    this.ttl = const Duration(seconds: 30),
    Stream<Object?>? authorityEvents,
    String? Function()? currentAuthUserId,
    SupplierCredentialRevealTimerFactory? timerFactory,
  })  : _credentialService = credentialService,
        _profileService = profileService,
        _currentAuthUserId =
            currentAuthUserId ?? (() => credentialService.currentAuthUserId),
        _timerFactory = timerFactory ?? Timer.new {
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'Must be positive');
    }
    _profileService.addListener(_handleAuthorityEvent);
    _authoritySubscription =
        (authorityEvents ?? credentialService.authorityEvents)
            ?.listen((_) => _handleAuthorityEvent());
  }

  final SupplierCredentialService _credentialService;
  final CurrentUserProfileService _profileService;
  final String? Function() _currentAuthUserId;
  final SupplierCredentialRevealTimerFactory _timerFactory;
  final Duration ttl;

  StreamSubscription<Object?>? _authoritySubscription;
  SupplierCredential? _credential;
  SupplierCredentialRevealTarget? _target;
  _SupplierCredentialRevealAuthority? _authority;
  Timer? _expiryTimer;
  bool _isRevealing = false;
  bool _isVisible = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isRevealing => _isRevealing;

  bool get isVisible {
    _clearIfAuthorityChanged();
    return _isVisible && _credential != null;
  }

  SupplierCredentialRevealTarget? get target {
    _clearIfAuthorityChanged();
    return _target;
  }

  SupplierCredentialMetadata? get metadata {
    _clearIfAuthorityChanged();
    return _isVisible ? _credential?.metadata : null;
  }

  String? get revealedUsername {
    _clearIfAuthorityChanged();
    return _isVisible ? _credential?.username : null;
  }

  String? get revealedSecret {
    _clearIfAuthorityChanged();
    return _isVisible ? _credential?.secret : null;
  }

  Future<bool> reveal(SupplierCredentialRevealTarget target) async {
    if (_disposed) return false;
    final authority = _captureAuthority();
    if (authority == null) {
      _clear(notify: true);
      throw const SupplierCredentialAccessDenied();
    }
    _clear(notify: false);
    final generation = ++_generation;
    _target = target;
    _authority = authority;
    _isRevealing = true;
    notifyListeners();
    try {
      final credential = await _credentialService.get(
        supplierId: target.supplierId,
        kind: target.kind,
        credentialKey: target.credentialKey,
      );
      if (_disposed ||
          generation != _generation ||
          !_ownsAuthority(authority) ||
          !_matchesTarget(credential?.metadata, target)) {
        return false;
      }
      if (credential == null) {
        _clear(notify: true);
        return false;
      }
      _credential = credential;
      _isRevealing = false;
      _isVisible = true;
      _expiryTimer = _timerFactory(ttl, _expire);
      notifyListeners();
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _clear(notify: true);
      }
      rethrow;
    } finally {
      if (!_disposed && generation == _generation && _isRevealing) {
        _isRevealing = false;
        notifyListeners();
      }
    }
  }

  /// Hiding is destructive: a later show always requires another audited RPC.
  void hide() => _clear(notify: true);

  void clear() => _clear(notify: true);

  void _expire() => _clear(notify: true);

  _SupplierCredentialRevealAuthority? _captureAuthority() {
    final profile = _profileService.profile;
    final authUserId = _currentAuthUserId();
    if (profile == null ||
        authUserId != profile.userId ||
        !profile.canManageSupplierCredentials) {
      return null;
    }
    return _SupplierCredentialRevealAuthority(
      profile: profile,
      userId: profile.userId,
      tenantId: profile.tenantId,
    );
  }

  bool _ownsAuthority(_SupplierCredentialRevealAuthority authority) {
    final profile = _profileService.profile;
    return _currentAuthUserId() == authority.userId &&
        identical(profile, authority.profile) &&
        profile?.userId == authority.userId &&
        profile?.tenantId == authority.tenantId &&
        profile?.canManageSupplierCredentials == true;
  }

  void _handleAuthorityEvent() {
    if (_disposed) return;
    final authority = _authority;
    if (authority != null && !_ownsAuthority(authority)) {
      _clear(notify: true);
    }
  }

  void _clearIfAuthorityChanged() {
    final authority = _authority;
    if (authority != null && !_ownsAuthority(authority)) {
      _clear(notify: false);
    }
  }

  void _clear({required bool notify}) {
    final hadState = _credential != null ||
        _target != null ||
        _authority != null ||
        _isRevealing ||
        _isVisible ||
        _expiryTimer != null;
    _generation++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _credential = null;
    _target = null;
    _authority = null;
    _isRevealing = false;
    _isVisible = false;
    if (notify && hadState && !_disposed) notifyListeners();
  }

  bool _matchesTarget(
    SupplierCredentialMetadata? metadata,
    SupplierCredentialRevealTarget target,
  ) {
    return metadata != null &&
        metadata.supplierId == target.supplierId &&
        metadata.kind == target.kind &&
        metadata.credentialKey == target.credentialKey;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _profileService.removeListener(_handleAuthorityEvent);
    unawaited(_authoritySubscription?.cancel());
    _authoritySubscription = null;
    _clear(notify: false);
    super.dispose();
  }
}

class _SupplierCredentialRevealAuthority {
  const _SupplierCredentialRevealAuthority({
    required this.profile,
    required this.userId,
    required this.tenantId,
  });

  final CurrentUserProfile profile;
  final String userId;
  final String tenantId;
}
