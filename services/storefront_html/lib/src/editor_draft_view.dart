/// The draft's own look and behaviour, added before `</body>`: the
/// editor's marks (the only visual difference the editor contract allows),
/// links that do not leave the page, and a click that tells the editor which
/// part it picked.
///
/// The marks are a layer over the page, as Shopify's and Wix's editors draw
/// theirs, never a style on the page's own elements: an outline on an
/// element was hidden under a positioned child (the product photo), and the
/// `position: relative` it needed took the header off its sticky place.
const draftExtrasHtml =
    '<style>$_draftCss</style><script>$_draftScript</script>';

const _draftCss = '''
.vb-mark{position:fixed;z-index:2147483646;pointer-events:none;display:none;box-sizing:border-box;
  border:1px dashed rgb(26 115 232 / .75);border-radius:2px}
.vb-mark.vb-on{display:block}
.vb-mark.vb-picked{border:2px solid #1a73e8}
.vb-mark span{position:absolute;left:-2px;top:-22px;padding:2px 8px;border-radius:4px 4px 4px 0;
  background:#1a73e8;color:#fff;font:600 11px/16px system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-mark.vb-inside span{top:0;left:0;border-radius:0 0 4px 0}
.draft-missing{display:grid;place-items:center;gap:4px;min-height:160px;margin:0;padding:24px;
  border:1px dashed #9aa0a6;border-radius:8px;background:repeating-linear-gradient(135deg,#f8f9fa 0 12px,#f1f3f4 12px 24px);
  color:#5f6368;font:400 14px/1.4 var(--body,system-ui);text-align:center}
.draft-missing p{margin:0;max-width:52ch}
.draft-missing-t{font-weight:700;color:#3c4043}
''';

/// A click picks the part under it and goes nowhere: the editor hears it
/// through the web view's handler (`vbDraftPick`) or, in the ERP on the
/// web, a message to the page that holds the frame. The editor marks its
/// selection with `vbDraftPicked(id)`; the pointer's part is marked as it
/// passes, both following the page as it scrolls or changes size.
const _draftScript = r'''
(function () {
  function tell(id) {
    var host = window.flutter_inappwebview;
    if (host && host.callHandler) { host.callHandler('vbDraftPick', id); return; }
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: 'vb-draft-pick', id: id }, '*');
    }
  }
  function mark(picked) {
    var el = document.createElement('div');
    el.className = picked ? 'vb-mark vb-picked' : 'vb-mark';
    el.appendChild(document.createElement('span'));
    document.body.appendChild(el);
    return { el: el, target: null };
  }
  var hover = mark(false), pick = mark(true), pickedId = null;
  function place(m) {
    var t = m.target;
    if (!t || !t.isConnected) { m.el.classList.remove('vb-on'); return; }
    var r = t.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) { m.el.classList.remove('vb-on'); return; }
    var s = m.el.style;
    s.left = r.left + 'px'; s.top = r.top + 'px';
    s.width = r.width + 'px'; s.height = r.height + 'px';
    m.el.firstChild.textContent = t.getAttribute('data-block-label') || '';
    m.el.firstChild.style.display = m.el.firstChild.textContent ? '' : 'none';
    m.el.classList.toggle('vb-inside', r.top < 24);
    m.el.classList.add('vb-on');
  }
  function part(node) {
    return node && node.closest ? node.closest('[data-block-id]') : null;
  }
  function refresh() {
    place(pick);
    if (hover.target && hover.target === pick.target) hover.el.classList.remove('vb-on');
    else place(hover);
  }
  var queued = false;
  function soon() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; refresh(); });
  }
  document.addEventListener('click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    var found = part(event.target);
    tell(found ? found.getAttribute('data-block-id') : null);
  }, true);
  document.addEventListener('submit', function (event) { event.preventDefault(); }, true);
  document.addEventListener('mouseover', function (event) {
    hover.target = part(event.target);
    soon();
  }, true);
  document.addEventListener('mouseleave', function () { hover.target = null; soon(); });
  addEventListener('scroll', soon, { passive: true, capture: true });
  addEventListener('resize', soon);
  addEventListener('load', soon);
  if (window.ResizeObserver) new ResizeObserver(soon).observe(document.body);
  window.vbDraftPicked = function (id) {
    pickedId = id || null;
    pick.target = null;
    if (pickedId) {
      [].some.call(document.querySelectorAll('[data-block-id]'), function (el) {
        if (el.getAttribute('data-block-id') !== pickedId) return false;
        pick.target = el;
        return true;
      });
    }
    refresh();
  };
})();
''';
