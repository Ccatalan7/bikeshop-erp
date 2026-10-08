import 'dart:convert';

import 'package:vinabike_public_core/public_store/models/customer_auth_forms.dart';

/// The login's script: the two modes, the fields' messages, entering,
/// creating the account, Google and «¿Olvidaste tu contraseña?», as
/// `CustomerAuthPage` and `CustomerAccountService` do them.
///
/// Supabase Auth is called from the browser, as `supabase_flutter` calls it
/// (it counts attempts by address), and what it gives is kept where
/// `supabase_flutter` keeps it: the session in `sb-<ref>-auth-token`, a PKCE
/// verifier in `flutter.supabase.auth.token-code-verifier` (the JSON text
/// `shared_preferences` writes, `/passwordRecovery` after it for a
/// recovery), so whoever redeems the e-mail's link or Google's return finds
/// it: this page, or Flutter for a link that sets a password. The fields are checked by the server with the core's
/// rules before anything goes to Auth; the password itself never goes
/// there, only its shape (each letter, digit or sign replaced by one of its
/// kind), which is all the rules read.
String loginPageScript() => _script.replaceFirst(
  '/*WORDS*/{}',
  jsonEncode({
    'signInFailed': customerAuthSignInFailed,
    'signUpFailed': customerAuthSignUpFailed,
    'googleFailed': customerAuthGoogleFailed,
    'storeBusy': customerAuthStoreBusy,
    'sent': customerAuthVerificationSent('{email}'),
    'resent': customerAuthResent,
    'resendFailed': customerAuthResendFailed,
    'resetSent': customerResetSent,
    'resetLimited': customerResetRateLimited,
    'resetOffline': customerResetOffline,
    'notices': {
      'actualizada': customerAuthPasswordNotice('actualizada'),
      'creada': customerAuthPasswordNotice('creada'),
    },
    'noticeParameter': customerAuthPasswordNoticeParameter,
  }),
);

