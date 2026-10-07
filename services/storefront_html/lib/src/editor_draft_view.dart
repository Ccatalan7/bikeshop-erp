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
.vb-mark.vb-has-bar>span{display:none}
.vb-bar{position:absolute;right:8px;top:8px;display:flex;align-items:center;gap:2px;padding:2px 4px 2px 10px;
  border-radius:10px;box-shadow:0 2px 6px rgb(0 0 0 / .3);pointer-events:auto;
  font:700 12px/1 system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-bar{max-width:calc(100% - 16px);box-sizing:border-box}
.vb-bar b{margin-right:6px;min-width:0;overflow:hidden;text-overflow:ellipsis}
.vb-bar button{flex:none}
.vb-bar button{all:unset;display:grid;place-items:center;width:30px;height:30px;border-radius:8px;cursor:pointer}
.vb-bar button:hover,.vb-bar button:focus-visible{background:rgb(0 0 0 / .1)}
.vb-bar svg{width:18px;height:18px;fill:currentColor}
.draft-missing{display:grid;place-items:center;gap:4px;min-height:160px;margin:0;padding:24px;
  border:1px dashed #9aa0a6;border-radius:8px;background:repeating-linear-gradient(135deg,#f8f9fa 0 12px,#f1f3f4 12px 24px);
  color:#5f6368;font:400 14px/1.4 var(--body,system-ui);text-align:center}
.draft-missing p{margin:0;max-width:52ch}
.draft-missing-t{font-weight:700;color:#3c4043}
''';

/// A click picks the part under it and goes nowhere: the editor hears it
/// through the web view's handler (`vbDraftPick`) or, in the ERP on the
/// web, a message to the page that holds the frame. The editor marks its
/// selection with `vbDraftPicked(id, info)`, `info.bar` saying which of the
/// block bar's buttons apply (a press goes back as `vbDraftAction`); the pointer's part is marked as it
/// passes (`vbDraftHover` where the page sees no pointer), both following
/// the page as it scrolls or changes size.
const _draftScript = r'''
(function () {
  function send(name, args, message) {
    var host = window.flutter_inappwebview;
    if (host && host.callHandler) { host.callHandler.apply(host, [name].concat(args)); return; }
    if (window.parent && window.parent !== window) {
      message.nonce = window.vbDraftNonce || null;
      window.parent.postMessage(message, '*');
    }
  }
  var ICONS = {"up":"M12.984 18.984L12.984 7.828L17.859 12.703C18.281 13.078 18.891 13.078 19.312 12.703C19.688 12.328 19.688 11.672 19.312 11.297L12.703 4.688C12.328 4.312 11.672 4.312 11.297 4.688L4.688 11.297C4.312 11.672 4.312 12.328 4.688 12.703C5.109 13.078 5.719 13.078 6.094 12.703L11.016 7.828L11.016 18.984C11.016 19.547 11.438 20.016 12 20.016C12.562 20.016 12.984 19.547 12.984 18.984z","down":"M11.016 5.016L11.016 16.172L6.141 11.297C5.719 10.922 5.109 10.922 4.688 11.297C4.312 11.672 4.312 12.328 4.688 12.703L11.297 19.312C11.672 19.688 12.328 19.688 12.703 19.312L19.312 12.703C19.688 12.328 19.688 11.672 19.312 11.297C18.891 10.922 18.281 10.922 17.859 11.297L12.984 16.172L12.984 5.016C12.984 4.453 12.562 3.984 12 3.984C11.438 3.984 11.016 4.453 11.016 5.016z","show":"M12 6C15.797 6 19.172 8.109 20.812 11.484C19.172 14.859 15.797 17.016 12 17.016C8.203 17.016 4.828 14.859 3.188 11.484C4.828 8.109 8.203 6 12 6zM12 3.984C6.984 3.984 2.719 7.125 0.984 11.484C2.719 15.891 6.984 18.984 12 18.984C17.016 18.984 21.281 15.891 23.016 11.484C21.281 7.125 17.016 3.984 12 3.984zM12 9C13.359 9 14.484 10.125 14.484 11.484C14.484 12.891 13.359 14.016 12 14.016C10.641 14.016 9.516 12.891 9.516 11.484C9.516 10.125 10.641 9 12 9zM12 6.984C9.516 6.984 7.5 9 7.5 11.484C7.5 13.969 9.516 15.984 12 15.984C14.484 15.984 16.5 13.969 16.5 11.484C16.5 9 14.484 6.984 12 6.984z","hide":"M12 6C15.797 6 19.172 8.109 20.812 11.484C20.25 12.703 19.406 13.781 18.422 14.625L19.828 16.031C21.188 14.812 22.312 13.266 23.016 11.484C21.281 7.125 17.016 3.984 12 3.984C10.734 3.984 9.516 4.219 8.344 4.547L10.031 6.234C10.641 6.094 11.297 6 12 6zM10.922 7.125L12.984 9.188C13.547 9.469 14.016 9.938 14.297 10.5L16.359 12.562C16.453 12.234 16.5 11.859 16.5 11.484C16.5 9 14.484 6.984 12 6.984C11.625 6.984 11.297 7.031 10.922 7.125zM2.016 3.891L4.688 6.562C3.047 7.828 1.781 9.516 0.984 11.484C2.719 15.891 6.984 18.984 12 18.984C13.5 18.984 15 18.703 16.312 18.188L19.734 21.609L21.141 20.203L3.422 2.438L2.016 3.891zM9.516 11.391L12.141 13.969C12.094 13.969 12.047 14.016 12 14.016C10.641 14.016 9.516 12.891 9.516 11.484C9.516 11.438 9.516 11.438 9.516 11.391zM6.094 7.969L7.875 9.703C7.641 10.266 7.5 10.875 7.5 11.484C7.5 13.969 9.516 15.984 12 15.984C12.609 15.984 13.219 15.891 13.781 15.656L14.766 16.641C13.875 16.875 12.938 17.016 12 17.016C8.203 17.016 4.828 14.859 3.188 11.484C3.891 10.078 4.922 8.906 6.094 7.969z","duplicate":"M18 2.016L9 2.016C7.922 2.016 6.984 2.906 6.984 3.984L6.984 15.984C6.984 17.109 7.922 18 9 18L18 18C19.078 18 20.016 17.109 20.016 15.984L20.016 3.984C20.016 2.906 19.078 2.016 18 2.016zM18 15.984L9 15.984L9 3.984L18 3.984L18 15.984zM3 15L3 12.984L5.016 12.984L5.016 15L3 15zM3 9.516L5.016 9.516L5.016 11.484L3 11.484L3 9.516zM9.984 20.016L12 20.016L12 21.984L9.984 21.984L9.984 20.016zM3 18.516L3 16.5L5.016 16.5L5.016 18.516L3 18.516zM5.016 21.984C3.891 21.984 3 21.094 3 20.016L5.016 20.016L5.016 21.984zM8.484 21.984L6.516 21.984L6.516 20.016L8.484 20.016L8.484 21.984zM13.5 21.984L13.5 20.016L15.516 20.016C15.516 21.094 14.578 21.984 13.5 21.984zM5.016 6L5.016 8.016L3 8.016C3 6.891 3.891 6 5.016 6z","copy":"M15 20.016L5.016 20.016L5.016 6.984C5.016 6.469 4.547 6 3.984 6C3.469 6 3 6.469 3 6.984L3 20.016C3 21.094 3.891 21.984 5.016 21.984L15 21.984C15.562 21.984 15.984 21.562 15.984 21C15.984 20.438 15.562 20.016 15 20.016zM20.016 15.984L20.016 3.984C20.016 2.906 19.078 2.016 18 2.016L9 2.016C7.922 2.016 6.984 2.906 6.984 3.984L6.984 15.984C6.984 17.109 7.922 18 9 18L18 18C19.078 18 20.016 17.109 20.016 15.984zM18 15.984L9 15.984L9 3.984L18 3.984L18 15.984z","remove":"M6 18.984C6 20.109 6.891 21 8.016 21L15.984 21C17.109 21 18 20.109 18 18.984L18 9C18 7.922 17.109 6.984 15.984 6.984L8.016 6.984C6.891 6.984 6 7.922 6 9L6 18.984zM9 9L15 9C15.562 9 15.984 9.469 15.984 9.984L15.984 18C15.984 18.562 15.562 18.984 15 18.984L9 18.984C8.438 18.984 8.016 18.562 8.016 18L8.016 9.984C8.016 9.469 8.438 9 9 9zM15.516 3.984L14.812 3.281C14.625 3.094 14.344 3 14.109 3L9.891 3C9.656 3 9.375 3.094 9.188 3.281L8.484 3.984L6 3.984C5.438 3.984 5.016 4.453 5.016 5.016C5.016 5.531 5.438 6 6 6L18 6C18.562 6 18.984 5.531 18.984 5.016C18.984 4.453 18.562 3.984 18 3.984L15.516 3.984z"};
  // The bar of the picked block, as the canvas draws it (`BlockActionBar`):
  // the editor says which buttons apply and in which colours.
  function drawBar() {
    var old = pick.el.querySelector('.vb-bar');
    if (old) old.remove();
    pick.el.classList.remove('vb-has-bar');
    var b = meta && meta.bar;
    if (!b || !pick.target) return;
    var bar = document.createElement('div');
    bar.className = 'vb-bar';
    bar.setAttribute('role', 'toolbar');
    bar.style.background = meta.fill || '#d3e3fd';
    bar.style.color = meta.onFill || '#041e49';
    var name = document.createElement('b');
    name.textContent = pick.target.getAttribute('data-block-label') || '';
    bar.appendChild(name);
    function button(action, title, icon, danger) {
      var x = document.createElement('button');
      x.type = 'button';
      x.title = title;
      x.setAttribute('aria-label', title);
      x.setAttribute('data-action', action);
      x.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + ICONS[icon] + '"/></svg>';
      if (danger) x.style.color = meta.danger || '#b3261e';
      bar.appendChild(x);
    }
    if (!b.first) button('up', 'Subir', 'up');
    if (!b.last) button('down', 'Bajar', 'down');
    button('visibility', b.visible ? 'Ocultar' : 'Mostrar', b.visible ? 'show' : 'hide');
    button('duplicate', 'Duplicar', 'duplicate');
    if (b.copy) button('copy', 'Copiar para otra página', 'copy');
    button('delete', 'Eliminar', 'remove', true);
    pick.el.appendChild(bar);
    pick.el.classList.add('vb-has-bar');
  }
  var meta = null;
  function tell(id) {
    send('vbDraftPick', [id], { type: 'vb-draft-pick', id: id });
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
    var bar = m.el.querySelector('.vb-bar');
    if (bar) {
      // In sight while the block is: below the header that stays on top
      // (sticky, or fixed over the home's first block), inside the block.
      var header = document.querySelector('header.top');
      var position = header ? getComputedStyle(header).position : '';
      var cover = position === 'sticky' || position === 'fixed'
        ? Math.max(0, header.getBoundingClientRect().bottom) : 0;
      var top = Math.max(8, cover - r.top + 8);
      bar.style.top = Math.min(top, Math.max(8, r.height - 42)) + 'px';
    }
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
    var act = event.target.closest && event.target.closest('.vb-bar [data-action]');
    if (act) {
      var id = pick.target && pick.target.getAttribute('data-block-id');
      var action = act.getAttribute('data-action');
      if (id) send('vbDraftAction', [id, action], { type: 'vb-draft-action', id: id, action: action });
      return;
    }
    if (event.target.closest && event.target.closest('.vb-mark')) return;
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
  // The desktop editor's native view gets no pointer moves: the editor
  // tells where its pointer is, as fractions of the window (-1: gone).
  window.vbDraftHover = function (fx, fy) {
    hover.target = fx < 0 ? null
      : part(document.elementFromPoint(fx * innerWidth, fy * innerHeight));
    soon();
  };
  window.vbDraftPicked = function (id, info) {
    pickedId = id || null;
    meta = info || null;
    pick.target = null;
    if (pickedId) {
      [].some.call(document.querySelectorAll('[data-block-id]'), function (el) {
        if (el.getAttribute('data-block-id') !== pickedId) return false;
        pick.target = el;
        return true;
      });
    }
    drawBar();
    refresh();
  };
})();
''';
