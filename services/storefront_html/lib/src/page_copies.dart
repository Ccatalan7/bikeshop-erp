import 'dart:async';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// The public pages this server already built, kept for as long as nothing
/// they show has changed.
///
/// Every visit used to build its page from scratch: the reads take ~0.4 s of
/// a ~0.45 s answer (2026-11-28), although between two visits nothing on the
/// page had changed. A kept page is answered from memory, and what decides
/// whether it still stands is the database's own word: [stamp]
/// (`get_public_storefront_change_stamp_v1`, about a millisecond) moves when
/// a price, a stock, a product or anything the site editor writes changes.
///
/// The stamp is read **before** a page is built and the copy is kept under
/// that stamp, so a change that lands while the page is being built finds a
/// copy with the old stamp and builds it again. The other order would keep a
/// page older than its stamp for as long as nothing else changes.
class PageCopies {
  PageCopies({
    required Future<String> Function() stamp,
    this.askEvery = const Duration(seconds: 1),
    this.askAgainAfterNoAnswer = const Duration(seconds: 5),
    this.answerWithin = const Duration(milliseconds: 1500),
    this.keptFor = const Duration(minutes: 30),
    this.trustedWithoutAnswerFor = const Duration(minutes: 5),
    this.maxBytes = 40 * 1024 * 1024,
    DateTime Function()? now,
  }) : _stamp = stamp,
       _now = now ?? DateTime.now;

  final Future<String> Function() _stamp;
  final DateTime Function() _now;

  /// How long the last answer about the stamp is trusted: an edit in the
  /// site editor reaches the pages within this time, and a sale within it
  /// plus what the database takes to count the write (up to ~10 s).
  final Duration askEvery;

  /// How long a question that got no answer waits before it is asked again:
  /// a database that is not answering is not asked every second.
  final Duration askAgainAfterNoAnswer;

  /// A stamp that takes longer than this counts as no answer: no visitor
  /// waits on a busy database to be handed a page that is already in memory.
  final Duration answerWithin;

  /// A kept page is built again after this long even with the same stamp:
  /// the limit for anything the stamp does not watch (a read added without
  /// its table, a function redeployed, a review's «hace 2 semanas»).
  final Duration keptFor;

  /// With the database not answering, a page whose stamp was confirmed less
  /// than this long ago is still handed out: better than «try again».
  final Duration trustedWithoutAnswerFor;

  /// The most memory the kept pages take; past it the ones asked for longest
  /// ago go first.
  final int maxBytes;

  String? _knownStamp;
  DateTime? _confirmedAt;
  DateTime? _askedAt;
  Future<String?>? _asking;

  /// In the order they were last asked for (a map literal keeps the order
  /// of insertion): the first is the next to go.
  final _copies = <String, _Copy>{};
  var _bytes = 0;

  /// The pages being built right now: a second visitor asking for the same
  /// one waits for it instead of reading the database again.
  final _building = <String, Future<_Copy?>>{};

  /// Pages kept right now; for tests.
  int get kept => _copies.length;

  /// Bytes the kept pages take; for tests.
  int get bytes => _bytes;

  /// The page for [key]: the kept one while its stamp stands, otherwise the
  /// one [build] makes, kept when [store] allows and it is a page worth
  /// keeping ([_keepable]).
  ///
  /// [store] is false for a request whose own address must not shape the
  /// page others get (an ad's click id): it may be handed the kept page, but
  /// the one built for it is not kept.
  Future<Response> answer(
    String key, {
    required Future<Response> Function() build,
    bool store = true,
  }) async {
    final watch = Stopwatch()..start();
    final stamp = await _currentStamp();
    final now = _now();
    final copy = _copies[key];
    if (stamp == null) {
      final confirmed = _confirmedAt;
      if (copy != null &&
          confirmed != null &&
          copy.stamp == _knownStamp &&
          now.difference(confirmed) < trustedWithoutAnswerFor &&
          now.difference(copy.builtAt) < keptFor) {
        return copy.response(now, watch.elapsedMilliseconds);
      }
      return build();
    }
    if (copy != null &&
        copy.stamp == stamp &&
        now.difference(copy.builtAt) < keptFor) {
      // Asked for again: the last to go.
      _copies
        ..remove(key)
        ..[key] = copy;
      return copy.response(now, watch.elapsedMilliseconds);
    }
    if (!store) return build();

    final underWay = _building[key];
    if (underWay != null) {
      final built = await underWay;
      return built == null
          ? build()
          : built.response(_now(), watch.elapsedMilliseconds);
    }
    final done = Completer<_Copy?>();
    _building[key] = done.future;
    try {
      final response = await build();
      if (!_keepable(response)) {
        done.complete(null);
        return response;
      }
      final built = _Copy(
        status: response.statusCode,
        headers: Map.of(response.headers)..remove('content-length'),
        body: await _bytesOf(response),
        stamp: stamp,
        builtAt: _now(),
      );
      _keep(key, built);
      done.complete(built);
      return built.response(null, 0);
    } on Object {
      // Whoever waited builds its own: this failure is this visitor's.
      if (!done.isCompleted) done.complete(null);
      rethrow;
    } finally {
      _building.remove(key);
    }
  }

