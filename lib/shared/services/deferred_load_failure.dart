/// A part of the program that the ERP on the web could not load.
///
/// The web build is split: what the first screen needs comes in
/// `main.dart.js`, and the rest of the ERP and the site editor in parts with
/// fixed names (`main.dart.js_N.part.js`), which the page fetches the first
/// time it needs them. After a deploy the server holds the next build's
/// parts, so a page opened before cannot load the ones it has not used yet:
/// dart2js tells it by the part's hash ([newBuild]). A download that failed,
/// or code that ran without its part, tells less ([unavailable]). Either
/// way nothing is wrong with the data or the operator's work: the page needs
/// a reload to go on (`DeferredLoadNotice` says so).
enum DeferredLoadFailure {
  /// The server holds another build: this page is older than the deploy.
  newBuild,

  /// The part did not arrive, or code ran without it.
  unavailable;

  /// The failure [error] reports, or `null` for any other error. Reads the
  /// messages dart2js writes (`DeferredLoadException`, and
  /// `DeferredNotLoadedError`'s «Deferred library … was not loaded.»).
  static DeferredLoadFailure? of(Object? error) {
    if (error == null) return null;
    final message = error.toString();
    if (message.startsWith('DeferredLoadException')) {
      return message.contains('the code with hash') ? newBuild : unavailable;
    }
    if (_notLoaded.hasMatch(message)) return unavailable;
    return null;
  }

  static final _notLoaded = RegExp(r'^Deferred library \S+ was not loaded\.');
}
