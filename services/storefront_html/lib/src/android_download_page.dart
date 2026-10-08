import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/android_download_words.dart';
import 'package:vinabike_public_core/shared/models/android_release_manifest.dart';

import 'material_icons.dart';
import 'portal_page_route.dart';
import 'public_reads.dart';
import 'site_layout.dart';

/// The team's private Android download, which Flutter drew until 2026-10-08
/// (`AndroidAppDownloadPage`): the team signs in, the store reads the latest
/// release's manifest as that account (Storage's row security decides who
/// sees it) and the browser downloads the APK's parts, checks each one's
/// SHA-256 and the whole file's, and saves it.
const androidDownloadPath = '/cuenta/descargas/android';

/// `POST` with the session and `{parts}`: the release, and with `parts` the
/// signed links of its pieces (`MobileReleaseRepository`).
const androidReleasePath = '/cuenta/descargas/android/version';

/// `MobileReleaseRepository.bucketName`.
const _bucket = 'erp-mobile-releases';

Component androidDownloadDocument(PageContext page) {
  final prefix = page.hidden ? '/_html' : '';
  return sitePage(
    context: page,
    meta: androidDownloadMeta(page),
    content: [
      div(
        classes: 'ad',
        attributes: {
          'data-android': '',
          'data-state': 'loading',
          'data-release-url': '$prefix$androidReleasePath',
        },
        [
          h1(classes: 'ad-title', [.text(androidDownloadTitle)]),
          p(classes: 'ad-lead', [.text(androidDownloadLead)]),
          div(
            classes: 'ad-wait',
            attributes: {'data-only': 'loading', 'role': 'status'},
            [RawText(_spinner)],
          ),
          _signIn(),
          _release(),
          _none(),
          p(
            classes: 'ad-error',
            attributes: {'data-error': '', 'role': 'alert', 'hidden': ''},
            const [],
          ),
          Component.element(
            tag: 'noscript',
            children: [
              p(classes: 'ad-lead', [
                .text('Activa JavaScript para descargar la aplicación.'),
              ]),
            ],
          ),
        ],
      ),
    ],
    pageScripts: [script(content: _script)],
  );
}

/// Never indexed: a page for the team, the same for every visitor.
PageMeta androidDownloadMeta(PageContext page) => PageMeta(
  title: '$androidDownloadTitle | ${page.shell.storeName}',
  description: androidDownloadLead,
  canonicalUrl: '${page.storeUrl}$androidDownloadPath',
  indexable: false,
  styles: _css(WebsiteThemeRoles.resolve(page.shell.setting)),
);

Component _signIn() => Component.element(
  tag: 'form',
  classes: 'ad-card',
  attributes: {
    'data-only': 'signin',
    'data-signin': '',
    'method': 'post',
    'novalidate': '',
  },
  children: [
    h2(classes: 'ad-h2', [.text(androidDownloadSignInTitle)]),
    _field('email', androidDownloadEmailLabel, 'email', 'username'),
    _field(
      'password',
      androidDownloadPasswordLabel,
      'password',
      'current-password',
    ),
    button(
      classes: 'ad-primary',
      attributes: {'type': 'submit', 'data-submit': ''},
      [
        span(attributes: {'data-idle': ''}, [.text(androidDownloadSignIn)]),
        span(
          attributes: {'data-busy': '', 'hidden': ''},
          [.text(androidDownloadSigningIn)],
        ),
      ],
    ),
  ],
);

Component _field(String name, String label, String type, String autocomplete) {
  final id = 'ad-$name';
  return div(
    classes: 'ad-field',
    attributes: {'data-field': name},
    [
      Component.element(
        tag: 'label',
        attributes: {'for': id},
        children: [.text(label)],
      ),
      input(
        attributes: {
          'id': id,
          'name': name,
          'type': type,
          'autocomplete': autocomplete,
          if (type == 'email') 'autocapitalize': 'none',
          'spellcheck': 'false',
          'aria-describedby': '$id-m',
        },
      ),
      p(classes: 'ad-msg', attributes: {'id': '$id-m'}, const []),
    ],
  );
}

