import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

/// A clock the test moves.
class _Clock {
  var now = DateTime.utc(2026, 11, 28, 8);
  DateTime call() => now;
  void pass(Duration time) => now = now.add(time);
}

/// The database's word on whether something changed, as the test sets it.
class _Stamp {
  var value = 'a';
  var asked = 0;

  /// Thrown instead of answering.
  Object? failure;

  /// Completed by the test to let the answer out.
  Completer<void>? hold;

  Future<String> call() async {
    asked++;
    await hold?.future;
    if (failure case final error?) throw error;
    return value;
  }
}

/// A page builder that counts its builds and says which one answered.
class _Builder {
  var built = 0;
  int status = 200;
  Map<String, String> headers = const {};
  Object? failure;
  Completer<void>? hold;
  void Function()? whileBuilding;

  Future<Response> call() async {
    final number = ++built;
    whileBuilding?.call();
    await hold?.future;
    if (failure case final error?) throw error;
    return Response(
      status,
      body: 'página $number',
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'server-timing': 'data;dur=400, render;dur=50',
        ...headers,
      },
    );
  }
}

void main() {
  late _Clock clock;
  late _Stamp stamp;
  late _Builder build;
  late PageCopies copies;

  setUp(() {
    clock = _Clock();
    stamp = _Stamp();
    build = _Builder();
    copies = PageCopies(stamp: stamp.call, now: clock.call);
  });

  Future<String> body(String key, {bool store = true}) async =>
      (await copies.answer(
        key,
        build: build.call,
        store: store,
      )).readAsString();

  test('a page is built once and answered from memory after that', () async {
    final first = await copies.answer('/', build: build.call);
    expect(await first.readAsString(), 'página 1');
    expect(first.headers['server-timing'], 'data;dur=400, render;dur=50');

    clock.pass(const Duration(seconds: 40));
    final second = await copies.answer('/', build: build.call);
    expect(await second.readAsString(), 'página 1');
    expect(second.statusCode, 200);
    expect(second.headers['content-type'], 'text/html; charset=utf-8');
    // A kept answer says so, with how old the page is.
    expect(second.headers['server-timing'], startsWith('kept;dur='));
    expect(second.headers['server-timing'], contains('desc="40 s"'));
    expect(build.built, 1);
    // Each page has its own copy.
    expect(await body('/productos'), 'página 2');
    expect(copies.kept, 2);
  });

  test('the stamp is trusted for a moment, then asked again', () async {
    await body('/');
    await body('/');
    await body('/productos');
    expect(stamp.asked, 1);
    clock.pass(const Duration(seconds: 3));
    await body('/');
    expect(stamp.asked, 2);
    expect(build.built, 2);
  });

  test('when the stamp moves every kept page is built again', () async {
    await body('/');
    await body('/productos');
    stamp.value = 'b';
    // Within the moment the last answer is trusted the page still stands.
    expect(await body('/'), 'página 1');
    clock.pass(const Duration(seconds: 3));
    expect(await body('/'), 'página 3');
    expect(await body('/productos'), 'página 4');
    expect(await body('/'), 'página 3');
  });

  test(
    'a change that lands while a page is built does not keep the old page',
    () async {
      // The stamp is read before the build: the copy is kept under the stamp
      // the database had then, so the change finds it stale.
      build.whileBuilding = () => stamp.value = 'b';
      expect(await body('/'), 'página 1');
      build.whileBuilding = null;
      clock.pass(const Duration(seconds: 3));
      expect(await body('/'), 'página 2');
      expect(await body('/'), 'página 2');
    },
  );

  test('a kept page is built again after half an hour', () async {
    await body('/');
    clock.pass(const Duration(minutes: 29));
    expect(await body('/'), 'página 1');
    clock.pass(const Duration(minutes: 2));
    expect(await body('/'), 'página 2');
  });

  test('a redirect, an error and the Flutter document are not kept', () async {
    build.status = 301;
    await body('/productos/viejo/1');
    await body('/productos/viejo/1');
    build.status = 503;
    await body('/');
    await body('/');
    build
      ..status = 200
      ..headers = {'x-storefront-fallback': 'flutter'};
    await body('/pagina/mapa');
    await body('/pagina/mapa');
    expect(build.built, 6);
    expect(copies.kept, 0);
  });

  test(
    'a request that may not keep its page still gets the kept one',
    () async {
      // An ad's click id: its own page would repeat the id in its links.
      expect(await body('/', store: false), 'página 1');
      expect(copies.kept, 0);
      expect(await body('/'), 'página 2');
      expect(await body('/', store: false), 'página 2');
      expect(build.built, 2);
    },
  );

  test('visitors asking for the same page at once share one build', () async {
    build.hold = Completer<void>();
    final answers = [
      copies.answer('/', build: build.call),
      copies.answer('/', build: build.call),
      copies.answer('/', build: build.call),
    ];
    await Future<void>.delayed(Duration.zero);
    build.hold!.complete();
    final bodies = [
      for (final answer in await Future.wait(answers))
        await answer.readAsString(),
    ];
    expect(bodies, ['página 1', 'página 1', 'página 1']);
    expect(build.built, 1);
  });

  test(
    'a build that fails is its visitor\'s; the rest build their own',
    () async {
      final failing = _Builder()
        ..failure = StateError('sin base')
        ..hold = Completer<void>();
      final first = copies.answer('/', build: failing.call);
      final second = copies.answer('/', build: build.call);
      await Future<void>.delayed(Duration.zero);
      failing.hold!.complete();
      await expectLater(first, throwsStateError);
      expect(await (await second).readAsString(), 'página 1');
      // Nothing was left behind: the next visitor builds and keeps.
      expect(await body('/'), 'página 2');
      expect(await body('/'), 'página 2');
    },
  );

  test('without the database\'s answer a page confirmed lately still goes '
      'out', () async {
    await body('/');
    clock.pass(const Duration(seconds: 3));
    stamp.failure = TimeoutException('base ocupada');
    final answer = await copies.answer('/', build: build.call);
    expect(await answer.readAsString(), 'página 1');
    expect(answer.headers['server-timing'], startsWith('kept;'));
    // A page that was never kept is built as always.
    expect(await body('/productos'), 'página 2');
    expect(copies.kept, 1);
    // Five minutes without a word: not trusted any more.
    clock.pass(const Duration(minutes: 6));
    expect(await body('/'), 'página 3');
  });

  test('a question that failed is not asked again at once', () async {
    await body('/');
    clock.pass(const Duration(seconds: 3));
    stamp.failure = TimeoutException('base ocupada');
    await body('/');
    clock.pass(const Duration(seconds: 3));
    await body('/');
    await body('/');
    expect(stamp.asked, 2);
    clock.pass(const Duration(seconds: 3));
    stamp.failure = null;
    expect(await body('/'), 'página 1');
    expect(stamp.asked, 3);
    expect(build.built, 1);
  });

  test('a stamp that takes too long counts as no answer', () async {
    copies = PageCopies(
      stamp: stamp.call,
      now: clock.call,
      answerWithin: const Duration(milliseconds: 20),
    );
    await body('/');
    clock.pass(const Duration(seconds: 3));
    stamp.hold = Completer<void>();
    expect(await body('/'), 'página 1');
    stamp.hold!.complete();
  });

  test('past its memory the pages asked for longest ago go first', () async {
    copies = PageCopies(stamp: stamp.call, now: clock.call, maxBytes: 2000);
    await body('/a');
    await body('/b');
    await body('/c');
    expect(copies.kept, 3);
    // `/a` is asked for again: `/b` is now the oldest.
    await body('/a');
    await body('/d');
    expect(copies.kept, 3);
    expect(copies.bytes, lessThanOrEqualTo(2000));
    expect(build.built, 4);
    await body('/a');
    await body('/c');
    await body('/d');
    expect(build.built, 4);
    await body('/b');
    expect(build.built, 5);
  });

  group('pageCopyKey', () {
    PageCopyKey? key(
      String query, {
      bool catalog = false,
      bool gzip = true,
      bool part = false,
    }) => pageCopyKey(
      path: '/productos/camara/C1',
      query: query,
      catalog: catalog,
      gzip: gzip,
      part: part,
    );

    test('a page is kept by its address and how it is sent', () {
      expect(key(''), (key: '/productos/camara/C1?|gzip', store: true));
      expect(key('', gzip: false)!.key, isNot(key('')!.key));
      // The product part the page script asks for alone is another answer.
      expect(key('', part: true)!.key, isNot(key('')!.key));
    });

    test('a click id is left out of the key and its page is not kept', () {
      for (final query in [
        'fbclid=IwAR0',
        'gclid=abc&utm_source=google&utm_medium=cpc',
        'srsltid=AfmBOo',
        '_gl=1*abc',
      ]) {
        expect(key(query), (
          key: '/productos/camara/C1?|gzip',
          store: false,
        ), reason: query);
      }
    });

    test('a parameter the page does not know is read every time', () {
      expect(key('talla=M'), isNull);
      expect(key('fbclid=x&talla=M'), isNull);
      expect(key('%E0%A4%A'), isNull);
    });

    test('a catalog keeps each filter, sort and page apart', () {
      final filtered = key('brand=a&page=2', catalog: true);
      expect(filtered, (
        key: '/productos/camara/C1?brand=a&page=2|gzip',
        store: true,
      ));
      expect(key('brand=a', catalog: true)!.key, isNot(filtered!.key));
      expect(key('brand=a&page=2&utm_source=mail', catalog: true), (
        key: filtered.key,
        store: false,
      ));
    });

    test('a search is the visitor\'s own: never kept', () {
      expect(key('q=camara', catalog: true), isNull);
      expect(key('search=camara', catalog: true), isNull);
      expect(key('categoria=mtb', catalog: true), isNull);
      expect(key('brand=a&q=camara', catalog: true), isNull);
    });
  });
}
