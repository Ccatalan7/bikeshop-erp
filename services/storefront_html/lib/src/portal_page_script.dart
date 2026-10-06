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
const portalPageScript = r'''
(function () {
  var root = document.querySelector('[data-portal-root]');
  if (!root) return;
  var session = window.vinabikeSession;
  var viewUrl = root.dataset.viewUrl, fileUrl = root.dataset.fileUrl;
  var path = location.pathname.replace(/^\/_html(?=\/)/, '');

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

  function ask(token) {
    return fetch(viewUrl, {
      method: 'POST',
      headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' },
      body: JSON.stringify({ path: path, query: location.search.replace(/^\?/, '') }),
      credentials: 'omit',
      cache: 'no-store'
    }).then(function (r) { return r.json(); });
  }

  function reveal() {
    var tab = root.querySelector('.pt-tab.on'), strip = tab && tab.parentNode;
    if (!strip || strip.scrollWidth <= strip.clientWidth) return;
    strip.scrollLeft = tab.offsetLeft - (strip.clientWidth - tab.offsetWidth) / 2;
  }

  function load() {
    if (!session || !session.read()) { boundary('signedOut'); return; }
    boundary('loading');
    session.current().then(function (s) {
      if (!s) return { state: 'signed-out' };
      return ask(s.access_token).then(function (answer) {
        if (!answer || answer.state !== 'expired') return answer;
        return session.renew().then(function (fresh) {
          return fresh ? ask(fresh.access_token) : { state: 'signed-out' };
        });
      });
    }).then(function (answer) {
      if (answer && typeof answer.html === 'string') {
        root.innerHTML = answer.html;
        reveal();
        return;
      }
      boundary(answer && answer.state === 'expired' || answer && answer.state === 'signed-out' ? 'signedOut' : 'notCustomer');
    }, function () { boundary('notCustomer'); });
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

  // ---- sheets -----------------------------------------------------------
  var html = document.documentElement;
  function openSheet(id, opener) {
    var dialog = document.getElementById(id);
    if (!dialog || dialog.open) return;
    dialog.opener = opener;
    dialog.showModal();
    html.classList.add('pt-dlg-lock');
    dialog.offsetWidth;
    dialog.classList.add('in');
  }
  function closeSheet(dialog) {
    if (!dialog.open || dialog.closing) return;
    dialog.closing = true;
    dialog.classList.remove('in');
    var panel = dialog.querySelector('.pt-panel'), done = false;
    function finish() {
      if (done) return;
      done = true;
      dialog.closing = false;
      dialog.close();
      if (!document.querySelector('.pt-dlg[open]')) html.classList.remove('pt-dlg-lock');
      if (dialog.opener && dialog.opener.focus) dialog.opener.focus();
    }
    panel.addEventListener('transitionend', finish, { once: true });
    setTimeout(finish, 320);
  }
  document.addEventListener('cancel', function (event) {
    if (event.target.matches && event.target.matches('.pt-dlg')) {
      event.preventDefault();
      closeSheet(event.target);
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

  // ---- clicks -----------------------------------------------------------
  document.addEventListener('click', function (event) {
    var target = event.target.closest && event.target.closest('[data-sheet],[data-close],[data-view-to],[data-act],[data-file]');
    if (!target || !root.contains(target)) return;
    if (target.dataset.sheet) {
      event.preventDefault();
      var open = target.closest('.pt-dlg');
      if (open) closeSheet(open);
      openSheet(target.dataset.sheet, target);
    } else if (target.hasAttribute('data-close')) {
      closeSheet(target.closest('.pt-dlg'));
    } else if (target.dataset.viewTo) {
      showView(target);
    } else if (target.dataset.file) {
      openFile(target);
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