Component _release() => div(
  classes: 'ad-card',
  attributes: {'data-only': 'release'},
  [
    div(classes: 'ad-head', [
      h2(classes: 'ad-h2', attributes: {'data-version': ''}, const []),
      button(
        classes: 'ad-text',
        attributes: {'type': 'button', 'data-signout': ''},
        [.text(androidDownloadSignOut)],
      ),
    ]),
    p(classes: 'ad-summary', attributes: {'data-summary': ''}, const []),
    Component.element(
      tag: 'dl',
      classes: 'ad-meta',
      children: [
        div([
          Component.element(
            tag: 'dt',
            children: [.text(androidDownloadSizeLabel)],
          ),
          Component.element(
            tag: 'dd',
            attributes: {'data-size': ''},
            children: const [],
          ),
        ]),
        div([
          Component.element(
            tag: 'dt',
            children: [.text(androidDownloadCheckLabel)],
          ),
          Component.element(
            tag: 'dd',
            attributes: {'data-check': ''},
            children: const [],
          ),
        ]),
      ],
    ),
    button(
      classes: 'ad-primary',
      attributes: {'type': 'button', 'data-download': ''},
      [
        RawText(materialIcon(mdAndroidRounded, size: 20)),
        span(attributes: {'data-label': ''}, [.text(androidDownloadButton)]),
      ],
    ),
    div(
      classes: 'ad-bar',
      attributes: {'data-bar': '', 'hidden': '', 'role': 'progressbar'},
      [span(const [])],
    ),
    p(classes: 'ad-note', [.text(androidDownloadNote)]),
  ],
);

Component _none() => div(
  classes: 'ad-card',
  attributes: {'data-only': 'none'},
  [
    p([.text(androidDownloadNone)]),
    button(
      classes: 'ad-outline',
      attributes: {'type': 'button', 'data-signout': ''},
      [.text(androidDownloadOtherAccount)],
    ),
  ],
);

const _spinner =
    '<svg viewBox="0 0 36 36" width="36" height="36" aria-hidden="true">'
    '<circle cx="18" cy="18" r="15" fill="none" stroke="currentColor" '
    'stroke-width="3"/></svg>';

String _css(WebsiteThemeRoles roles) {
  final head = roles.headingFont.trim();
  final body = roles.bodyFont.trim();
  return '''
.ad{--ad-ink:${roles.onSurface.css};--ad-ink2:${roles.onSurfaceVariant.css};--ad-line:${roles.outlineVariant.css};--ad-fill:${roles.surfaceContainerLow.css};--ad-prim:${roles.primary.css};--ad-onprim:${roles.onPrimary.css};--ad-err:${roles.isDark ? '#f2b8b5' : '#b3261e'};box-sizing:border-box;max-width:592px;margin:0 auto;padding:40px 16px 64px;color:var(--ad-ink);font-family:"$body",var(--body),sans-serif}
.ad *,.ad *::before,.ad *::after{box-sizing:border-box}
.ad [hidden]{display:none!important}
.ad[data-state=loading] [data-only]:not([data-only=loading]),.ad[data-state=signin] [data-only]:not([data-only=signin]),.ad[data-state=release] [data-only]:not([data-only=release]),.ad[data-state=none] [data-only]:not([data-only=none]){display:none!important}
.ad-title{margin:0;font:700 clamp(26px,5vw,32px)/1.2 "$head",var(--head),sans-serif;letter-spacing:-.01em;text-wrap:balance}
.ad-lead{margin:8px 0 24px;font-size:17px;line-height:1.5;color:var(--ad-ink2)}
.ad-wait{display:flex;justify-content:center;padding:32px;color:var(--ad-prim)}
.ad-wait svg{animation:ad-spin 1.2s linear infinite}
.ad-wait circle{stroke-dasharray:70 25}
@keyframes ad-spin{to{transform:rotate(360deg)}}
.ad-card{display:flex;flex-direction:column;gap:16px;padding:20px;border:1px solid var(--ad-line);border-radius:16px;background:var(--ad-fill)}
.ad-h2{margin:0;font:600 18px/1.35 "$head",var(--head),sans-serif}
.ad-field{display:flex;flex-direction:column;gap:6px}
.ad-field label{font-size:13px;font-weight:700}
.ad-field input{height:48px;padding:0 14px;border:1px solid var(--ad-line);border-radius:10px;background:#fff;color:#1e293b;font:inherit;font-size:16px;outline:0}
.ad-field input:focus{border-color:var(--ad-prim);box-shadow:0 0 0 1px var(--ad-prim)}
.ad-field.bad input{border-color:var(--ad-err)}
.ad-msg{display:none;margin:0;font-size:13px;color:var(--ad-err)}
.ad-field.bad .ad-msg{display:block}
.ad-primary{display:flex;align-items:center;justify-content:center;gap:10px;min-height:48px;padding:0 20px;border:0;border-radius:12px;background:var(--ad-prim);color:var(--ad-onprim);font:inherit;font-size:15px;font-weight:700;cursor:pointer}
.ad-primary:disabled{opacity:.6;cursor:default}
.ad-outline{min-height:44px;padding:0 18px;border:1px solid var(--ad-line);border-radius:12px;background:transparent;color:var(--ad-ink);font:inherit;font-weight:600;cursor:pointer}
.ad-text{min-height:40px;padding:0 12px;border:0;border-radius:8px;background:transparent;color:var(--ad-prim);font:inherit;font-weight:700;cursor:pointer}
.ad-text:hover,.ad-outline:hover{background:rgb(0 0 0 / .05)}
.ad button:focus-visible,.ad input:focus-visible{outline:2px solid var(--ad-prim);outline-offset:2px}
.ad-head{display:flex;align-items:center;justify-content:space-between;gap:12px}
.ad-head .ad-h2{font-size:22px}
.ad-summary{margin:0;line-height:1.5;color:var(--ad-ink2)}
.ad-meta{display:grid;gap:6px;margin:0}
.ad-meta div{display:flex;justify-content:space-between;gap:12px;font-size:14px}
.ad-meta dt{color:var(--ad-ink2)}
.ad-meta dd{margin:0;font-weight:600;font-variant-numeric:tabular-nums}
.ad-bar{height:6px;border-radius:3px;background:var(--ad-line);overflow:hidden}
.ad-bar span{display:block;width:0;height:100%;background:var(--ad-prim);transition:width .2s}
.ad-note{margin:0;font-size:13px;line-height:1.5;color:var(--ad-ink2)}
.ad-error{margin:16px 0 0;font-weight:600;color:var(--ad-err)}
''';
}

