/// The customer portal's behavior on the HTML pages, after the page script
/// (`window.vinabikeSession`).
///
/// - **Content.** With a session, it asks `data-view-url` for this page with
///   the token in the `authorization` header; the server reads Supabase as
///   the customer and answers the page drawn. A refused token is renewed
///   once (`vinabikeSession.renew`); without a session the way in stays.
/// - **Views.** «Pedidos» and «Taller» come with every tab or bike drawn;
///   a chip shows its view, as Flutter keeps it in the page's state.
/// - **Sheets.** A row opens its `<dialog>` (`showPortalDetail`): a dialog
///   that fades in wide, a sheet that slides up under 600 px.
/// - **Files.** A job's file asks `data-file-url` for a fresh link and opens
///   it in a new tab.
/// - **Saving (4b).** The profile and address forms go to `data-action-url`
///   with the session; the server checks them with the portal's rules,
///   writes as the customer and answers the page drawn again, a field's
///   message or what to say. Here only an empty required field is caught
///   before sending (its message comes in `data-required`), as Flutter's
///   form does on «Guardar». The password dialog moves between its steps
///   with what the server answers.
const portalPageScript = r'''
(function () {
  var root = document.querySelector('[data-portal-root]');
  if (!root) return;
  var session = window.vinabikeSession;
  var viewUrl = root.dataset.viewUrl, fileUrl = root.dataset.fileUrl, actionUrl = root.dataset.actionUrl;
  var path = location.pathname.replace(/^\/_html(?=\/)/, '');
  var html = document.documentElement;

  function boundary(state) {
    var shown = false;
    Array.prototype.forEach.call(root.children, function (child) {
      if (!child.matches || !child.matches('.pt')) return;
      var on = child.dataset.portal === state;
      child.hidden = !on;
      shown = shown || on;
    });
    return shown;
  }

  // A password changed but the other sessions still open, in this tab
  // (`hasPendingOtherSessionsRevocation`, by user).
  var PENDING = 'vinabike.portal.revocation-pending';
  function userId() { var s = session && session.read(); return s && s.user && s.user.id; }
  function pending() { try { var id = userId(); return !!id && sessionStorage.getItem(PENDING) === id; } catch (e) { return false; } }
  function setPending(on) {
    try { var id = userId(); if (on && id) sessionStorage.setItem(PENDING, id); else sessionStorage.removeItem(PENDING); } catch (e) {}
  }

  // A POST with the session; a refused one is renewed once and sent again.
  function post(url, payload) {
    return session.current().then(function (s) {
      if (!s) return { state: 'signed-out' };
      function send(token) {
        return fetch(url, {
          method: 'POST',
          headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' },
          body: JSON.stringify(payload),
          credentials: 'omit',
          cache: 'no-store'
        }).then(function (r) { return r.json(); });
      }
      return send(s.access_token).then(function (answer) {
        if (!answer || answer.state !== 'expired') return answer;
        return session.renew().then(function (fresh) {
          return fresh ? send(fresh.access_token) : { state: 'signed-out' };
        });
      });
    });
  }
  function query() { return location.search.replace(/^\?/, ''); }

  function reveal() {
    var tab = root.querySelector('.pt-tab.on'), strip = tab && tab.parentNode;
    if (!strip || strip.scrollWidth <= strip.clientWidth) return;
    strip.scrollLeft = tab.offsetLeft - (strip.clientWidth - tab.offsetWidth) / 2;
  }
  function swap(markup) { root.innerHTML = markup; reveal(); }
  // An answer that is not the page: the way in, or «No pudimos abrir».
  function lost(answer) {
    if (!answer) return false;
    if (answer.state === 'expired' || answer.state === 'signed-out') { boundary('signedOut'); return true; }
    if (answer.state === 'not-customer') { boundary('notCustomer'); return true; }
    return false;
  }

  function load() {
    if (!session || !session.read()) { boundary('signedOut'); return; }
    boundary('loading');
    post(viewUrl, { path: path, query: query(), pending: pending() }).then(function (answer) {
      if (answer && typeof answer.html === 'string') { swap(answer.html); return; }
      if (!lost(answer)) boundary('notCustomer');
    }, function () { boundary('notCustomer'); });
  }

  // ---- the SnackBar -------------------------------------------------------
  var toastEl = null, toastTimer = null;
  function toast(message) {
    if (!message) return;
    if (!toastEl) {
      toastEl = document.createElement('p');
      toastEl.className = 'pt pt-toast';
      toastEl.setAttribute('role', 'status');
      root.parentNode.appendChild(toastEl);
    }
    toastEl.textContent = message;
    toastEl.hidden = false;
    toastEl.style.animation = 'none'; toastEl.offsetWidth; toastEl.style.animation = '';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.hidden = true; }, 4000);
  }

  // ---- views ------------------------------------------------------------
  function showView(button) {
    var views = button.closest('.pt-views');
    if (!views) return;
    var name = button.dataset.viewTo, target = null;
    Array.prototype.forEach.call(views.children, function (view) {
      if (view.dataset.view === name) target = view;
    });
    if (!target) target = views.querySelector('[data-view="all"]');
    Array.prototype.forEach.call(views.children, function (view) { view.hidden = view !== target; });
  }

  // ---- sheets and dialogs -------------------------------------------------
  function openSheet(id, opener) {
    var dialog = document.getElementById(id);
    if (!dialog || dialog.open) return;
    dialog.opener = opener;
    dialog.showModal();
    // Flutter's dialog opens with no field focused (the label stays inside).
    if (dialog.classList.contains('alert')) dialog.focus({ preventScroll: true });
    html.classList.add('pt-dlg-lock');
    dialog.offsetWidth;
    dialog.classList.add('in');
  }
  function closeSheet(dialog, then) {
    if (!dialog || !dialog.open || dialog.closing) return;
    dialog.closing = true;
    dialog.classList.remove('in');
    var panel = dialog.querySelector('.pt-panel,.pt-alert'), done = false;
    function finish() {
      if (done) return;
      done = true;
      dialog.closing = false;
      dialog.close();
      if (!document.querySelector('.pt-dlg[open]')) html.classList.remove('pt-dlg-lock');
      if (dialog.opener && dialog.opener.focus && document.contains(dialog.opener)) dialog.opener.focus();
      if (then) then();
      if (dialog.reloadOnClose) { dialog.reloadOnClose = false; load(); }
    }
    panel.addEventListener('transitionend', finish, { once: true });
    setTimeout(finish, 320);
  }
  document.addEventListener('cancel', function (event) {
    if (event.target.matches && event.target.matches('.pt-dlg')) {
      event.preventDefault();
      if (!event.target.busy) closeSheet(event.target);
    }
  }, true);

  // ---- files ------------------------------------------------------------
  function openFile(button) {
    var sheet = button.closest('.pt-files'), error = sheet && sheet.querySelector('.pt-files-error');
    if (error) error.hidden = true;
    var tab = window.open('', '_blank');
    session.current().then(function (s) {
      if (!s) throw new Error('session');
      return fetch(fileUrl, {
        method: 'POST',
        headers: { authorization: 'Bearer ' + s.access_token, 'content-type': 'application/json' },
        body: JSON.stringify({ reference: button.dataset.file }),
        credentials: 'omit',
        cache: 'no-store'
      }).then(function (r) { return r.json(); });
    }).then(function (answer) {
      if (!answer || !answer.url) throw new Error('file');
      if (tab) { tab.opener = null; tab.location.href = answer.url; } else location.assign(answer.url);
    }).catch(function () {
      if (tab) tab.close();
      if (error) error.hidden = false;
    });
  }

  // ---- forms --------------------------------------------------------------
  function field(form, name) { return form.querySelector('[name="' + name + '"]'); }
  function setError(box, message) {
    if (!box) return;
    var msg = box.querySelector('.pt-f-msg');
    box.classList.toggle('bad', !!message);
    if (msg) msg.textContent = message || msg.dataset.helper || '';
  }
  function clearErrors(scope) {
    Array.prototype.forEach.call(scope.querySelectorAll('.pt-f.bad'), function (box) { setError(box, null); });
  }
  function showErrors(form, errors) {
    var first = null;
    Object.keys(errors || {}).forEach(function (name) {
      var el = field(form, name);
      if (!el) return;
      setError(el.closest('.pt-f'), errors[name]);
      first = first || el;
    });
    return first;
  }
  function shown(el) { return el.getClientRects().length > 0; }
  // Flutter's `validate()` on the fields the step shows: an empty required
  // one says its message (`data-required`).
  function emptyRequired(form) {
    var errors = {}, any = false;
    Array.prototype.forEach.call(form.querySelectorAll('[data-required]'), function (el) {
      if (!shown(el)) return;
      var box = el.closest('.pt-f');
      if (el.value.trim() === '') { errors[el.name] = el.dataset.required; any = true; } else setError(box, null);
    });
    if (any) showErrors(form, errors);
    return any;
  }
  function valuesOf(form) {
    var out = {};
    Array.prototype.forEach.call(form.querySelectorAll('input[name],textarea[name]'), function (el) {
      out[el.name] = el.type === 'checkbox' ? el.checked : el.value;
    });
    return out;
  }
  // `PortalButton(busy: …)`: the spinner, the busy label; the others wait.
  function busy(form, on) {
    var dialog = form.closest('.pt-dlg');
    if (dialog) dialog.busy = on;
    if (on) form.dataset.busy = '1'; else delete form.dataset.busy;
    Array.prototype.forEach.call(form.querySelectorAll('button'), function (b) {
      if (on) { b.dataset.was = b.disabled ? '1' : ''; b.disabled = true; }
      else if (!b.dataset.was) b.disabled = false;
    });
    Array.prototype.forEach.call(form.querySelectorAll('[type=submit]'), function (b) {
      if (!shown(b) && on) return;
      var spin = b.querySelector('.pt-btn-spin'), label = b.querySelector('.pt-btn-label .pt-x') || b.querySelector('.pt-btn-label');
      if (spin) spin.hidden = !on;
      if (b.dataset.busyLabel && label) {
        if (on) { b.dataset.idle = label.textContent; label.textContent = b.dataset.busyLabel; }
        else if (b.dataset.idle) label.textContent = b.dataset.idle;
      }
    });
  }
  function act(action, values) {
    return post(actionUrl, { path: path, query: query(), action: action, values: values || {}, pending: pending() });
  }

  // ---- «Perfil y seguridad» -------------------------------------------------
  function editProfile(on) {
    var box = root.querySelector('[data-profile]');
    if (!box) return;
    var form = box.querySelector('[data-form=profile]'), facts = box.querySelector('[data-profile-facts]');
    var link = box.querySelector('.pt-sh .pt-link');
    if (!on) { form.reset(); clearErrors(form); }
    form.hidden = !on;
    facts.hidden = on;
    if (link) link.hidden = on;
  }
  function saveProfile(form) {
    if (emptyRequired(form)) return;
    busy(form, true);
    act('profile', valuesOf(form)).then(function (answer) {
      busy(form, false);
      if (lost(answer)) return;
      if (answer && answer.errors) { showErrors(form, answer.errors); return; }
      if (answer && typeof answer.html === 'string') swap(answer.html);
      toast(answer && answer.toast);
    }, function () {
      busy(form, false);
      toast(form.dataset.failed || 'No pudimos guardar tus datos. Inténtalo nuevamente.');
    });
  }

  function passwordStep(dialog, step) {
    dialog.dataset.step = step;
    if (step === 'verification') {
      var code = field(dialog, 'code');
      if (code) setTimeout(function () { code.focus(); }, 30);
    }
  }
  function say(dialog, kind, message) {
    var el = dialog.querySelector(kind === 'notice' ? '[data-notice]' : '[data-error="' + kind + '"]');
    if (!el) return;
    el.textContent = message || '';
    el.hidden = !message;
  }
  function quiet(dialog) {
    ['password', 'verification', 'revocation', 'notice'].forEach(function (kind) { say(dialog, kind, null); });
  }
  function openPassword(button) {
    var dialog = document.getElementById(button.dataset.password);
    if (!dialog) return;
    var form = dialog.querySelector('form');
    form.reset();
    clearErrors(form);
    quiet(dialog);
    passwordStep(dialog, button.dataset.stepTo || (pending() ? 'revocation' : 'password'));
    openSheet(dialog.id, button);
  }
  function passwordAnswer(dialog, form, answer, errorKind) {
    if (lost(answer)) { closeSheet(dialog); return; }
    answer = answer || {};
    if (answer.errors) { showErrors(form, answer.errors); return; }
    if (answer.done) {
      var wasPending = pending();
      setPending(false);
      if (wasPending) dialog.reloadOnClose = true;
      closeSheet(dialog);
      toast(answer.toast);
      return;
    }
    if (answer.step === 'revocation') {
      setPending(true);
      dialog.reloadOnClose = true;
      ['password', 'confirm', 'code'].forEach(function (name) { var el = field(form, name); if (el) el.value = ''; });
      quiet(dialog);
      passwordStep(dialog, 'revocation');
      return;
    }
    if (answer.step === 'verification') {
      if (dialog.dataset.step !== 'verification') { var code = field(form, 'code'); if (code) code.value = ''; }
      quiet(dialog);
      passwordStep(dialog, 'verification');
      if (answer.notice) { var c = field(form, 'code'); if (c) c.value = ''; }
      say(dialog, 'notice', answer.notice);
      say(dialog, 'verification', answer.error);
      return;
    }
    if (answer.notice) say(dialog, 'notice', answer.notice);
    if (answer.error) say(dialog, errorKind, answer.error);
  }
  // An attempt whose answer was lost may have changed the password: the
  // next one says so, and Auth's «same password» then means it did.
  var passwordUncertain = false;
  function submitPassword(form) {
    var dialog = form.closest('.pt-dlg'), step = dialog.dataset.step;
    if (step !== 'revocation' && emptyRequired(form)) return;
    var values = valuesOf(form), action = 'password', payload;
    if (step === 'password') { payload = { password: values.password, confirm: values.confirm }; say(dialog, 'password', null); }
    else if (step === 'verification') { payload = { password: values.password, code: values.code }; say(dialog, 'verification', null); }
    else { action = 'revoke-others'; payload = {}; say(dialog, 'revocation', null); }
    if (action === 'password' && passwordUncertain) payload.uncertain = true;
    busy(form, true);
    act(action, payload).then(function (answer) {
      busy(form, false);
      if (answer && answer.uncertain) passwordUncertain = true;
      if (answer && (answer.done || answer.step === 'revocation')) passwordUncertain = false;
      passwordAnswer(dialog, form, answer, step);
    }, function () {
      if (action === 'password') passwordUncertain = true;
      busy(form, false);
      say(dialog, step, step === 'password'
        ? 'No pudimos actualizar la contraseña. Inténtalo nuevamente.'
        : step === 'verification'
          ? 'No pudimos verificar el código. Inténtalo nuevamente.'
          : 'La contraseña sigue actualizada, pero no pudimos cerrar las demás sesiones. Reintenta desde Seguridad.');
    });
  }
  function resendCode(button) {
    var dialog = button.closest('.pt-dlg'), form = dialog.querySelector('form');
    quiet(dialog);
    busy(form, true);
    act('password-resend', {}).then(function (answer) {
      busy(form, false);
      passwordAnswer(dialog, form, answer, 'verification');
    }, function () {
      busy(form, false);
      say(dialog, 'verification', 'No pudimos enviar el código. Revisa tu conexión e inténtalo nuevamente.');
    });
  }

  // ---- «Direcciones» --------------------------------------------------------
  var places = window.vinabikePlaces, placesToken = places ? places.token() : null;
  // Bumped on every open and every pick: a late answer of Places is dropped
  // instead of filling the address now open.
  var placeSeq = 0;
  function addressDialog() { return document.querySelector('[data-address-dialog]'); }
  function applyMine(form) {
    var mine = field(form, 'profile_contact'), data = form.closest('.pt-dlg').dataset;
    var on = !!(mine && mine.checked);
    ['recipient_name', 'phone'].forEach(function (name) {
      var el = field(form, name);
      el.disabled = on;
      el.closest('.pt-f').classList.toggle('off', on);
    });
    if (on) {
      if (data.profileName) field(form, 'recipient_name').value = data.profileName;
      if (data.profilePhone) field(form, 'phone').value = data.profilePhone;
    }
  }
  function openAddress(row, opener) {
    var dialog = addressDialog();
    if (!dialog) return;
    var form = dialog.querySelector('form');
    form.reset();
    clearErrors(form);
    placeSeq++;
    sugSeq++;
    closeSugs(form);
    var spin = form.querySelector('.pt-f-busy');
    if (spin) spin.hidden = true;
    var values = row ? JSON.parse(row.dataset.addressRow) : {};
    dialog.dataset.step = row ? 'edit' : 'new';
    ['id', 'label', 'recipient_name', 'phone', 'street_address', 'street_number', 'apartment', 'comuna', 'city', 'region', 'postal_code', 'additional_info'].forEach(function (name) {
      var el = field(form, name);
      if (el) el.value = values[name] == null ? '' : String(values[name]);
    });
    field(form, 'is_default').checked = !!values.is_default;
    var mine = field(form, 'profile_contact');
    if (mine) mine.checked = !mine.disabled && !!values.profile_contact;
    applyMine(form);
    var search = form.querySelector('[data-places]');
    if (search && places) places.status().then(function (on) { search.hidden = !on; });
    openSheet(dialog.id, opener);
  }
  function saveAddress(form) {
    if (emptyRequired(form)) return;
    var dialog = form.closest('.pt-dlg');
    busy(form, true);
    act('address-save', valuesOf(form)).then(function (answer) {
      busy(form, false);
      if (lost(answer)) { closeSheet(dialog); return; }
      if (answer && answer.errors) { showErrors(form, answer.errors); return; }
      if (answer && typeof answer.html === 'string') {
        closeSheet(dialog, function () { swap(answer.html); toast(answer.toast); });
        return;
      }
      toast(answer && answer.toast);
    }, function () {
      busy(form, false);
      toast('No pudimos guardar la dirección. Intenta de nuevo.');
    });
  }
  function rowChange(action, row, dialog, failed) {
    var id = JSON.parse(row.dataset.addressRow).id;
    return act(action, { id: id }).then(function (answer) {
      if (lost(answer)) { if (dialog) closeSheet(dialog); return; }
      var markup = answer && typeof answer.html === 'string' ? answer.html : null;
      var after = function () { if (markup) swap(markup); toast(answer && answer.toast); };
      if (dialog) closeSheet(dialog, after); else after();
    }, function () {
      if (dialog) closeSheet(dialog, function () { toast(failed); }); else toast(failed);
    });
  }
  function openDelete(row) {
    var dialog = document.querySelector('[data-delete-dialog]');
    if (!dialog) return;
    dialog.row = row;
    dialog.querySelector('[data-delete-title]').textContent = row.dataset.deleteTitle;
    dialog.querySelector('[data-delete-full]').textContent = row.dataset.full;
    busy(dialog.querySelector('form'), false);
    openSheet(dialog.id, row.querySelector('[data-address-more]'));
  }
  function deleteAddress(form) {
    var dialog = form.closest('.pt-dlg');
    busy(form, true);
    rowChange('address-delete', dialog.row, dialog, 'No pudimos eliminar la dirección. Intenta de nuevo.').then(function () { busy(form, false); });
  }

  // The row's menu (`PopupMenuButton`): over the button, toward the side
  // with room.
  var menuRow = null;
  function menuEl() { return root.querySelector('[data-address-menu]'); }
  function closeMenu() {
    var menu = menuEl();
    if (menu) menu.hidden = true;
    menuRow = null;
  }
  function openMenu(button) {
    var menu = menuEl();
    if (!menu) return;
    menuRow = button.closest('.pt-arow');
    var values = JSON.parse(menuRow.dataset.addressRow);
    menu.querySelector('[data-menu=default]').hidden = !!values.is_default;
    menu.hidden = false;
    var b = button.getBoundingClientRect(), w = menu.offsetWidth, h = menu.offsetHeight;
    var vw = document.documentElement.clientWidth, vh = window.innerHeight;
    var left = b.left > vw - b.right ? b.right - w : b.left;
    left = Math.max(8, Math.min(left, vw - 8 - w));
    var top = Math.max(8, Math.min(b.top, vh - 8 - h));
    menu.style.left = left + 'px';
    menu.style.top = top + 'px';
    menu.style.animation = 'none'; menu.offsetWidth; menu.style.animation = '';
  }
  document.addEventListener('scroll', closeMenu, true);
  window.addEventListener('resize', closeMenu);

  // The search on Google Maps (`TypeAheadField`), through the store's proxy.
  var sugTimer = null, sugSeq = 0, sugItems = [], sugIndex = -1;
  function sugList(form) { return form.querySelector('.pt-sugs'); }
  function closeSugs(form) {
    var list = sugList(form);
    if (!list) return;
    list.hidden = true; list.innerHTML = ''; sugItems = []; sugIndex = -1;
    var input = field(form, 'search');
    if (input) input.setAttribute('aria-expanded', 'false');
  }
  function paintSugs(form, items, note) {
    var list = sugList(form), input = field(form, 'search');
    sugItems = items; sugIndex = -1;
    list.innerHTML = '';
    if (note) { var li = document.createElement('li'); li.className = 'note'; li.innerHTML = note; list.appendChild(li); }
    items.forEach(function (s, i) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option'); li.dataset.index = String(i);
      li.innerHTML = root.dataset.placeIcon || '';
      var span = document.createElement('span'); span.textContent = s.description; li.appendChild(span);
      list.appendChild(li);
    });
    list.hidden = false;
    input.setAttribute('aria-expanded', 'true');
  }
  function suggest(form) {
    var q = field(form, 'search').value.trim();
    clearTimeout(sugTimer);
    if (!places || q.length < 3) { closeSugs(form); return; }
    sugTimer = setTimeout(function () {
      var mine = ++sugSeq;
      paintSugs(form, [], root.dataset.spinner || '');
      places.suggest(q, placesToken).then(function (list) {
        if (mine !== sugSeq) return;
        if (list.length) paintSugs(form, list); else paintSugs(form, [], 'No encontramos coincidencias');
      }, function () { if (mine === sugSeq) paintSugs(form, [], 'No encontramos coincidencias'); });
    }, 300);
  }
  // `_applyResolvedAddress`.
  function pick(form, s) {
    closeSugs(form);
    var input = field(form, 'search'), box = input.closest('.pt-f'), spin = box.querySelector('.pt-f-busy');
    var dialog = form.closest('.pt-dlg'), mine = ++placeSeq;
    var current = function () { return mine === placeSeq && dialog.open && !dialog.closing; };
    input.blur();
    if (spin) spin.hidden = false;
    places.details(s.placeId, placesToken).then(function (r) {
      if (!current()) return;
      if (!r) { toast('No pudimos cargar esa dirección'); return; }
      var street = r.street.trim() || (r.formatted || '').split(',')[0].trim();
      var comuna = (r.comuna || '').trim() || (r.city || '').trim();
      var city = (r.city || '').trim() || comuna;
      field(form, 'street_address').value = street;
      field(form, 'street_number').value = (r.number || '').trim();
      if (r.apartment && r.apartment.trim()) field(form, 'apartment').value = r.apartment.trim();
      field(form, 'comuna').value = comuna;
      field(form, 'city').value = city;
      field(form, 'region').value = (r.region || '').trim();
      field(form, 'postal_code').value = (r.postal || '').trim();
      placesToken = places.token();
    }, function () { if (current()) toast('No pudimos cargar esa dirección'); }).then(function () { if (mine === placeSeq && spin) spin.hidden = true; });
  }

  // ---- events -------------------------------------------------------------
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!form.matches || !form.matches('[data-form]') || !document.contains(form) || !(root.contains(form) || form.closest('.pt-dlg'))) return;
    event.preventDefault();
    var open = form.closest('.pt-dlg');
    if (form.dataset.busy || (open && (open.closing || !open.open))) return;
    var kind = form.dataset.form;
    if (kind === 'profile') saveProfile(form);
    else if (kind === 'password') submitPassword(form);
    else if (kind === 'address') saveAddress(form);
    else if (kind === 'address-delete') deleteAddress(form);
  });

  document.addEventListener('input', function (event) {
    var el = event.target;
    if (!el.closest || !root.contains(el)) return;
    if (el.name === 'code') {
      var digits = el.value.replace(/\D+/g, '').slice(0, 6);
      if (digits !== el.value) el.value = digits;
      var dialog = el.closest('.pt-dlg');
      if (dialog) say(dialog, 'verification', null);
    } else if (el.name === 'search') suggest(el.form);
  });
  document.addEventListener('change', function (event) {
    var el = event.target;
    if (el.name === 'profile_contact' && el.form && root.contains(el)) applyMine(el.form);
  });
  document.addEventListener('keydown', function (event) {
    var el = event.target;
    if (event.key === 'Escape' && menuEl() && !menuEl().hidden) { var row = menuRow; closeMenu(); if (row) row.querySelector('[data-address-more]').focus(); return; }
    if (el.name !== 'search' || !el.form) return;
    var list = sugList(el.form);
    if (!list || list.hidden || !sugItems.length) { if (event.key === 'Enter') event.preventDefault(); return; }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      sugIndex = (sugIndex + (event.key === 'ArrowDown' ? 1 : -1) + sugItems.length) % sugItems.length;
      Array.prototype.forEach.call(list.querySelectorAll('[role=option]'), function (li, i) { li.setAttribute('aria-selected', i === sugIndex ? 'true' : 'false'); });
    } else if (event.key === 'Enter') {
      event.preventDefault();
      if (sugIndex >= 0) pick(el.form, sugItems[sugIndex]);
    } else if (event.key === 'Escape') { event.stopPropagation(); closeSugs(el.form); }
  });
  document.addEventListener('focusout', function (event) {
    var el = event.target;
    if (el.name === 'search' && el.form) setTimeout(function () { if (document.activeElement !== el) closeSugs(el.form); }, 150);
  });
  document.addEventListener('mousedown', function (event) {
    var li = event.target.closest && event.target.closest('.pt-sugs [role=option]');
    if (!li) return;
    event.preventDefault();
    var form = li.closest('form');
    pick(form, sugItems[+li.dataset.index]);
  });

  document.addEventListener('click', function (event) {
    var menu = menuEl();
    if (menu && !menu.hidden && !menu.contains(event.target) && !(event.target.closest && event.target.closest('[data-address-more]'))) closeMenu();
    var target = event.target.closest && event.target.closest('[data-sheet],[data-close],[data-view-to],[data-act],[data-file],[data-password],[data-address],[data-address-more],[data-menu]');
    if (!target || !root.contains(target)) return;
    if (target.dataset.sheet) {
      event.preventDefault();
      var open = target.closest('.pt-dlg');
      if (open) closeSheet(open);
      openSheet(target.dataset.sheet, target);
    } else if (target.hasAttribute('data-close')) {
      var dialog = target.closest('.pt-dlg');
      if (dialog && !dialog.busy) closeSheet(dialog);
    } else if (target.dataset.viewTo) {
      showView(target);
    } else if (target.dataset.file) {
      openFile(target);
    } else if (target.dataset.password) {
      openPassword(target);
    } else if (target.dataset.address) {
      openAddress(target.dataset.address === 'edit' ? target.closest('.pt-arow') : null, target);
    } else if (target.hasAttribute('data-address-more')) {
      if (menu && !menu.hidden && menuRow === target.closest('.pt-arow')) closeMenu(); else openMenu(target);
    } else if (target.dataset.menu) {
      var row = menuRow;
      closeMenu();
      if (!row) return;
      if (target.dataset.menu === 'edit') openAddress(row, row.querySelector('[data-address-more]'));
      else if (target.dataset.menu === 'default') rowChange('address-default', row, null, 'No pudimos cambiar la principal. Intenta de nuevo.');
      else if (target.dataset.menu === 'delete') openDelete(row);
    } else if (target.dataset.act === 'profile-edit') {
      editProfile(true);
    } else if (target.dataset.act === 'profile-cancel') {
      editProfile(false);
    } else if (target.dataset.act === 'password-resend') {
      resendCode(target);
    } else if (target.dataset.act === 'portal-sign-out') {
      target.disabled = true;
      var to = target.dataset.to || '/';
      (session ? session.signOut() : Promise.resolve()).then(function () { location.assign(to); });
    } else if (target.dataset.act === 'portal-retry') {
      load();
    }
  });

  // A photo that does not load shows what Flutter's errorBuilder shows.
  document.addEventListener('error', function (event) {
    var image = event.target;
    if (!image.matches || !image.matches('.pt-pimg>img')) return;
    var box = image.parentNode;
    box.classList.add('failed');
    var fallback = box.querySelector('.pt-pimg-fb');
    if (fallback) fallback.hidden = false;
  }, true);

  load();
})();
''';