  /// The stamp as of now: the last answer while it is fresh, a new one
  /// otherwise; `null` when the database gave none in time.
  Future<String?> _currentStamp() {
    final asked = _askedAt;
    if (asked != null) {
      final confirmed = _confirmedAt;
      final answered = confirmed != null && !confirmed.isBefore(asked);
      final since = _now().difference(asked);
      if (answered && since < askEvery) return Future.value(_knownStamp);
      // The last question got no answer: none until it is time to ask again.
      if (!answered && since < askAgainAfterNoAnswer) return Future.value();
    }
    return _asking ??= _ask().whenComplete(() => _asking = null);
  }

  Future<String?> _ask() async {
    String? stamp;
    try {
      stamp = await _stamp().timeout(answerWithin);
    } on Object {
      stamp = null;
    }
    final now = _now();
    _askedAt = now;
    if (stamp == null) return null;
    if (stamp != _knownStamp) {
      // Something a page shows changed: none of the kept ones stands.
      _copies.clear();
      _bytes = 0;
      _knownStamp = stamp;
    }
    _confirmedAt = now;
    return stamp;
  }

  void _keep(String key, _Copy copy) {
    final previous = _copies.remove(key);
    if (previous != null) _bytes -= previous.size(key);
    _copies[key] = copy;
    _bytes += copy.size(key);
    while (_bytes > maxBytes && _copies.length > 1) {
      final oldest = _copies.keys.first;
      _bytes -= _copies.remove(oldest)!.size(oldest);
    }
  }

  /// A page that was found and drawn here. Not a redirect or an error, and
  /// not the Flutter store's own document, which names files of a build
  /// this server does not watch.
  static bool _keepable(Response response) =>
      response.statusCode == 200 &&
      !response.headers.containsKey('x-storefront-fallback');

  static Future<Uint8List> _bytesOf(Response response) async {
    final all = BytesBuilder(copy: false);
    await for (final chunk in response.read()) {
      all.add(chunk);
    }
    return all.takeBytes();
  }
}

class _Copy {
  _Copy({
    required this.status,
    required this.headers,
    required this.body,
    required this.stamp,
    required this.builtAt,
  });

  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  final String stamp;
  final DateTime builtAt;

  /// What it takes in memory, near enough: its bytes, its key and headers.
  int size(String key) => body.length + key.length + 512;

  /// This page for one more visitor. A kept answer says so where the build
  /// said how long its reads and its drawing took: `kept` with the time this
  /// request took and how old the page is.
  Response response(DateTime? now, int elapsedMs) => Response(
    status,
    body: body,
    headers: {
      ...headers,
      if (now != null)
        'server-timing':
            'kept;dur=$elapsedMs;desc="${now.difference(builtAt).inSeconds} s"',
    },
  );
}

/// Where a request's page is kept, and whether the page built for it may be
/// kept for others ([PageCopies.answer]).
typedef PageCopyKey = ({String key, bool store});

/// What an ad, a mail or a social link adds to an address to count its
/// clicks. The browser reads them (Analytics, the pixel); the server draws
/// the same page with or without them.
bool isClickTrackingParameter(String name) =>
    name.startsWith('utm_') ||
    const {
      'fbclid',
      'gclid',
      'gbraid',
      'wbraid',
      'gad_source',
      'gad_campaignid',
      'gclsrc',
      'dclid',
      'srsltid',
      'msclkid',
      'ttclid',
      'twclid',
      'igshid',
      'mc_cid',
      'mc_eid',
      '_gl',
      '_ga',
    }.contains(name);

/// The key of a public page that reads the same for every visitor, or `null`
/// for everything else: the cart, the checkout, an order, a quote, the
/// customer's account, the search box and a search for a term, which are a
/// visitor's own or record what was asked.
///
/// - [catalog]: `/productos`, `/servicios` and their categories, which take
///   filters, a sort and a page in the query;
/// - the other kept pages (home, a product, a policy, contact, an editor
///   page, the guides) take no parameter: one this server does not know may
///   mean something to the page, so it is not answered from a kept copy.
///
/// Click-tracking parameters are left out of the key, and a request that
/// carries one is handed the kept page but its own is not kept: the page's
/// links repeat the address it was asked with.
PageCopyKey? pageCopyKey({
  required String path,
  required String query,
  required bool catalog,
  required bool gzip,
  bool part = false,
}) {
  var tracked = false;
  final own = <String>[];
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final String name;
    try {
      name = Uri.decodeQueryComponent(pair.split('=').first);
    } on Object {
      return null;
    }
    if (isClickTrackingParameter(name)) {
      tracked = true;
      continue;
    }
    if (!catalog) return null;
    // A search is the visitor's own words, and one without results is
    // recorded: read every time.
    if (const {'q', 'search', 'categoria'}.contains(name)) return null;
    own.add(pair);
  }
  return (
    key:
        '$path?${own.join('&')}'
        '|${gzip ? 'gzip' : 'plain'}${part ? '|part' : ''}',
    store: !tracked,
  );
}
