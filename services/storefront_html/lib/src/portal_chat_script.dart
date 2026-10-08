import 'dart:convert';

import 'package:vinabike_public_core/public_store/models/customer_chat_words.dart';

/// «Soporte»'s behavior (4h), after the portal's script
/// (`window.vinabikePortal`), as Flutter's `CustomerChatHubPage`,
/// `CustomerChatView` and `ChatProvider` behave:
///
/// - **Live.** The page listens to Supabase Realtime with the customer's
///   session (`postgres_changes` on the open conversation's messages and
///   its row, or on the conversations for the list; row security decides
///   what reaches it) and redraws its parts from the server when something
///   changes. Without Realtime it asks again every 15 s while it is seen,
///   and always when it comes back to the screen or online.
/// - **Writing.** A message shows at once, marked while it is sent, and is
///   kept to retry if it does not go (the text comes back to the field when
///   it is empty, as Flutter). Each send carries its own key
///   (`client_message_id`); a send whose answer was lost is retried with the
///   same key and the server does not write it twice.
/// - **Reading.** While the conversation is seen, the latest message of the
///   store marks it read (`mark_conversation_read`).
/// - **History.** At the top, older messages load fifty at a time, by hand
///   or when the top is reached, and the reader stays on the same message.
/// - **The store's requests.** «Aprobar presupuesto», «Confirmar recibido»
///   and «Solicitar cambios» answer through the audited command.
/// - **Files.** A picture or document opens with a fresh link.
final portalChatScript =
    r'''
(function () {
  'use strict';
  var api = window.vinabikePortal, session = window.vinabikeSession;
  if (!api || !session) return;
  var root = api.root, W = /*WORDS*/{};
  var body = document.body;
  var sbUrl = (body.dataset.sbUrl || '').replace(/\/+$/, ''), sbKey = body.dataset.sbKey || '';
  var prefix = location.pathname.indexOf('/_html/') === 0 ? '/_html' : '';
  var coarse = window.matchMedia && matchMedia('(pointer: coarse)').matches;

  function page() { return root.querySelector('.pt-chatpage'); }
  function scroller() { var el = page(); return el && el.querySelector('[data-chat-scroll]'); }
  function key() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID().replace(/-/g, '');
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 12);
  }

  // The page fits the window under the store's header.
  function fit() {
    var top = document.querySelector('header.top');
    var height = top ? Math.round(top.getBoundingClientRect().height) : 56;
    document.documentElement.style.setProperty('--pt-top', height + 'px');
  }
  fit();
  window.addEventListener('resize', fit);

  var conversation = null, windowSize = 50, lastRead = null, stick = true;
  var refreshing = null, again = false, live = null, poll = null, timer = null;
  var sending = [];

  // ---- after every full draw ------------------------------------------------
  function setup() {
    var el = page();
    if (!el) { stopLive(); return; }
    var next = el.dataset.chat || null;
    // A redraw of the same conversation keeps what is on its way.
    if (next !== conversation) { sending = []; lastRead = null; }
    conversation = next;
    windowSize = +el.dataset.chatWindow || 50;
    api.extra.window = windowSize;
    fit();
    stick = true;
    resend();
    afterLog(true);
    autosize();
    startLive();
    markRead();
  }
  api.swapped.push(setup);

  // ---- redrawing parts --------------------------------------------------------
  function soon() { clearTimeout(timer); timer = setTimeout(refresh, 120); }
  function refresh(options) {
    if (refreshing) { again = true; return refreshing; }
    var el = page();
    if (!el) return Promise.resolve();
    var box = scroller(), anchor = null, anchorTop = 0;
    if (options && options.older && box) {
      anchor = box.querySelector('[data-msg]');
      anchorTop = anchor ? anchor.getBoundingClientRect().top : 0;
    }
    var atBottom = !box || stick;
    refreshing = api.post(api.viewUrl, { path: api.path, query: api.query(), pending: false, window: windowSize }).then(function (answer) {
      if (api.lost(answer)) return;
      if (!answer || typeof answer.html !== 'string') throw new Error('view');
      offline(false);
      patch(answer.html, atBottom, anchor && anchor.dataset.msg, anchorTop);
    }).catch(function () {
      offline(true);
      if (options && options.older) { windowSize = Math.max(50, windowSize - 50); api.extra.window = windowSize; olderFailed(); }
    }).then(function () {
      refreshing = null;
      if (again) { again = false; refresh(); }
    });
    return refreshing;
  }

  // A part is replaced only when it changed (each draw signs the files
  // again, so their addresses do not count), and a picture already shown
  // keeps its address: no new download, no focus lost, every 15 s.
  function bare(node) { return node.outerHTML.replace(/ (src|data-seen)="[^"]*"/g, ''); }
  function swapPart(el, fresh, selector) {
    var now = el.querySelector(selector), next = fresh.querySelector(selector);
    if (!now || !next || bare(now) === bare(next)) return false;
    Array.prototype.forEach.call(next.querySelectorAll('[data-msg] img'), function (image) {
      var id = image.closest('[data-msg]').dataset.msg;
      var old = now.querySelector('[data-msg="' + id + '"] img');
      if (old && old.complete && old.naturalWidth) image.setAttribute('src', old.getAttribute('src'));
    });
    now.replaceWith(next);
    return true;
  }
  function patch(markup, atBottom, anchorId, anchorTop) {
    var holder = document.createElement('template');
    holder.innerHTML = markup;
    var fresh = holder.content.querySelector('.pt-chatpage'), el = page();
    if (!fresh || !el || (fresh.dataset.chat || null) !== conversation) { api.swap(markup); return; }
    // The conversation now is about a job (or no longer): the page changes
    // its shape, so it is drawn whole, with what was being written.
    var shape = function (page) { return [!!page.querySelector('.pt-chat-side'), !!page.querySelector('.pt-chat-info')].join(); };
    if (conversation && shape(el) !== shape(fresh)) {
      var field = el.querySelector('.pt-chat-input'), draft = field ? field.value : '';
      api.swap(markup);
      var next = page() && page().querySelector('.pt-chat-input');
      if (next && draft) { next.value = draft; autosize(); }
      return;
    }
    swapPart(el, fresh, '.pt-chat-head');
    if (!conversation) {
      swapPart(el, fresh, '.pt-chat-list');
    } else {
      swapPart(el, fresh, '[data-chat-live="state"]');
      swapPart(el, fresh, '[data-chat-live="log"]');
      var compose = el.querySelector('[data-chat-live="compose"]'), next = fresh.querySelector('[data-chat-live="compose"]');
      if (compose && next) {
        var form = compose.querySelector('form'), nextForm = next.querySelector('form');
        if (!form !== !nextForm) compose.replaceWith(next);
        else if (form) {
          var hint = nextForm.elements.text.placeholder;
          form.elements.text.placeholder = hint;
          form.elements.text.setAttribute('aria-label', hint);
        }
      }
    }
    // Beside it, the job may have moved on.
    swapPart(el, fresh, '.pt-chat-side');
    syncDialogs(el, fresh);
    el.dataset.chatWindow = fresh.dataset.chatWindow;
    resend();
    afterLog(atBottom, anchorId, anchorTop);
    markRead();
  }
  // The sheets and dialogs drawn again, except one open now.
  function syncDialogs(el, fresh) {
    var mine = {};
    Array.prototype.forEach.call(el.querySelectorAll(':scope > dialog'), function (d) { mine[d.id] = d; });
    Array.prototype.forEach.call(fresh.querySelectorAll(':scope > dialog'), function (d) {
      var now = mine[d.id];
      delete mine[d.id];
      if (!now) el.appendChild(d);
      else if (!now.open && bare(now) !== bare(d)) now.replaceWith(d);
    });
    Object.keys(mine).forEach(function (id) { if (!mine[id].open) mine[id].remove(); });
  }

  // ---- the log: where it rests ---------------------------------------------------
  function afterLog(bottom, anchorId, anchorTop) {
    var box = scroller();
    if (!box) return;
    if (anchorId) {
      var target = box.querySelector('[data-msg="' + anchorId + '"]');
      if (target) box.scrollTop += target.getBoundingClientRect().top - anchorTop;
    } else if (bottom) {
      box.scrollTop = box.scrollHeight;
    }
    Array.prototype.forEach.call(box.querySelectorAll('img:not([data-seen])'), function (image) {
      image.dataset.seen = '1';
      if (!image.complete) image.addEventListener('load', function () { if (stick) box.scrollTop = box.scrollHeight; }, { once: true });
    });
    requestAnimationFrame(function () { maybeOlder(box); });
  }
  document.addEventListener('scroll', function (event) {
    var box = event.target;
    if (!box.matches || !box.matches('[data-chat-scroll]')) return;
    stick = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
    maybeOlder(box);
  }, true);

  // `_requestOlderMessagesIfAtStart`: near the top, or when the messages do
  // not fill the frame.
  function maybeOlder(box) {
    var button = box.querySelector('[data-chat-older]');
    if (!button || button.disabled || refreshing || windowSize >= 500) return;
    if (box.scrollTop < 180 || box.scrollHeight <= box.clientHeight) older(button);
  }
  function older(button) {
    if (windowSize >= 500) return;
    button.disabled = true;
    windowSize += 50;
    api.extra.window = windowSize;
    refresh({ older: true });
  }
  function olderFailed() {
    var box = scroller(), button = box && box.querySelector('[data-chat-older]');
    if (button) button.disabled = false;
    api.toast(W.olderFailed);
  }

  // ---- the line that says the conversation stopped updating ------------------------
  function offline(on) {
    var el = page(), frame = el && el.querySelector('[data-chat-frame]');
    if (!frame) return;
    var line = frame.querySelector('[data-chat-offline]');
    if (!on) { if (line) line.remove(); return; }
    if (line) return;
    line = document.createElement('div');
    line.className = 'pt-chat-banner offline';
    line.setAttribute('data-chat-offline', '');
    line.setAttribute('role', 'status');
    line.innerHTML = '<span class="pt-chat-banner-dot"></span><p></p><button type="button" class="pt-tbtn" data-chat-reload></button>';
    line.querySelector('p').textContent = W.offline;
    line.querySelector('button').textContent = W.retry;
    frame.insertBefore(line, frame.querySelector('[data-chat-scroll]'));
  }

  // ---- Realtime -----------------------------------------------------------------
  function startPoll() {
    if (poll) return;
    poll = setInterval(function () { if (document.visibilityState === 'visible') refresh(); }, 15000);
  }
  function stopPoll() { clearInterval(poll); poll = null; }
  function stopLive() { if (live) live.close(); live = null; stopPoll(); }
  function startLive() {
    var name = page() ? (conversation || 'list') : null;
    if (live && live.name === name) return;
    stopLive();
    if (!name) return;
    if (!sbUrl || !sbKey || !window.WebSocket) { startPoll(); return; }
    live = connect(name);
  }
  // Phoenix's protocol as `realtime-js` speaks it (vsn 1.0.0).
  function connect(name) {
    var changes = conversation ? [
      { event: '*', schema: 'public', table: 'messages', filter: 'conversation_id=eq.' + conversation },
      { event: '*', schema: 'public', table: 'conversations', filter: 'id=eq.' + conversation }
    ] : [{ event: '*', schema: 'public', table: 'conversations' }];
    var topic = 'realtime:portal-chat-' + key().slice(0, 12);
    var state = { closed: false, ws: null, ref: 0, joinRef: null, beat: null, retry: 0, wait: null, token: null, down: false };
    function send(event, payload, to) {
      if (!state.ws || state.ws.readyState !== 1) return;
      var message = { topic: to || topic, event: event, payload: payload, ref: String(++state.ref) };
      if (!to) message.join_ref = state.joinRef;
      state.ws.send(JSON.stringify(message));
    }
    function renew() {
      session.current().then(function (s) {
        if (s && s.access_token !== state.token) { state.token = s.access_token; send('access_token', { access_token: s.access_token }); }
      });
    }
    function again() {
      if (state.closed) return;
      state.down = true;
      clearInterval(state.beat);
      startPoll();
      clearTimeout(state.wait);
      state.wait = setTimeout(open, Math.min(30000, 1000 * Math.pow(2, state.retry++)));
    }
    function open() {
      session.current().then(function (s) {
        if (state.closed) return;
        if (!s) { startPoll(); return; }
        state.token = s.access_token;
        var ws;
        try { ws = new WebSocket(sbUrl.replace(/^http/, 'ws') + '/realtime/v1/websocket?apikey=' + encodeURIComponent(sbKey) + '&vsn=1.0.0'); }
        catch (e) { startPoll(); return; }
        state.ws = ws;
        ws.onopen = function () {
          state.joinRef = String(++state.ref);
          ws.send(JSON.stringify({
            topic: topic, event: 'phx_join', ref: state.joinRef, join_ref: state.joinRef,
            payload: { config: { broadcast: { ack: false, self: false }, presence: { key: '' }, postgres_changes: changes, private: false }, access_token: s.access_token }
          }));
          clearInterval(state.beat);
          state.beat = setInterval(function () { send('heartbeat', {}, 'phoenix'); renew(); }, 25000);
        };
        ws.onmessage = function (event) {
          var message;
          try { message = JSON.parse(event.data); } catch (e) { return; }
          if (message.topic !== topic) return;
          var payload = message.payload || {};
          if (message.event === 'phx_reply' && message.ref === state.joinRef) {
            if (payload.status !== 'ok') { startPoll(); return; }
            state.retry = 0;
            stopPoll();
            // What changed while it was down.
            if (state.down) { state.down = false; refresh(); }
          } else if (message.event === 'postgres_changes') {
            soon();
          } else if (message.event === 'system' && payload.status === 'error') {
            startPoll();
          } else if (message.event === 'phx_error' || message.event === 'phx_close') {
            try { ws.close(); } catch (e) {}
          }
        };
        ws.onclose = function () { if (state.ws === ws) again(); };
      }, function () { startPoll(); });
    }
    open();
    return {
      name: name,
      close: function () {
        state.closed = true;
        clearInterval(state.beat);
        clearTimeout(state.wait);
        if (state.ws) { var ws = state.ws; state.ws = null; try { ws.close(); } catch (e) {} }
      }
    };
  }
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible' && page()) { refresh(); markRead(); }
  });
  window.addEventListener('online', function () { if (page()) refresh(); });

  // ---- reading -----------------------------------------------------------------
  // `_markActiveConversationReadIfNeeded`: the store's latest message, while
  // the conversation is seen.
  function markRead() {
    var el = page();
    if (!el || !conversation || document.visibilityState !== 'visible') return;
    var theirs = el.querySelectorAll('[data-chat-live="log"] [data-msg][data-mine="0"]:not([data-sys])');
    var last = theirs.length ? theirs[theirs.length - 1].dataset.msg : null;
    if (!last || last === lastRead) return;
    lastRead = last;
    api.act('chat-read', { conversation: conversation, message: last }).then(function (answer) {
      if (!answer || answer.read !== true) lastRead = null;
    }, function () { lastRead = null; });
  }

  // ---- writing -----------------------------------------------------------------
  function autosize() {
    var el = page(), input = el && el.querySelector('.pt-chat-input');
    if (!input) return;
    input.style.height = '48px';
    input.style.height = Math.min(input.scrollHeight + 2, 148) + 'px';
  }
  function bubble(item) {
    var row = document.createElement('div');
    row.className = 'pt-msg mine sending';
    row.dataset.mine = '1';
    row.dataset.client = item.client;
    row.innerHTML = '<div class="pt-msg-b"><p class="pt-msg-text"></p><span class="pt-msg-time"></span></div>';
    row.querySelector('.pt-msg-text').textContent = item.text;
    row.querySelector('.pt-msg-time').textContent = W.sending;
    return row;
  }
  // The messages still on their way, after a redraw that does not have them yet.
  function resend() {
    var log = page() && page().querySelector('[data-chat-live="log"]');
    if (!log) return;
    sending = sending.filter(function (item) {
      if (log.querySelector('[data-client="' + item.client + '"]:not(.sending)')) return false;
      item.row = bubble(item);
      log.appendChild(item.row);
      return true;
    });
  }
  function send(form) {
    var input = form.elements.text, text = input.value.trim();
    if (!text || !conversation) return;
    // The same text after a send whose answer was lost goes with its key.
    if (form.dataset.clientText !== text) { form.dataset.client = key(); form.dataset.clientText = text; }
    var item = { client: form.dataset.client, text: text };
    input.value = '';
    autosize();
    var log = page().querySelector('[data-chat-live="log"]');
    item.row = bubble(item);
    log.appendChild(item.row);
    sending.push(item);
    stick = true;
    afterLog(true);
    api.act('chat-send', { conversation: conversation, text: text, client: item.client }).then(function (answer) {
      if (answer && answer.sent) {
        delete form.dataset.client; delete form.dataset.clientText;
        refresh();
        return;
      }
      if (api.lost(answer)) return;
      failed(answer && answer.uncertain, answer && answer.toast);
    }, function () { failed(true); });
    function failed(uncertain, message) {
      sending = sending.filter(function (other) { return other !== item; });
      if (item.row) item.row.remove();
      if (!uncertain) { delete form.dataset.client; delete form.dataset.clientText; }
      var field = page() && page().querySelector('.pt-chat-input');
      if (field && field.value.trim() === '') { field.value = text; autosize(); }
      api.toast(message || W.sendFailed);
    }
  }

  // ---- a new consultation ----------------------------------------------------------
  function openNew(opener) {
    var dialog = document.querySelector('[data-chat-new-dialog]');
    if (!dialog) return;
    var form = dialog.querySelector('form');
    form.reset();
    api.clearErrors(form);
    delete form.dataset.key; delete form.dataset.keyText;
    api.openSheet(dialog.id, opener);
    setTimeout(function () { var field = form.querySelector('textarea'); if (field) field.focus(); }, 40);
  }
  function submitNew(form) {
    var text = form.querySelector('textarea').value.trim();
    if (!text) return;
    if (form.dataset.keyText !== text) { form.dataset.key = key(); form.dataset.keyText = text; }
    api.busy(form, true);
    api.act('chat-new', { message: text, key: form.dataset.key }).then(function (answer) {
      if (answer && answer.conversation) { location.assign(prefix + '/cuenta/chats/' + answer.conversation); return; }
      api.busy(form, false);
      if (api.lost(answer)) return;
      if (!(answer && answer.uncertain)) delete form.dataset.keyText;
      api.toast((answer && answer.toast) || W.newFailed);
    }, function () {
      api.busy(form, false);
      api.toast(W.newFailed);
    });
  }

  // ---- the store's requests ----------------------------------------------------------
  var asking = null;
  function respond(card, type, status, note) {
    if (card.dataset.busy) return Promise.resolve(false);
    card.dataset.busy = '1';
    var buttons = card.querySelectorAll('button'), spin = card.querySelector('.pt-btn-spin');
    Array.prototype.forEach.call(buttons, function (b) { b.disabled = true; });
    if (spin && status === 'accepted') spin.hidden = false;
    return api.act('chat-answer', { message: card.dataset.msg, type: type, status: status, note: note || '' }).then(function (answer) {
      if (api.lost(answer)) return false;
      api.toast(answer && answer.toast);
      refresh();
      return !!answer && (answer.toast === W.accepted || answer.toast === W.declined);
    }, function () {
      api.toast(W.uncertain);
      return false;
    }).then(function (done) {
      delete card.dataset.busy;
      if (document.contains(card)) {
        Array.prototype.forEach.call(buttons, function (b) { b.disabled = false; });
        if (spin) spin.hidden = true;
      }
      return done;
    });
  }
  function openChanges(card, type, opener) {
    var dialog = document.querySelector('[data-chat-changes-dialog]');
    if (!dialog) return;
    var form = dialog.querySelector('form');
    form.reset();
    api.clearErrors(form);
    asking = { card: card, type: type };
    api.openSheet(dialog.id, opener);
    setTimeout(function () { var field = form.querySelector('textarea'); if (field) field.focus(); }, 40);
  }
  function submitChanges(form) {
    var note = form.querySelector('textarea').value.trim();
    var dialog = form.closest('.pt-dlg');
    if (!note || !asking) return;
    var card = page() && page().querySelector('[data-msg="' + asking.card.dataset.msg + '"]');
    if (!card) { api.closeSheet(dialog); return; }
    api.busy(form, true);
    respond(card, asking.type, 'declined', note).then(function (done) {
      api.busy(form, false);
      if (done) api.closeSheet(dialog);
    });
  }

  // ---- files -----------------------------------------------------------------
  function openFile(button) {
    if (button.classList.contains('failed')) { refresh(); return; }
    var row = button.closest('[data-msg]');
    var tab = window.open('', '_blank');
    api.act('chat-file', { conversation: conversation, message: row.dataset.msg }).then(function (answer) {
      if (answer && answer.url) {
        if (tab) { tab.opener = null; tab.location.href = answer.url; } else location.assign(answer.url);
        return;
      }
      if (tab) tab.close();
      if (!api.lost(answer)) api.toast((answer && answer.toast) || W.fileFailed);
    }, function () {
      if (tab) tab.close();
      api.toast(W.fileFailed);
    });
  }
  document.addEventListener('error', function (event) {
    var image = event.target;
    if (!image.matches || !image.matches('.pt-msg-img img')) return;
    var button = image.closest('.pt-msg-img');
    button.classList.add('failed');
    image.hidden = true;
    var note = button.querySelector('.pt-msg-img-bad');
    if (note) note.hidden = false;
  }, true);

  // ---- events -------------------------------------------------------------------
  document.addEventListener('click', function (event) {
    var target = event.target.closest && event.target.closest('[data-chat-new],[data-chat-older],[data-chat-file],[data-chat-retry],[data-chat-reload],[data-chat-answer]');
    if (!target || !root.contains(target)) return;
    if (target.hasAttribute('data-chat-new')) openNew(target);
    else if (target.hasAttribute('data-chat-older')) older(target);
    else if (target.hasAttribute('data-chat-file')) openFile(target);
    else if (target.hasAttribute('data-chat-retry') || target.hasAttribute('data-chat-reload')) refresh();
    else if (target.dataset.chatAnswer) {
      var card = target.closest('[data-msg]');
      if (target.dataset.chatAnswer === 'declined') openChanges(card, target.dataset.askType, target);
      else respond(card, target.dataset.askType, 'accepted', '');
    }
  });
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!form.matches || !document.contains(form)) return;
    if (form.matches('[data-chat-compose]')) { event.preventDefault(); send(form); return; }
    var kind = form.dataset.form;
    if (kind !== 'chat-new' && kind !== 'chat-changes') return;
    event.preventDefault();
    var dialog = form.closest('.pt-dlg');
    if (form.dataset.busy || (dialog && (dialog.closing || !dialog.open))) return;
    if (kind === 'chat-new') submitNew(form); else submitChanges(form);
  });
  // Enter sends and Shift+Enter breaks the line, as Flutter's shortcut; on a
  // touch keyboard Enter breaks the line.
  document.addEventListener('keydown', function (event) {
    var input = event.target;
    if (!input.matches || !input.matches('.pt-chat-input')) return;
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing || coarse) return;
    event.preventDefault();
    if (input.form.requestSubmit) input.form.requestSubmit(); else send(input.form);
  });
  document.addEventListener('input', function (event) {
    if (event.target.matches && event.target.matches('.pt-chat-input')) autosize();
  });
})();
'''
        .replaceFirst('/*WORDS*/{}', jsonEncode(_words));

const _words = {
  'sendFailed': customerChatSendFailed,
  'newFailed': customerChatNewFailed,
  'accepted': customerChatAccepted,
  'declined': customerChatDeclined,
  'uncertain': customerChatAnswerUncertain,
  'fileFailed': customerChatFileRenewFailed,
  'offline': customerChatOffline,
  'olderFailed': customerChatOlderFailed,
  'retry': customerChatRetry,
  'sending': customerChatSending,
};