const _words = {
  'signInFailed': androidDownloadSignInFailed,
  'unpublished': androidDownloadUnpublished,
  'forbidden': androidDownloadForbidden,
  'failed': androidDownloadLoadFailed,
  'downloadFailed': androidDownloadFailed,
  'button': androidDownloadButton,
  'defaultSummary': androidDownloadDefaultSummary,
};

/// The words the script fills in, from the same functions Flutter calls.
final _templates = {
  'emailError': androidDownloadEmailError('')!,
  'passwordError': androidDownloadPasswordError('')!,
  'progress': androidDownloadProgress('{n}'),
  'version': androidDownloadVersion('{v}'),
};

final _script =
    r'''
(function () {
  'use strict';
  var root = document.querySelector('[data-android]');
  if (!root) return;
  var W = /*WORDS*/{};
  var body = document.body;
  var sbUrl = (body.dataset.sbUrl || '').replace(/\/+$/, ''), sbKey = body.dataset.sbKey || '';
  var releaseUrl = root.dataset.releaseUrl;
  var session = window.vinabikeSession;
  var errorEl = root.querySelector('[data-error]');
  var form = root.querySelector('[data-signin]');
  var downloadButton = root.querySelector('[data-download]');
  var release = null, busy = false;

  function state(next) { root.dataset.state = next; }
  function error(message) { errorEl.textContent = message || ''; errorEl.hidden = !message; }
  function jwtExp(token) {
    try { return JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp || 0; } catch (e) { return 0; }
  }
  // A session kept only by this page, when the browser keeps nothing.
  var fresh = null;
  function current() { return fresh ? Promise.resolve(fresh) : session ? session.current() : Promise.resolve(null); }
  // The release as this account may read it, and with [parts] its pieces'
  // links. A token Storage refuses before it expires is renewed once.
  function ask(parts, renewed) {
    return (renewed ? session.renew() : current()).then(function (s) {
      if (!s) return { state: 'signin' };
      return fetch(releaseUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer ' + s.access_token },
        body: JSON.stringify({ parts: !!parts })
      }).then(function (r) { return r.json(); }).then(function (answer) {
        if (!answer || answer.state !== 'expired') return answer;
        return renewed || fresh || !session ? { state: 'signin' } : ask(parts, true);
      });
    });
  }
  function mb(bytes) { return (bytes / (1024 * 1024)).toFixed(1) + ' MB'; }

  // `_loadRelease`: no session, the way in; with one, what Storage lets this
  // account read.
  function load() {
    error('');
    state('loading');
    ask(false).then(function (answer) {
      release = null;
      if (answer && answer.state === 'signin') { state('signin'); return; }
      if (answer && answer.state === 'ready') {
        release = answer;
        root.querySelector('[data-version]').textContent = W.version.replace('{v}', answer.version);
        root.querySelector('[data-summary]').textContent = answer.summary || W.defaultSummary;
        root.querySelector('[data-size]').textContent = mb(answer.size);
        root.querySelector('[data-check]').textContent = answer.sha256.slice(0, 12) + '…';
        state('release');
        return;
      }
      state('none');
      error(W[answer && answer.state] || W.failed);
    }).catch(function () { release = null; state('none'); error(W.failed); });
  }

  // `signInWithPassword`, kept where `supabase_flutter` keeps the session.
  form.addEventListener('submit', function (event) {
    event.preventDefault();
    if (busy) return;
    var email = form.email.value.trim(), password = form.password.value;
    var errors = { email: email.indexOf('@') >= 0 ? '' : W.emailError, password: password ? '' : W.passwordError };
    Array.prototype.forEach.call(form.querySelectorAll('[data-field]'), function (box) {
      var message = errors[box.dataset.field];
      box.classList.toggle('bad', !!message);
      box.querySelector('.ad-msg').textContent = message;
    });
    if (errors.email || errors.password) return;
    busy = true;
    error('');
    var submit = form.querySelector('[data-submit]');
    submit.disabled = true;
    submit.querySelector('[data-idle]').hidden = true;
    submit.querySelector('[data-busy]').hidden = false;
    fetch(sbUrl + '/auth/v1/token?grant_type=password', {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json;charset=UTF-8' },
      body: JSON.stringify({ email: email, password: password, gotrue_meta_security: { captcha_token: null } })
    }).then(function (r) { return r.ok ? r.json() : null; }).then(function (r) {
      if (!r || !r.access_token || !r.user) throw new Error('refused');
      var kept = {
        access_token: r.access_token, expires_in: r.expires_in, expires_at: r.expires_at || jwtExp(r.access_token),
        refresh_token: r.refresh_token, token_type: r.token_type || 'bearer',
        provider_token: null, provider_refresh_token: null, user: r.user
      };
      try {
        if (!session) throw new Error('no helper');
        localStorage.setItem(session.key, JSON.stringify(kept));
      } catch (e) { fresh = kept; }
      form.password.value = '';
      // The store's helper (and its header) read it from a new page.
      if (!fresh) { location.reload(); return new Promise(function () {}); }
      load();
    }).catch(function () { error(W.signInFailed); }).then(function () {
      busy = false;
      submit.disabled = false;
      submit.querySelector('[data-idle]').hidden = false;
      submit.querySelector('[data-busy]').hidden = true;
    });
  });

  // `_signOut`: «Salir» and «Usar otra cuenta».
  root.addEventListener('click', function (event) {
    if (!event.target.closest('[data-signout]') || busy) return;
    var leaving = fresh;
    fresh = null;
    (leaving
      ? fetch(sbUrl + '/auth/v1/logout?scope=local', {
          method: 'POST', headers: { apikey: sbKey, authorization: 'Bearer ' + leaving.access_token }
        }).catch(function () { return null; })
      : session ? session.signOut() : Promise.resolve()).then(function () {
      release = null;
      error('');
      state('signin');
    });
  });

  // `_downloadApk`: each part from its signed link, checked by size and
  // SHA-256, then the whole file; saved under the release's own name.
  function hex(buffer) {
    return Array.prototype.map.call(new Uint8Array(buffer), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  downloadButton.addEventListener('click', function () {
    if (!release || busy) return;
    busy = true;
    error('');
    var label = downloadButton.querySelector('[data-label]');
    var bar = root.querySelector('[data-bar]'), fill = bar.querySelector('span');
    downloadButton.disabled = true;
    bar.hidden = false;
    var progress = function (done) {
      var n = Math.round(done / release.size * 100);
      label.textContent = W.progress.replace('{n}', n);
      fill.style.width = n + '%';
      bar.setAttribute('aria-valuenow', String(n));
    };
    progress(0);
    // Allocated inside the chain: a phone without the memory says the
    // download failed and frees the button (Codex 9).
    var whole = null, offset = 0;
    ask(true).then(function (answer) {
      if (!answer || answer.state !== 'ready' || answer.sha256 !== release.sha256 || !answer.parts) throw new Error('release');
      whole = new Uint8Array(release.size);
      return answer.parts.reduce(function (chain, part) {
        return chain.then(function () {
          return fetch(part.url).then(function (r) {
            if (!r.ok) throw new Error('part');
            return r.arrayBuffer();
          }).then(function (buffer) {
            if (buffer.byteLength !== part.size || offset + buffer.byteLength > whole.length) throw new Error('size');
            return crypto.subtle.digest('SHA-256', buffer).then(function (digest) {
              if (hex(digest) !== part.sha256) throw new Error('digest');
              whole.set(new Uint8Array(buffer), offset);
              offset += buffer.byteLength;
              progress(offset);
            });
          });
        });
      }, Promise.resolve());
    }).then(function () {
      if (offset !== release.size) throw new Error('incomplete');
      return crypto.subtle.digest('SHA-256', whole);
    }).then(function (digest) {
      if (hex(digest) !== release.sha256) throw new Error('digest');
      var url = URL.createObjectURL(new Blob([whole], { type: 'application/vnd.android.package-archive' }));
      whole = null;
      var a = document.createElement('a');
      a.href = url;
      a.download = release.file;
      a.style.display = 'none';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
    }).catch(function () { whole = null; error(W.downloadFailed); }).then(function () {
      busy = false;
      downloadButton.disabled = false;
      label.textContent = W.button;
      bar.hidden = true;
      fill.style.width = '0';
    });
  });

  load();
})();
'''
        .replaceFirst('/*WORDS*/{}', jsonEncode({..._words, ..._templates}));