const _script = r'''
(function () {
  'use strict';
  if (window.vinabikeAuthHandoff) return;
  var root = document.querySelector('[data-login]');
  if (!root) return;
  var W = /*WORDS*/{};
  var body = document.body;
  var sbUrl = (body.dataset.sbUrl || '').replace(/\/+$/, ''), sbKey = body.dataset.sbKey || '';
  var actionUrl = root.dataset.actionUrl;
  var prefix = actionUrl.indexOf('/_html/') === 0 ? '/_html' : '';
  var origin = location.origin;
  var form = root.querySelector('[data-login-form]');
  var submit = form.querySelector('.lg-submit');
  var spin = submit.querySelector('.lg-spin');
  var google = root.querySelector('[data-google]');
  var resend = root.querySelector('[data-resend]');
  var verify = root.querySelector('[data-verify]');
  var dialog = root.querySelector('#lg-reset');
  var resetForm = dialog.querySelector('[data-reset-form]');
  var mode = 'login', busy = false, leaving = false, verifyEmail = null, toastEl = null, toastTimer = 0;
  var VERIFIER = 'flutter.supabase.auth.token-code-verifier';
  // `WebsiteEditorOAuthIntentGate.storageKey`: the editor's Google link.
  var EDITOR_INTENT = 'google_oauth_editor_intent';

  function field(name) { return form.querySelector('[name="' + name + '"]'); }
  function value(name) { var f = field(name); return f ? f.value : ''; }
  function visible(el) { return el && el.offsetParent !== null; }

  // ---- the bar (ScaffoldMessenger's SnackBar) ---------------------------
  function toast(message, bad) {
    if (!message) return;
    if (!toastEl) {
      toastEl = document.createElement('p');
      toastEl.setAttribute('role', 'status');
      root.appendChild(toastEl);
    }
    toastEl.className = 'lg-toast' + (bad ? ' bad' : '');
    toastEl.textContent = message;
    toastEl.hidden = false;
    toastEl.style.animation = 'none'; toastEl.offsetWidth; toastEl.style.animation = '';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.hidden = true; }, 4000);
  }

  // ---- the page's state ---------------------------------------------------
  // Flutter's `_isLoading`: the main button turns into its spinner (and,
  // disabled, takes the theme's disabled fill); Google and «Reenviar» wait.
  function setBusy(on) {
    busy = on;
    root.setAttribute('aria-busy', on ? 'true' : 'false');
    submit.setAttribute('aria-busy', on ? 'true' : 'false');
    submit.disabled = on;
    spin.hidden = !on;
    google.disabled = on;
    resend.disabled = on;
  }
  function showErrors(errors, scope) {
    Array.prototype.forEach.call((scope || form).querySelectorAll('[data-field]'), function (box) {
      var message = errors[box.dataset.field] || '';
      box.classList.toggle('bad', !!message);
      var msg = box.querySelector('.lg-msg');
      msg.textContent = message;
      var input = box.querySelector('input');
      if (message) input.setAttribute('aria-invalid', 'true'); else input.removeAttribute('aria-invalid');
    });
  }
  // `_formKey.currentState.reset()`: the values stay, the messages go.
  function setMode(next) {
    mode = next;
    root.dataset.mode = next;
    showErrors({});
    var password = field('password');
    var hints = JSON.parse(password.dataset.hints || '{}');
    password.placeholder = hints[next] || password.placeholder;
    password.autocomplete = next === 'login' ? 'current-password' : 'new-password';
  }

  // ---- the server and Supabase Auth ---------------------------------------
  function post(payload, token) {
    var headers = { 'content-type': 'application/json' };
    if (token) headers.authorization = 'Bearer ' + token;
    return fetch(actionUrl, { method: 'POST', headers: headers, body: JSON.stringify(payload) })
      .then(function (r) { return r.json(); });
  }
  // gotrue-dart's request: the publishable key as key and bearer.
  function auth(path, payload, token) {
    return fetch(sbUrl + path, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + (token || sbKey), 'content-type': 'application/json;charset=UTF-8' },
      body: JSON.stringify(payload || {})
    }).then(function (r) {
      return r.text().then(function (t) {
        var parsed = null;
        try { parsed = t ? JSON.parse(t) : null; } catch (e) { parsed = null; }
        return { ok: r.ok, status: r.status, body: parsed };
      });
    });
  }
  // What the rules read of a password, and nothing else: its length and
  // the kind of each character.
  function shape(password) {
    return password.replace(/[A-Z]/g, 'A').replace(/[a-z]/g, 'a').replace(/[0-9]/g, '1')
      .replace(/\s/g, ' ').replace(/[\x00-\x1F\x7F]/g, '\x01').replace(/[^Aa1 \x01]/g, '.');
  }
  // gotrue-dart's PKCE pair, the verifier where `supabase_flutter` reads it.
  function pkce(event) {
    var bytes = new Uint8Array(56); crypto.getRandomValues(bytes);
    var bin = ''; for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    var verifier = btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)).then(function (digest) {
      var d = new Uint8Array(digest), s = '';
      for (var k = 0; k < d.length; k++) s += String.fromCharCode(d[k]);
      localStorage.setItem(VERIFIER, JSON.stringify(event ? verifier + '/' + event : verifier));
      return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
    });
  }
  function jwtExp(token) {
    try { return JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp || 0; } catch (e) { return 0; }
  }
  function sessionKey() { return window.vinabikeSession ? window.vinabikeSession.key : ''; }

  // `signInWithPassword`, then the store's customer behind it
  // (`_loadCustomerData`): the session is kept as gotrue-dart's
  // `Session.toJson`; a session that cannot be a customer here is closed
  // again (`signOut(scope: local)`).
  function enter(r) {
    var session = {
      access_token: r.access_token, expires_in: r.expires_in, expires_at: r.expires_at || jwtExp(r.access_token),
      refresh_token: r.refresh_token, token_type: r.token_type || 'bearer',
      provider_token: r.provider_token || null, provider_refresh_token: r.provider_refresh_token || null, user: r.user
    };
    var key = sessionKey();
    localStorage.setItem(key, JSON.stringify(session));
    return post({ action: 'enter' }, session.access_token).catch(function () { return null; }).then(function (answer) {
      if (answer && answer.state === 'entered') {
        location.assign(prefix + '/cuenta');
        return new Promise(function () {});
      }
      // Forgotten here at once (only if it is still this attempt's), then
      // closed in Auth without waiting on it.
      try {
        var kept = JSON.parse(localStorage.getItem(key) || 'null');
        if (kept && kept.access_token === session.access_token) localStorage.removeItem(key);
      } catch (e) { /* nothing kept */ }
      var abort = window.AbortController ? new AbortController() : null;
      if (abort) setTimeout(function () { abort.abort(); }, 5000);
      fetch(sbUrl + '/auth/v1/logout?scope=local', {
        method: 'POST', headers: { apikey: sbKey, authorization: 'Bearer ' + session.access_token },
        signal: abort ? abort.signal : undefined, keepalive: true
      }).catch(function () { return null; });
      // The store could not answer: nothing about the account or the data.
      throw new Error(!answer || answer.state === 'unavailable' ? 'unavailable' : 'not a customer');
    });
  }
  function signIn(v) {
    return auth('/auth/v1/token?grant_type=password', {
      email: v.email.trim(), password: v.password,
      gotrue_meta_security: { captcha_token: null }
    }).then(function (r) {
      if (!r.ok || !r.body || !r.body.access_token || !r.body.user) throw new Error('refused');
      return enter(r.body);
    });
  }
  // `signUp` with the PKCE flow: an account that must confirm its e-mail
  // first leaves the notice, the bar and the login mode.
  function signUp(v) {
    var email = v.email.trim(), phone = v.phone.trim();
    return pkce().then(function (challenge) {
      return auth('/auth/v1/signup?redirect_to=' + encodeURIComponent(origin + '/cuenta/login?confirmed=true'), {
        email: email, password: v.password,
        data: { account_type: 'public_store_customer', name: v.name.trim(), phone: phone || null },
        gotrue_meta_security: { captcha_token: null }, code_challenge: challenge, code_challenge_method: 's256'
      });
    }).then(function (r) {
      if (!r.ok || !r.body) throw new Error('refused');
      var b = r.body, user = b.user || b;
      if (!b.access_token || !user.email_confirmed_at) {
        verifyEmail = email;
        var text = verify.querySelector('[data-verify-body]');
        text.textContent = text.dataset.template.replace('{email}', email);
        verify.hidden = false;
        field('password').value = '';
        setMode('login');
        setBusy(false);
        toast(W.sent.replace('{email}', email));
        return;
      }
      return enter(b);
    });
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    if (busy) return;
    // The mode and the values as they are now: the check and Auth get the
    // same ones, whatever changes while the check answers.
    var sent = mode, v = { name: value('name'), email: value('email'), phone: value('phone'), password: value('password') };
    var failed = sent === 'login' ? W.signInFailed : W.signUpFailed;
    setBusy(true);
    post({
      action: 'check', form: sent,
      values: { name: v.name, email: v.email, password: shape(v.password) }
    }).then(function (answer) {
      if (!answer || !answer.errors) throw new Error('check');
      showErrors(answer.errors);
      if (Object.keys(answer.errors).length) { setBusy(false); return; }
      return sent === 'login' ? signIn(v) : signUp(v);
    }).catch(function (error) {
      setBusy(false);
      toast(error && error.message === 'unavailable' ? W.storeBusy : failed, true);
    });
  });

  root.addEventListener('click', function (event) {
    var target = event.target.closest('button');
    if (!target || !root.contains(target)) return;
    if (target.hasAttribute('data-switch')) { if (!busy) setMode(mode === 'login' ? 'register' : 'login'); }
    else if (target.hasAttribute('data-reveal')) {
      var password = field('password'), shown = password.type === 'password';
      password.type = shown ? 'text' : 'password';
      target.setAttribute('aria-pressed', shown ? 'true' : 'false');
      target.setAttribute('aria-label', shown ? 'Ocultar contraseña' : 'Mostrar contraseña');
    } else if (target.hasAttribute('data-google')) {
      if (busy || leaving) return;
      leaving = true;
      // `signInWithOAuth`: Google returns to /auth/callback, where this
      // page redeems the code with this verifier.
      pkce().then(function (challenge) {
        var q = new URLSearchParams({
          provider: 'google', redirect_to: origin + '/auth/callback', flow_type: 'pkce',
          code_challenge: challenge, code_challenge_method: 's256'
        });
        location.assign(sbUrl + '/auth/v1/authorize?' + q.toString());
      }).catch(function () { leaving = false; toast(W.googleFailed, true); });
    } else if (target.hasAttribute('data-resend')) {
      if (busy || !verifyEmail) return;
      setBusy(true);
      auth('/auth/v1/resend?redirect_to=' + encodeURIComponent(origin + '/cuenta/login?confirmed=true'), {
        email: verifyEmail, type: 'signup', gotrue_meta_security: { captcha_token: null }
      }).then(function (r) {
        setBusy(false);
        toast(r.ok ? W.resent : W.resendFailed, !r.ok);
      }, function () { setBusy(false); toast(W.resendFailed, true); });
    } else if (target.hasAttribute('data-forgot')) openReset();
  });

  // ---- «¿Olvidaste tu contraseña?» -----------------------------------------
  var resetBusy = false;
  function openReset() {
    var input = resetForm.querySelector('input');
    input.value = value('email').trim();
    showErrors({}, resetForm);
    dialog.showModal();
    dialog.focus();
  }
  function closeReset() { if (dialog.open) dialog.close(); }
  dialog.addEventListener('click', function (event) {
    if (event.target.closest('[data-close]')) closeReset();
  });
  dialog.addEventListener('cancel', function (event) { if (resetBusy) event.preventDefault(); });
  resetForm.addEventListener('submit', function (event) {
    event.preventDefault();
    if (resetBusy) return;
    var email = resetForm.querySelector('input').value.trim();
    resetBusy = true;
    post({ action: 'check', form: 'reset', values: { email: email } }).then(function (answer) {
      if (!answer || !answer.errors) throw new Error('offline');
      showErrors(answer.errors, resetForm);
      if (Object.keys(answer.errors).length) return;
      // `resetPasswordForEmail`: the verifier marked for a recovery.
      return pkce('passwordRecovery').then(function (challenge) {
        return auth('/auth/v1/recover?redirect_to=' + encodeURIComponent(origin + '/cuenta/login?recovery=true'), {
          email: email, gotrue_meta_security: { captcha_token: null },
          code_challenge: challenge, code_challenge_method: 's256'
        });
      }).then(function (r) {
        var b = r.body || {};
        // `customerResetIsRateLimited`: Auth's code or message names it.
        if (!r.ok && /rate.?limit/i.test(String(b.error_code || b.code || '') + ' ' + String(b.msg || b.message || b.error_description || ''))) {
          toast(W.resetLimited, true);
          return;
        }
        // Said whether or not the address has an account.
        closeReset();
        toast(W.resetSent);
      });
    }).catch(function () {
      toast(W.resetOffline, true);
    }).then(function () { resetBusy = false; });
  });

  window.addEventListener('pageshow', function () { leaving = false; });

  // ---- what the address says ----------------------------------------------
  var params = new URLSearchParams(location.search);
  var callback = location.pathname === prefix + '/auth/callback';
  var code = params.get('code');
  if (callback || code) {
    // `exchangeCodeForSession` with this browser's verifier: Google's return
    // and an account's confirmation. What only this browser can tell goes
    // back to the server with `enlace`, which answers Flutter: the editor's
    // own Google link (its intent waits here) and a recovery (its verifier
    // is marked), which ends in setting a password.
    var verifier = null;
    try { verifier = JSON.parse(localStorage.getItem(VERIFIER) || 'null'); } catch (e) { verifier = null; }
    if (typeof verifier !== 'string' || !verifier) verifier = null;
    if ((callback && localStorage.getItem(EDITOR_INTENT) !== null) ||
        (code && ((verifier && /\/passwordRecovery$/.test(verifier)) || params.get('recovery') === 'true'))) {
      params.set('enlace', '1');
      location.replace(location.pathname + '?' + params.toString());
      return;
    }
    // A code is good once: once Auth answers, the address and this storage
    // forget it (gotrue-dart drops the verifier then too); a request that
    // never reached Auth keeps both, so reloading the page tries again.
    var confirmed = !callback && params.get('confirmed') === 'true';
    var forget = function () {
      history.replaceState(history.state, '', prefix + '/cuenta/login' + (confirmed ? '?confirmed=true' : ''));
    };
    if (!code || !verifier) {
      // Google said no, or the link was opened in another browser: an
      // account's link confirmed it all the same (the notice below says so).
      forget();
      if (callback) toast(W.googleFailed, true);
    } else {
      setBusy(true);
      var answered = false;
      auth('/auth/v1/token?grant_type=pkce', { auth_code: code, code_verifier: verifier }).then(function (r) {
        answered = true;
        localStorage.removeItem(VERIFIER);
        forget();
        if (!r.ok || !r.body || !r.body.access_token || !r.body.user) throw new Error('refused');
        return enter(r.body);
      }).catch(function (error) {
        setBusy(false);
        if (!answered || (error && error.message === 'unavailable')) toast(W.storeBusy, true);
        else if (callback) toast(W.googleFailed, true);
        else if (!confirmed) toast(W.signInFailed, true);
      });
    }
    params = new URLSearchParams(location.search);
  }
  if (params.get('confirmed') === 'true') root.querySelector('[data-confirmed]').hidden = false;
  var notice = W.notices[params.get(W.noticeParameter) || ''];
  if (notice) {
    toast(notice);
    params.delete(W.noticeParameter);
    var rest = params.toString();
    history.replaceState(history.state, '', location.pathname + (rest ? '?' + rest : '') + location.hash);
  }
})();
''';
