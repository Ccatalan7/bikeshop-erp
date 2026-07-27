/// Whether a standalone storefront route should use the shell's page scroll.
///
/// Conversation details own a fixed-height viewport and are the only public
/// routes that bypass the ordinary page scroll container.
bool publicStoreRouteUsesPageViewScrolling(String path) {
  final normalized = path.trim().toLowerCase();
  return !RegExp(r'^/cuenta/(?:mensajes|chats)/[^/]+/?$').hasMatch(normalized);
}
