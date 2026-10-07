import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/deferred_load_failure.dart';

void main() {
  test('a part that arrives without this build\'s hash is a new build', () {
    // What a page left behind by a deploy reports: the script downloads,
    // registers the next build's hash, and dart2js retries three times.
    expect(
      DeferredLoadFailure.of(
        const _Reported(
            "DeferredLoadException: 'Loading https://project-vinabike.web.app/"
            'main.dart.js_22.part.js?dart2jsRetry=3 failed: Success callback '
            'invoked but part main.dart.js_22.part.js not loaded.\nContext: '
            "\nevent log:\n'"),
      ),
      DeferredLoadFailure.newBuild,
    );
    expect(
      DeferredLoadFailure.of(
        const _Reported("DeferredLoadException: 'Loading main.dart.js_1.part.js"
            ';main.dart.js_2.part.js failed: Success callback invoked but '
            "parts main.dart.js_1.part.js;main.dart.js_2.part.js not loaded.'"),
      ),
      DeferredLoadFailure.newBuild,
    );
  });

  test('a part missing when the parts are initialized is a new build', () {
    // As dart2js words it when the server holds the next build's part.
    const message = "DeferredLoadException: 'Loading main.dart.js_1.part.js "
        "failed: the code with hash 'BHBtdaaq1hFtPQrfqcGLK/9I19s=' was not "
        "loaded.\nevent log:\n'";
    expect(
      DeferredLoadFailure.of(const _Reported(message)),
      DeferredLoadFailure.newBuild,
    );
  });

  test('a download that failed, or code run without its part, is unavailable',
      () {
    expect(
      DeferredLoadFailure.of(
        const _Reported(
            "DeferredLoadException: 'Loading main.dart.js_2.part.js "
            "failed: TypeError: Failed to fetch\nContext: \n'"),
      ),
      DeferredLoadFailure.unavailable,
    );
    // What the ERP showed as «Algo salió mal» on 2026-10-07.
    expect(
      DeferredLoadFailure.of(
          const _Reported('Deferred library erp was not loaded.')),
      DeferredLoadFailure.unavailable,
    );
  });

  test('any other error is not a load failure', () {
    expect(DeferredLoadFailure.of(null), isNull);
    expect(DeferredLoadFailure.of(StateError('Bad state')), isNull);
    expect(
      DeferredLoadFailure.of(
        const _Reported('Exception: the code with hash was not loaded'),
      ),
      isNull,
    );
    expect(
      DeferredLoadFailure.of(const _Reported('Library erp was not loaded.')),
      isNull,
    );
  });
}

/// An error that reports [message], as dart2js's errors do.
class _Reported {
  const _Reported(this.message);

  final String message;

  @override
  String toString() => message;
}
