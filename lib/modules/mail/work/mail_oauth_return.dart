import '../../../shared/services/deep_link_handler.dart';
import '../../../shared/utils/web_url.dart';

/// Hay un regreso de conectar Gmail o Zoho que todavía nadie canjea: en la
/// web el código llega en la dirección (`?gmail_code=…#/mail`) y en la app por
/// el enlace `vinabike://mail/oauth`. Lo canjea la bandeja del proveedor
/// (`/mail/bandeja`), así que `/mail` lo manda allá.
bool mailOAuthCallbackPending() =>
    hasCapturedMailOAuthCode() ||
    DeepLinkHandler.instance.hasPendingOAuthCallback;
