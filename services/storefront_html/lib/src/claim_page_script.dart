/// The QR page's script (`/cuenta/vincular`): reads what the code says, greets
/// the customer and links the account — at once with a session, after
/// Google's return, or when the e-mail of a new account is confirmed.
///
/// - The code came in the fragment and the page's first script moved it to
///   this tab (`vb-claim`); it is never in the address again.
/// - Google: the phone and the code wait in this tab, the login page at
///   `/auth/callback` redeems the return as always (`vb-after-login` brings
///   it back here) and this page links without another tap.
/// - E-mail: the account is created with the code and the phone in its
///   metadata (`vinabike_claim_code`, `vinabike_claim_phone`): the store links
///   it when it enters, in whichever browser the confirmation opens.
/// - The PKCE pair is the login's (`flutter.supabase.auth.token-code-verifier`),
///   so the login page that redeems the return finds it.
const claimPageScript = r'''
(function () {
  'use strict';
  var root = document.querySelector('[data-claim]');
  if (!root) return;
  var W = {};
  try { W = JSON.parse(root.dataset.words || '{}'); } catch (e) { W = {}; }
  var body = document.body;
  var sbUrl = (body.dataset.sbUrl || '').replace(/\/+$/, ''), sbKey = body.dataset.sbKey || '';
  var actionUrl = root.dataset.actionUrl;
  var prefix = actionUrl.indexOf('/_html/') === 0 ? '/_html' : '';
  var origin = location.origin;
  var session = window.vinabikeSession;
  var VERIFIER = 'flutter.supabase.auth.token-code-verifier';
  var STORE = 'vb-claim';
  var form = root.querySelector('[data-claim-form]');
  var busy = false, peeked = null;

  function q(selector) { return root.querySelector(selector); }
  function stored() {
    try { return JSON.parse(sessionStorage.getItem(STORE) || '{}') || {}; } catch (e) { return {}; }
  }
  function keep(next) {
    try { sessionStorage.setItem(STORE, JSON.stringify(next)); } catch (e) { /* this visit only */ }
  }
  function forget() {
    try { sessionStorage.removeItem(STORE); } catch (e) { /* nothing kept */ }
  }
  var code = window.vinabikeClaimCode || stored().code || '';

  function panel(name) {
    Array.prototype.forEach.call(root.querySelectorAll('[data-panel]'), function (el) {
      el.hidden = el.dataset.panel !== name;
    });
    root.dataset.state = name;
  }
  function wait(text) {
    q('[data-wait-text]').textContent = text;
    panel('wait');
  }
  function problem(status) {
    var problems = W.problems || {};
    q('[data-problem-text]').textContent = problems[status] || problems.invalid || '';
    panel('problem');
  }
  function fieldError(name, message) {
    var box = form.querySelector('[data-field="' + name + '"]');
    if (!box) return;
    box.classList.toggle('bad', !!message);
    box.querySelector('.lg-msg').textContent = message || '';
    var input = box.querySelector('input');
    if (message) input.setAttribute('aria-invalid', 'true'); else input.removeAttribute('aria-invalid');
  }
  function value(name) { var f = form.querySelector('[name="' + name + '"]'); return f ? f.value.trim() : ''; }
  function setBusy(on, button) {
    busy = on;
    root.setAttribute('aria-busy', on ? 'true' : 'false');
    Array.prototype.forEach.call(form.querySelectorAll('button'), function (b) { b.disabled = on; });
    if (button) {
      var spin = button.querySelector('.lg-spin');
      if (spin) spin.hidden = !on;
    }
  }
  function phoneOk(phone) { return phone.replace(/[^0-9]/g, '').length >= 8; }
  function checkPhone() {
    var phone = value('phone');
    if (!phoneOk(phone)) { fieldError('phone', W.phoneMissing || ''); return null; }
    fieldError('phone', '');
    return phone;
  }

  function post(payload, token) {
    var headers = { 'content-type': 'application/json' };
    if (token) headers.authorization = 'Bearer ' + token;
    return fetch(actionUrl, {
      method: 'POST', headers: headers, body: JSON.stringify(payload),
      credentials: 'omit', cache: 'no-store'
    }).then(function (r) { return r.json(); });
  }
  function auth(path, payload) {
    return fetch(sbUrl + path, {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json' },
      body: JSON.stringify(payload || {})
    }).then(function (r) {
      return r.text().then(function (t) {
        var parsed = null;
        try { parsed = t ? JSON.parse(t) : null; } catch (e) { parsed = null; }
        return { ok: r.ok, status: r.status, body: parsed };
      });
    });
  }
  // The login's: its length and the kind of each character, nothing else.
  function shape(password) {
    return password.replace(/[A-Z]/g, 'A').replace(/[a-z]/g, 'a').replace(/[0-9]/g, '1')
      .replace(/\s/g, ' ').replace(/[\x00-\x1F\x7F]/g, '\x01').replace(/[^Aa1 \x01]/g, '.');
  }
  // gotrue-dart's PKCE pair, the verifier where the login page reads it.
  function pkce() {
    var bytes = new Uint8Array(56); crypto.getRandomValues(bytes);
    var bin = ''; for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    var verifier = btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)).then(function (digest) {
      var d = new Uint8Array(digest), s = '';
      for (var k = 0; k < d.length; k++) s += String.fromCharCode(d[k]);
      localStorage.setItem(VERIFIER, JSON.stringify(verifier));
      return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').split('=')[0];
    });
  }
  function comeBackHere() {
    try { sessionStorage.setItem('vb-after-login', prefix + '/cuenta/vincular'); } catch (e) { /* the account, then */ }
  }

  // ---- linking with the session ---------------------------------------------
  function claim(phone) {
    wait(W.linking || '');
    var tries = 0;
    function attempt(force) {
      return (force ? session.renew() : session.current()).then(function (s) {
        if (!s) return { state: 'signed-out' };
        return post({ action: 'claim', values: { code: code, phone: phone || '' } }, s.access_token);
      }).then(function (answer) {
        if (answer && answer.state === 'expired' && tries++ < 1) return attempt(true);
        return answer;
      });
    }
    return attempt(false).then(function (answer) {
      var status = answer && answer.claim ? answer.claim.status : (answer && answer.state) || 'unavailable';
      if (status === 'linked' || status === 'already_yours') {
        forget();
        panel('done');
        setTimeout(function () { location.assign(prefix + '/cuenta'); }, 1200);
        return;
      }
      if (status === 'signed-out') { showForm(false); return; }
      if ((W.retryable || []).indexOf(status) >= 0) {
        showForm(true);
        fieldError('phone', (W.problems || {})[status] || '');
        return;
      }
      forget();
      problem(status);
    }).catch(function () {
      showForm(!!(session && session.read()));
      fieldError('phone', (W.problems || {}).unavailable || '');
    });
  }

  // ---- the form -------------------------------------------------------------
  function showForm(withSession) {
    var s = withSession && session ? session.read() : null;
    var email = s && s.user && s.user.email;
    var line = q('[data-session-line]');
    line.hidden = !email;
    line.textContent = email ? (W.session || '').replace('{email}', email) : '';
    q('[data-link]').hidden = !s;
    q('[data-google]').hidden = !!s;
    q('[data-or]').hidden = !!s;
    q('[data-email-toggle]').hidden = !!s;
    q('[data-have-account]').hidden = !!s;
    var phone = form.querySelector('[name="phone"]');
    if (!phone.value && stored().phone) phone.value = stored().phone;
    setBusy(false);
    panel('form');
  }

  q('[data-google]').addEventListener('click', function () {
    if (busy) return;
    var phone = checkPhone();
    if (!phone) return;
    keep({ code: code, phone: phone, auto: true });
    comeBackHere();
    setBusy(true);
    pkce().then(function (challenge) {
      var params = new URLSearchParams({
        provider: 'google', redirect_to: origin + '/auth/callback', flow_type: 'pkce',
        code_challenge: challenge, code_challenge_method: 's256'
      });
      location.assign(sbUrl + '/auth/v1/authorize?' + params.toString());
    }).catch(function () { setBusy(false); fieldError('phone', (W.problems || {}).unavailable || ''); });
  });

  q('[data-email-toggle]').addEventListener('click', function () {
    var fields = q('[data-email-fields]'), toggle = q('[data-email-toggle]');
    fields.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    toggle.hidden = true;
    var email = form.querySelector('[name="email"]');
    if (email) email.focus();
  });

  q('[data-sign-in]').addEventListener('click', function () {
    var phone = value('phone');
    keep({ code: code, phone: phoneOk(phone) ? phone : '', auto: phoneOk(phone) });
    comeBackHere();
  });

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    if (busy) return;
    var phone = checkPhone();
    if (!phone) return;
    if (session && session.read()) { claim(phone); return; }
    createWithEmail(phone);
  });

  // `signUp` with the code in the account: the confirmation links it.
  function createWithEmail(phone) {
    var email = value('email'), password = form.querySelector('[name="password"]').value;
    var name = (peeked && peeked.first_name) || 'Cliente';
    var button = q('[data-create]');
    setBusy(true, button);
    post({
      action: 'check', form: 'register',
      values: { name: name, email: email, password: shape(password) }
    }).then(function (answer) {
      if (!answer || !answer.errors) throw new Error('check');
      fieldError('email', answer.errors.email || '');
      fieldError('password', answer.errors.password || '');
      if (answer.errors.email || answer.errors.password) { setBusy(false, button); return null; }
      return pkce().then(function (challenge) {
        return auth('/auth/v1/signup?redirect_to=' + encodeURIComponent(origin + '/cuenta/login?confirmed=true'), {
          email: email, password: password,
          data: {
            account_type: 'public_store_customer', name: name, phone: phone,
            vinabike_claim_code: code, vinabike_claim_phone: phone
          },
          gotrue_meta_security: { captcha_token: null },
          code_challenge: challenge, code_challenge_method: 's256'
        });
      });
    }).then(function (r) {
      if (r === null) return;
      if (!r || !r.ok || !r.body) throw new Error('refused');
      // After confirming, in this browser, the account: it is linked there.
      try { sessionStorage.setItem('vb-after-login', prefix + '/cuenta'); } catch (e) { /* the account anyway */ }
      forget();
      q('[data-verify-text]').textContent = (W.verifyBody || '').replace('{email}', email);
      setBusy(false, button);
      panel('verify');
    }).catch(function () {
      setBusy(false, button);
      fieldError('email', (W.problems || {}).unavailable || '');
    });
  }

  // ---- what the code says -----------------------------------------------------
  if (!code) { problem('invalid'); return; }
  wait(W.checking || '');
  post({ action: 'claim-peek', values: { code: code } }).then(function (answer) {
    var peek = answer && answer.peek;
    if (!peek) { problem('unavailable'); return; }
    if (peek.status !== 'valid') { forget(); problem(peek.status || 'invalid'); return; }
    peeked = peek;
    var greeting = q('[data-greeting]');
    greeting.textContent = peek.first_name
      ? (W.greetingNamed || '').replace('{name}', peek.first_name)
      : (W.greeting || greeting.textContent);
    var subject = [];
    if (peek.bike) subject.push(peek.bike);
    if (peek.job_number) subject.push('Servicio ' + peek.job_number);
    q('[data-subject]').textContent = subject.join(' · ');
    var s = session ? session.read() : null;
    var kept = stored();
    keep({ code: code, phone: kept.phone || '', auto: kept.auto || false });
    // Back from Google or from signing in: link without another tap.
    if (s && kept.auto && phoneOk(kept.phone || '')) { claim(kept.phone); return; }
    showForm(!!s);
  }).catch(function () { problem('unavailable'); });
})();
''';
