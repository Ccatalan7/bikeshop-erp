import '../providers/website_edit_mode_provider.dart';

/// Pure URI helpers for the Website Builder mode FSM.
///
/// The provider owns the mode; the URL is only an entry command plus a
/// write-through projection. These helpers are deliberately pure so the
/// route/provider adapter in the storefront layout stays deterministic,
/// without timers, pending flags or a second provider.
///
/// A malformed URL can contain both flags. Edit wins deterministically so
/// consumers never project Edit and Preview at the same time.
WebsiteEditorMode websiteEditorModeRequestFromUri(Uri uri) {
  final query = uri.queryParameters;
  if (query['edit'] == 'true') return WebsiteEditorMode.edit;
  if (query['preview'] == 'true') return WebsiteEditorMode.preview;
  return WebsiteEditorMode.public;
}

/// Projects [mode] onto [uri] as the canonical `edit`/`preview` query flags.
///
/// Foreign query parameters (including repeated values) and the fragment are
/// preserved untouched; only the two mode flags are owned by the projection.
Uri projectWebsiteEditorModeOntoUri(Uri uri, WebsiteEditorMode mode) {
  final query = Map<String, List<String>>.from(
    uri.queryParametersAll.map(
      (key, values) => MapEntry(key, List<String>.from(values)),
    ),
  )
    ..remove('edit')
    ..remove('preview');
  switch (mode) {
    case WebsiteEditorMode.edit:
      query['edit'] = const <String>['true'];
    case WebsiteEditorMode.preview:
      query['preview'] = const <String>['true'];
    case WebsiteEditorMode.public:
      break;
  }
  return Uri(
    scheme: uri.hasScheme ? uri.scheme : null,
    userInfo:
        uri.hasAuthority && uri.userInfo.isNotEmpty ? uri.userInfo : null,
    host: uri.hasAuthority ? uri.host : null,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}

/// True when [uri] already projects [mode] (no stale or missing mode flags).
///
/// The comparison is semantic — request round-trip plus foreign-query
/// equality — never raw string equality, so a history entry whose foreign
/// parameters merely differ in ordering/encoding from the canonical
/// projection cannot trigger an endless corrective write-through on every
/// browser Back visit.
bool uriProjectsWebsiteEditorMode(Uri uri, WebsiteEditorMode mode) {
  if (websiteEditorModeRequestFromUri(uri) != mode) return false;
  // Both mode flags must be canonical: exactly the projected flag, no stale
  // sibling (e.g. `?edit=true&preview=true` parses as edit but is not a
  // faithful projection).
  final query = uri.queryParametersAll;
  final hasEdit = query.containsKey('edit');
  final hasPreview = query.containsKey('preview');
  switch (mode) {
    case WebsiteEditorMode.edit:
      return hasEdit && !hasPreview && query['edit']!.length == 1;
    case WebsiteEditorMode.preview:
      return hasPreview && !hasEdit && query['preview']!.length == 1;
    case WebsiteEditorMode.public:
      return !hasEdit && !hasPreview;
  }
}
