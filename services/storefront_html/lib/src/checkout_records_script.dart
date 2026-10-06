/// The checkout's records, as `CheckoutSessionStore` writes them (Flutter):
/// the recovery snapshot of an attempt, the order's access, and the cart's
/// one-time subtraction. Kept apart from the page so
/// `test/unit/storefront_html_checkout_contract_test.dart` can run it in
/// Node and read what it wrote with Flutter's own readers, both ways.
///
/// `window.vinabikeCheckoutRecords(tenant, cart)` returns the operations;
/// `cart` is the page script's `window.vinabikeCart`.
const checkoutRecordsScript = r'''
(function () {
  window.vinabikeCheckoutRecords = function (tenant, cart) {
  var checkoutKey = 'vinabike.public-checkout.v1.' + tenant;
  var MAX_AGE = 2 * 3600e3, SKEW = 5 * 6e4;
  var UUID4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  // ---- small helpers -------------------------------------------------------
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  // Dart's base64Url.encode: URL alphabet, padding kept.
  function b64(text) {
    var bytes = new TextEncoder().encode(text), bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_');
  }
  function accessKey(order) { return 'vinabike.public-order-access.v1.' + b64(tenant) + '.' + b64(order); }
  function outcomeKey(order) { return 'vinabike.public-cart-preserved.v1.' + b64(tenant) + '.' + b64(order); }
  function nowIso() { return new Date().toISOString(); }
  function text(v) { return v == null ? '' : String(v).trim(); }
  function isMoney(v) { return typeof v === 'number' && isFinite(v) && v >= 0; }
  // A timestamp as Dart's `toUtc().toIso8601String()` writes it: milliseconds
  // always, microseconds only when there are some.
  function dartIso(value) {
    var m = /^(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]00(?::?00)?)$/.exec(String(value || ''));
    if (m) {
      var frac = ((m[3] || '') + '000000').slice(0, 6);
      return m[1] + 'T' + m[2] + '.' + frac.slice(0, 3) + (frac.slice(3) === '000' ? '' : frac.slice(3)) + 'Z';
    }
    var t = Date.parse(value);
    return isFinite(t) ? new Date(t).toISOString() : null;
  }


  // ---- sessionStorage, strict like BrowserCheckoutSessionStorage ---------
  function ssRead(key) { return sessionStorage.getItem(key); }
  function ssWrite(key, value) {
    sessionStorage.setItem(key, value);
    if (sessionStorage.getItem(key) !== value) throw new Error('storage');
  }
  function ssClear(key) {
    sessionStorage.setItem(key, '');
    var left = sessionStorage.getItem(key);
    if (left !== null && left !== '') throw new Error('storage');
  }

  // PublicOrderCheckoutAccess.fromRpc
  function parseReceipt(value) {
    if (!value || typeof value !== 'object') return null;
    var order = text(value.order_id), token = text(value.access_token);
    var expires = dartIso(value.expires_at);
    if (!order || token.length < 40 || token.length > 128 || !expires) return null;
    return { order_id: order, access_token: token, expires_at: expires, replay: value.replay === true };
  }

  // CheckoutSessionSnapshot._parse, field for field.
  function parseSnapshot(raw) {
    var j;
    try { j = JSON.parse(raw); } catch (e) { return null; }
    if (!j || typeof j !== 'object' || j.v !== 1) return null;
    var t = text(j.tenant_id), key = text(j.idempotency_key);
    if (!t || t !== tenant || !isFinite(Date.parse(j.saved_at || '')) || !key || !UUID4.test(key)) return null;
    var od = j.order_data, items = j.order_items;
    if (!od || typeof od !== 'object' || Array.isArray(od) || !Array.isArray(items) || !items.length) return null;
    var seen = {};
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      if (!it || typeof it !== 'object') return null;
      var pid = text(it.product_id);
      if (!pid || seen[pid]) return null;
      seen[pid] = true;
    }
    var fields = ['subtotal', 'tax_amount', 'shipping_quote_cost', 'shipping_cost', 'discount_amount', 'total'];
    if (String(od.tenant_id) !== t || String(od.checkout_idempotency_key) !== key ||
        !text(od.customer_email) || !text(od.customer_name) || !text(od.customer_address) ||
        od.status !== 'pending' || od.payment_status !== 'pending' ||
        fields.some(function (f) { return !isMoney(od[f]); }) ||
        items.some(function (it) {
          return String(it.tenant_id) !== t || !text(it.product_id) || !text(it.product_name) ||
            !(typeof it.quantity === 'number' && it.quantity === Math.floor(it.quantity) && it.quantity >= 1) ||
            !isMoney(it.unit_price) || !isMoney(it.subtotal);
        })) return null;
    var h = j.handoff;
    if (!h || ['mercadopago', 'transfer'].indexOf(h.payment_method) < 0 || ['shipping', 'pickup'].indexOf(h.delivery_type) < 0 ||
        String(od.payment_method) !== h.payment_method || String(od.delivery_type) !== h.delivery_type) return null;
    if (j.receipt != null && !parseReceipt(j.receipt)) return null;
    var closed = j.cart_consumption_closed_at, status = j.cart_consumption_status;
    if (closed != null || status != null) {
      if (closed == null || status == null || !j.receipt || !isFinite(Date.parse(closed)) ||
          ['consuming', 'preserved', 'applied'].indexOf(status) < 0 ||
          (status === 'consuming' && !text(j.cart_consumption_claim_id))) return null;
    }
    return j;
  }

  // CheckoutSessionStore._readUnlocked: a stale or unreadable record is
  // retired, unless something else wrote it meanwhile.
  function readSnapshot() {
    var raw = ssRead(checkoutKey);
    if (!raw) return null;
    var snap = parseSnapshot(raw);
    var now = Date.now();
    var fresh = snap && Date.parse(snap.saved_at) <= now + SKEW && now - Date.parse(snap.saved_at) <= MAX_AGE &&
      (!snap.receipt || Date.parse(snap.receipt.expires_at) > now);
    if (fresh) return snap;
    if (ssRead(checkoutKey) === raw) ssClear(checkoutKey);
    return null;
  }

  function encodeSnapshot(s) {
    var out = {
      v: 1, tenant_id: s.tenant_id, saved_at: s.saved_at, idempotency_key: s.idempotency_key,
      order_data: s.order_data, order_items: s.order_items, handoff: s.handoff
    };
    if (s.cart_revision != null) out.cart_revision = s.cart_revision;
    if (s.receipt) out.receipt = { order_id: s.receipt.order_id, access_token: s.receipt.access_token, expires_at: s.receipt.expires_at, replay: s.receipt.replay === true };
    if (s.cart_consumption_closed_at != null) out.cart_consumption_closed_at = s.cart_consumption_closed_at;
    if (s.cart_consumption_status != null) out.cart_consumption_status = s.cart_consumption_status;
    if (s.cart_consumption_claim_id != null) out.cart_consumption_claim_id = s.cart_consumption_claim_id;
    return JSON.stringify(out);
  }
  function saveSnapshot(s) {
    var encoded = encodeSnapshot(s);
    if (!parseSnapshot(encoded)) throw new Error('snapshot');
    ssWrite(checkoutKey, encoded);
  }

  // _saveOrderAccessUnlocked
  function saveOrderAccess(receipt) {
    if (!receipt.order_id || receipt.access_token.length < 40 || receipt.access_token.length > 128 ||
        !(Date.parse(receipt.expires_at) > Date.now())) throw new Error('access');
    ssWrite(accessKey(receipt.order_id), JSON.stringify({
      v: 1, tenant_id: tenant, order_id: receipt.order_id, access_token: receipt.access_token,
      expires_at: receipt.expires_at, replay: receipt.replay === true
    }));
  }

  // ---- the cart's one-time subtraction (consumeCartOnce) -----------------
  function readOutcome(order) {
    var raw = ssRead(outcomeKey(order));
    if (!raw) return null;
    try {
      var o = JSON.parse(raw);
      if (o && o.tenant_id === tenant && o.order_id === order && (o.v === 1 || o.v === 2)) return o;
    } catch (e) { /* unreadable: Flutter retires it */ }
    return null;
  }
  function recordOutcome(order, state, reason) {
    var existing = readOutcome(order);
    if (existing) return existing;
    var o = { v: 2, tenant_id: tenant, order_id: order, state: state, finalized_at: nowIso() };
    if (reason) o.reason = reason;
    ssWrite(outcomeKey(order), JSON.stringify(o));
    return o;
  }
  function consumeCartOnce(order) {
    var existing = readOutcome(order);
    if (existing) return Promise.resolve(existing);
    var snap = readSnapshot();
    if (!snap || !snap.receipt || snap.receipt.order_id !== order) return Promise.resolve(recordOutcome(order, 'preserved', 'snapshot_missing'));
    var status = snap.cart_consumption_status;
    if (status === 'applied') return Promise.resolve(recordOutcome(order, 'applied'));
    if (status === 'preserved') return Promise.resolve(recordOutcome(order, 'preserved', 'legacy_preserved'));
    if (status === 'consuming') {
      var interrupted = recordOutcome(order, 'preserved', 'interrupted');
      try { snap.cart_consumption_status = 'preserved'; saveSnapshot(snap); } catch (e) { /* the outcome already decides */ }
      return Promise.resolve(interrupted);
    }
    if (!text(snap.cart_revision)) {
      snap.cart_consumption_closed_at = nowIso();
      snap.cart_consumption_status = 'preserved';
      saveSnapshot(snap);
      return Promise.resolve(recordOutcome(order, 'preserved', 'baseline_missing'));
    }
    var claim = uuid();
    snap.cart_consumption_closed_at = nowIso();
    snap.cart_consumption_status = 'consuming';
    snap.cart_consumption_claim_id = claim;
    saveSnapshot(snap);
    var ordered = snap.order_items.map(function (it) { return { id: String(it.product_id), q: it.quantity }; });
    return cart.consume(ordered, snap.cart_revision).catch(function () { return false; }).then(function (applied) {
      var terminal = recordOutcome(order, applied ? 'applied' : 'preserved', applied ? null : 'cart_unavailable');
      try {
        var current = readSnapshot();
        if (current && current.receipt && current.receipt.order_id === order &&
            current.cart_consumption_status === 'consuming' && current.cart_consumption_claim_id === claim) {
          current.cart_consumption_status = terminal.state === 'applied' ? 'applied' : 'preserved';
          saveSnapshot(current);
        }
      } catch (e) { /* the outcome stays authoritative */ }
      return terminal;
    });
  }


  return {
    key: checkoutKey, uuid: uuid, ssRead: ssRead, ssClear: ssClear,
    parseReceipt: parseReceipt, parseSnapshot: parseSnapshot, readSnapshot: readSnapshot,
    saveSnapshot: saveSnapshot, saveOrderAccess: saveOrderAccess, consumeCartOnce: consumeCartOnce
  };
  };
})();
''';
