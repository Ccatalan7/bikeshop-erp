/// Alerts that belong to a supplier's legacy page must not become app-global
/// macOS dialogs. RBX uses this exact alert as its ordinary empty-result state;
/// the headless checker already consumes it as evidence, and the visible
/// browser can safely acknowledge it without blocking every other workspace.
bool shouldAutoConfirmBrowserAlert({
  required String pageUrl,
  required String? message,
}) {
  final uri = Uri.tryParse(pageUrl);
  final host = uri?.host.toLowerCase() ?? '';
  final isRbx = host == 'rburgos.cl' || host.endsWith('.rburgos.cl');
  if (!isRbx) return false;

  final normalized = (message ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
  return normalized == 'no hay ningun producto que mostrar en su busqueda';
}