/// `POST /cuenta/descargas/android/version`: the latest release as the
/// session's account may read it (`fetchLatestAndroidRelease`), checked by
/// the same rules (`AndroidReleaseManifest`); with `{parts: true}` also its
/// pieces' links, signed for ten minutes at the moment of the download.
Future<Response> androidReleaseResponse(
  Request request, {
  required PublicReads reads,
  required String tenantId,
}) async {
  final token = requestBearer(request);
  // Read up to a kilobyte and no further (Codex 9: a large body was read
  // whole before it was refused).
  final body = await requestJsonBody(request, limit: 1024);
  Response answer(Map<String, Object?> json, [int status = 200]) => Response(
    status,
    body: jsonEncode(json),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
    },
  );
  if (token == null || body == null) return answer({'state': 'invalid'}, 400);
  try {
    return answer(
      await androidRelease(
        reads,
        token,
        tenantId: tenantId,
        parts: body['parts'] == true,
      ),
    );
  } on CustomerSessionRefused {
    return answer({'state': 'expired'});
  } on Object catch (error) {
    stderr.writeln('android release failed: ${error.runtimeType}');
    return answer({'state': 'failed'});
  }
}

/// The answer behind [androidReleaseResponse].
Future<Map<String, Object?>> androidRelease(
  PublicReads reads,
  String token, {
  required String tenantId,
  bool parts = false,
}) async {
  final String manifestUrl;
  try {
    manifestUrl = await reads.customerSignedObject(
      token,
      _bucket,
      AndroidReleaseManifest.latestManifestPath(tenantId),
      expiresIn: 60,
    );
  } on StorageRefused catch (refused) {
    // As Flutter reads `StorageException.statusCode`.
    return {'state': refused.statusCode == '404' ? 'unpublished' : 'forbidden'};
  }
  final bytes = await reads.signedObjectBytes(
    manifestUrl,
    maxBytes: 128 * 1024,
  );
  if (bytes == null) return const {'state': 'failed'};
  final AndroidReleaseManifest release;
  try {
    release = AndroidReleaseManifest.fromBytes(
      Uint8List.fromList(bytes),
      tenantId: tenantId,
    );
  } on FormatException {
    return const {'state': 'failed'};
  }
  return {
    'state': 'ready',
    'version': release.versionName,
    'summary': release.releaseNotes?.summary,
    'size': release.sizeBytes,
    'sha256': release.sha256,
    'file': release.apkObjectPath.split('/').last,
    if (parts)
      'parts': [
        for (final part in release.parts)
          {
            'url': await reads.customerSignedObject(
              token,
              _bucket,
              part.objectPath,
              expiresIn: 10 * 60,
            ),
            'size': part.sizeBytes,
            'sha256': part.sha256,
          },
      ],
  };
}
