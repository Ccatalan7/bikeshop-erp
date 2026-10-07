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
.vb-mark.vb-writing>span{display:block}
.vb-mark.vb-writing .vb-bar{display:none}
.vb-text-hot{outline:1px dashed rgb(26 115 232 / .7);outline-offset:3px;cursor:text}
.vb-button-hot{outline:1px dashed rgb(26 115 232 / .7);outline-offset:3px;cursor:pointer}
.vb-mark.vb-layer{border:2px solid #1a73e8;border-radius:0}
.vb-mark.vb-layer span{display:none}
.vb-grip{position:absolute;right:-7px;bottom:-7px;width:12px;height:12px;box-sizing:border-box;border-radius:3px;
  background:#fff;border:2px solid #1a73e8;pointer-events:auto;cursor:nwse-resize}
.vb-editing{outline:2px solid #1a73e8;outline-offset:3px;cursor:text;text-transform:none!important;
  -webkit-user-select:text;user-select:text;caret-color:currentColor}
.vb-editing:focus{outline:2px solid #1a73e8}
.vb-bar{position:absolute;right:8px;top:8px;display:flex;align-items:center;gap:2px;padding:2px 4px 2px 10px;
  border-radius:10px;box-shadow:0 2px 6px rgb(0 0 0 / .3);pointer-events:auto;
  font:700 12px/1 system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-bar{max-width:calc(100% - 16px);box-sizing:border-box}
.vb-bar b{margin-right:6px;min-width:0;overflow:hidden;text-overflow:ellipsis}
.vb-bar b[data-grip]{cursor:grab;user-select:none}
.vb-bar b[data-grip]::before{content:"⠿";margin-right:6px;opacity:.6;font-weight:400}
.vb-drop{position:fixed;z-index:2147483647;height:4px;margin-top:-2px;border-radius:2px;pointer-events:none;display:none}
.vb-drop::before,.vb-drop::after{content:"";position:absolute;top:-4px;width:12px;height:12px;border-radius:50%;background:inherit}
.vb-drop::before{left:-6px}.vb-drop::after{right:-6px}
.vb-ghost{position:fixed;z-index:2147483647;pointer-events:none;padding:6px 10px;border-radius:8px;display:none;
  box-shadow:0 4px 12px rgb(0 0 0 / .3);font:700 12px/1 system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-moving,.vb-moving *{cursor:grabbing!important;user-select:none!important}
.vb-guide{position:fixed;z-index:2147483646;pointer-events:none;display:none;opacity:.8}
.vb-guide-x{width:1px;margin-left:-.5px}.vb-guide-y{height:1px;margin-top:-.5px}
.vb-bar button{flex:none}
.vb-bar button{all:unset;display:grid;place-items:center;width:30px;height:30px;border-radius:8px;cursor:pointer}
.vb-bar button:hover,.vb-bar button:focus-visible{background:rgb(0 0 0 / .1)}
.vb-bar svg{width:18px;height:18px;fill:currentColor}
.vb-add{all:unset;position:absolute;left:50%;top:0;transform:translate(-50%,-50%);display:flex;align-items:center;gap:6px;
  height:26px;padding:0 12px 0 4px;border-radius:999px;box-shadow:0 1px 4px rgb(0 0 0 / .3);pointer-events:auto;cursor:pointer;
  font:600 11px/1 system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-add.vb-after{top:100%}
.vb-add i{display:grid;place-items:center;width:18px;height:18px;border-radius:50%;font:700 14px/1 system-ui,sans-serif;font-style:normal}
.vb-add:hover,.vb-add:focus-visible{filter:brightness(1.08);outline:2px solid rgb(255 255 255 / .6)}
.vb-mark.vb-writing .vb-add{display:none}
.vb-size{position:absolute;left:8px;bottom:8px;display:flex;align-items:center;gap:4px;height:24px;padding:0 10px;
  border-radius:8px;box-shadow:0 1px 4px rgb(0 0 0 / .3);pointer-events:auto;cursor:ns-resize;user-select:none;
  font:700 11px/1 system-ui,-apple-system,sans-serif;white-space:nowrap;font-variant-numeric:tabular-nums}
.vb-mark.vb-writing .vb-size{display:none}
.vb-fmt{position:absolute;display:none;align-items:center;gap:2px;padding:2px 4px;border-radius:10px;
  box-shadow:0 2px 6px rgb(0 0 0 / .3);pointer-events:auto;font:700 13px/1 system-ui,-apple-system,sans-serif;white-space:nowrap}
.vb-mark.vb-writing .vb-fmt{display:flex}
.vb-fmt button{all:unset;display:grid;place-items:center;min-width:30px;height:30px;padding:0 4px;box-sizing:border-box;
  border-radius:8px;cursor:pointer;font:inherit}
.vb-fmt button:hover,.vb-fmt button:focus-visible{background:rgb(0 0 0 / .1)}
.vb-fmt button[aria-pressed="true"]{background:rgb(0 0 0 / .16)}
.vb-fmt output{min-width:28px;text-align:center;font-weight:600;font-variant-numeric:tabular-nums}
.vb-fmt i{width:1px;height:18px;margin:0 4px;background:currentColor;opacity:.3}
.vb-sizing,.vb-sizing *{cursor:ns-resize!important;user-select:none!important}
.draft-missing{display:grid;place-items:center;gap:4px;min-height:160px;margin:0;padding:24px;
  border:1px dashed #9aa0a6;border-radius:8px;background:repeating-linear-gradient(135deg,#f8f9fa 0 12px,#f1f3f4 12px 24px);
  color:#5f6368;font:400 14px/1.4 var(--body,system-ui);text-align:center}
.draft-missing p{margin:0;max-width:52ch}
.draft-missing-t{font-weight:700;color:#3c4043}
''';

/// A click picks the part under it and goes nowhere: the editor hears it
/// through the web view's handler (`vbDraftPick`) or, in the ERP on the
/// web, a message to the page that holds the frame. The editor marks its
/// selection with `vbDraftPicked(id, info, show)`: `info.bar` says which of
/// the block bar's buttons apply (a press, or one of the seams' «Agregar
/// aquí», goes back as `vbDraftAction`), and `show` brings a selection made
/// outside the page into sight. The pointer's part is marked as it passes
/// (`vbDraftHover` where the page sees no pointer), both following the page
/// as it scrolls or changes size.
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
    [].forEach.call(pick.el.querySelectorAll('.vb-bar,.vb-add,.vb-size'), function (old) { old.remove(); });
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
    // A block of the page moves by dragging its name.
    if (pick.target.classList.contains('blk')) {
      name.setAttribute('data-grip', '');
      name.title = 'Arrastra para mover el bloque';
      name.addEventListener('mousedown', startMoving);
    }
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
    // The height handle, for a block whose height is authored.
    if (meta.height) {
      var size = document.createElement('div');
      size.className = 'vb-size';
      size.setAttribute('role', 'slider');
      size.setAttribute('aria-label', 'Alto del bloque (doble clic: automático)');
      size.title = 'Arrastra para cambiar el alto; doble clic lo vuelve automático';
      size.style.background = meta.fill || '#d3e3fd';
      size.style.color = meta.onFill || '#041e49';
      size.textContent = '↕ ' + Math.round(pick.target.getBoundingClientRect().height) + ' px';
      size.addEventListener('mousedown', startSizing);
      size.addEventListener('dblclick', function (event) {
        event.preventDefault();
        var id = pick.target && pick.target.getAttribute('data-block-id');
        if (id) send('vbDraftHeight', [id, 'reset', null], { type: 'vb-draft-height', id: id, phase: 'reset' });
      });
      pick.el.appendChild(size);
    }
    // «Agregar aquí» on the block's two seams, as the canvas's markers.
    ['before', 'after'].forEach(function (side) {
      var add = document.createElement('button');
      add.type = 'button';
      add.className = 'vb-add vb-' + side;
      add.setAttribute('data-action', 'insert-' + side);
      add.setAttribute('aria-label', side === 'before' ? 'Agregar una sección arriba' : 'Agregar una sección abajo');
      add.style.background = meta.accent || '#0b57d0';
      add.style.color = meta.onAccent || '#fff';
      var plus = document.createElement('i');
      plus.textContent = '+';
      plus.style.background = meta.onAccent || '#fff';
      plus.style.color = meta.accent || '#0b57d0';
      add.appendChild(plus);
      add.appendChild(document.createTextNode('Agregar aquí'));
      pick.el.appendChild(add);
    });
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
  // The canvas layer picked in the panel (`info.layer` of vbDraftPicked:
  // its slide, or -1 for a canvas block's own, and its id), marked where it
  // shows.
  var layerPick = mark(true), layerSel = null;
  layerPick.el.classList.add('vb-layer');
  var layerGrip = document.createElement('i');
  layerGrip.className = 'vb-grip';
  layerGrip.title = 'Arrastra para cambiar el tamaño';
  layerPick.el.appendChild(layerGrip);
  function shownLayer() {
    if (!layerSel || !pick.target) return null;
    var slide = layerSel.slide < 0 ? 'root' : String(layerSel.slide);
    var found = null;
    [].some.call(pick.target.querySelectorAll('[data-canvas-slide]'), function (c) {
      if (c.getAttribute('data-canvas-slide') !== slide) return false;
      [].some.call(c.querySelectorAll('[data-layer]'), function (el) {
        if (el.getAttribute('data-layer') !== layerSel.id || !el.getClientRects().length) return false;
        found = el;
        return true;
      });
      return !!found;
    });
    return found;
  }
  function place(m) {
    var t = m.target;
    if (!t || !t.isConnected) { m.el.classList.remove('vb-on'); return; }
    var r = t.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) { m.el.classList.remove('vb-on'); return; }
    var s = m.el.style;
    s.left = r.left + 'px'; s.top = r.top + 'px';
    s.width = r.width + 'px'; s.height = r.height + 'px';
    m.el.firstChild.textContent = m === pick && edit && edit.on ? HINT
      : t.getAttribute('data-block-label') || '';
    m.el.firstChild.style.display = m.el.firstChild.textContent ? '' : 'none';
    m.el.classList.toggle('vb-inside', r.top < 24);
    m.el.classList.add('vb-on');
    var tools = m.el.querySelector('.vb-fmt');
    if (tools && edit && edit.on) {
      // Above the text being written, or below it when the header (or the
      // block's top) leaves no room.
      var t = edit.el.getBoundingClientRect();
      var room = Math.max(0, cover() - r.top) + 4;
      var y = t.top - r.top - 40;
      if (y < room) y = t.bottom - r.top + 8;
      tools.style.top = y + 'px';
      tools.style.left = Math.max(4, Math.min(t.left - r.left, r.width - tools.offsetWidth - 4)) + 'px';
    }
    var bar = m.el.querySelector('.vb-bar');
    if (bar) {
      // In sight while the block is: below the header that stays on top
      // (sticky, or fixed over the home's first block), inside the block,
      // and under the «Agregar aquí» of its upper seam.
      var hidden = Math.max(0, cover() - r.top);
      var add = m.el.querySelector('.vb-add.vb-before');
      if (add) add.style.top = (hidden ? hidden + 18 : 0) + 'px';
      var top = hidden ? hidden + 40 : 22;
      bar.style.top = Math.min(top, Math.max(8, r.height - 52)) + 'px';
    }
  }
  // How much of the window the header that stays on top (sticky, or fixed
  // over the home's first block) covers.
  function cover() {
    var header = document.querySelector('header.top');
    var position = header ? getComputedStyle(header).position : '';
    return position === 'sticky' || position === 'fixed'
      ? Math.max(0, header.getBoundingClientRect().bottom) : 0;
  }
  // A part picked from the panel (or just added) out of sight comes under
  // the header, as the canvas scrolls to its selection.
  function bring(el) {
    var r = el.getBoundingClientRect(), top = cover();
    if (r.bottom > top + 48 && r.top < innerHeight - 48) return;
    window.scrollBy({ top: r.top - top - 24, behavior: 'smooth' });
  }
  function part(node) {
    return node && node.closest ? node.closest('[data-block-id]') : null;
  }
  // The part drawn with [id]: a block drawn once per band (a phone copy
  // and a wide one, `data-bands`) is marked where it shows.
  function shown(id) {
    var first = null, seen = null;
    [].some.call(document.querySelectorAll('[data-block-id]'), function (el) {
      if (el.getAttribute('data-block-id') !== id) return false;
      first = first || el;
      if (el.getClientRects().length) seen = el;
      return !!seen;
    });
    return seen || first;
  }
  function refresh() {
    // The window changed band: the picked part shows in its other copy.
    if (pickedId && !edit && pick.target && !pick.target.getClientRects().length) {
      var other = shown(pickedId);
      if (other !== pick.target) { pick.target = other; drawBar(); }
    }
    place(pick);
    layerPick.target = edit ? null : shownLayer();
    place(layerPick);
    if (hover.target && hover.target === pick.target) hover.el.classList.remove('vb-on');
    else place(hover);
  }
  var queued = false;
  function soon() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; refresh(); });
  }
  // The click that ends a drag (a move, a height) picks nothing.
  var dragged = 0;
  document.addEventListener('click', function (event) {
    if (Date.now() - dragged < 500) {
      dragged = 0;
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    // The picked carousel's arrows and dots move it, as on the store.
    var turn = event.target.closest &&
      event.target.closest('[data-car-prev],[data-car-next],[data-car-go]');
    if (turn && pick.target && part(turn) === pick.target && !edit) return;
    event.preventDefault();
    event.stopPropagation();
    // Inside the text being written (or the key press a summary turns into
    // a click): the caret moves, nothing is picked.
    if (edit && (edit.el.contains(event.target) ||
        (event.target.tagName === 'SUMMARY' && event.target.contains(edit.el)))) return;
    var format = event.target.closest && event.target.closest('.vb-fmt [data-fmt]');
    if (format) { applyFormatting(format.getAttribute('data-fmt')); return; }
    var act = event.target.closest && event.target.closest('.vb-bar [data-action],.vb-add');
    if (act) {
      var id = pick.target && pick.target.getAttribute('data-block-id');
      var action = act.getAttribute('data-action');
      if (id) send('vbDraftAction', [id, action], { type: 'vb-draft-action', id: id, action: action });
      return;
    }
    if (event.target.closest && event.target.closest('.vb-mark')) return;
    var pressed = edit ? null : pressable(event.target);
    if (pressed) { askButton(pressed); return; }
    var text = editable(event.target);
    if (text && !edit) { begin(text); return; }
    var layer = edit ? null : layerOf(event.target);
    if (layer) { askLayer(layer); return; }
    var photo = edit ? null : photoOf(event.target);
    if (photo) { askPhoto(photo); return; }
    var found = part(event.target);
    // A question of the picked block opens and closes, as on the store.
    var question = event.target.closest && event.target.closest('summary');
    if (question && found && found === pick.target && question.parentElement) {
      question.parentElement.open = !question.parentElement.open;
      soon();
    }
    tell(found ? found.getAttribute('data-block-id') : null);
  }, true);
  document.addEventListener('submit', function (event) { event.preventDefault(); }, true);
  document.addEventListener('mouseover', function (event) {
    hover.target = part(event.target);
    heat(event.target);
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
    var node = fx < 0 ? null : document.elementFromPoint(fx * innerWidth, fy * innerHeight);
    hover.target = part(node);
    heat(node);
    soon();
  };
  // Writing a text where it is drawn (`data-edit-text`): a click on a text
  // of the picked block asks the editor (`vbDraftEdit … 'begin'`), which
  // answers with the text as the draft holds it (`vbDraftEditing`, or null
  // to refuse); leaving it (a click elsewhere, ⌘/Ctrl+Enter) writes it
  // (`'commit'`), Escape leaves it as it was (`'cancel'`). The text written
  // stays until the editor redraws the page, or goes back if the editor
  // refuses it (`vbDraftEdited(false)`).
  var edit = null, written = null, hot = null;
  var HINT = 'Escribiendo · ' + (/Mac|iP/.test(navigator.platform) ? '⌘↵' : 'Ctrl+↵') +
    ' listo · Esc cancela';
  function editable(node) {
    var text = node && node.closest ? node.closest('[data-edit-text]') : null;
    return text && pick.target && part(text) === pick.target ? text : null;
  }
  // A button of the picked block (`data-edit-button`): a click on it asks
  // the editor to open its label, destination and look
  // (`vbDraftButton(id, spec, where)`, where = the button's box as
  // fractions of the page's window, for the editor to place its card).
  function pressable(node) {
    var b = node && node.closest ? node.closest('[data-edit-button]') : null;
    return b && pick.target && part(b) === pick.target ? b : null;
  }
  // A layer of the picked block's canvas (a composed slide, a canvas
  // block): a click picks it in the panel, as on the Flutter canvas
  // (`vbDraftLayer(id, slide, layer)`, slide -1 for a canvas block's own).
  function layerOf(node) {
    var l = node && node.closest ? node.closest('[data-layer]') : null;
    return l && pick.target && part(l) === pick.target ? l : null;
  }
  function askLayer(l) {
    var id = pick.target.getAttribute('data-block-id');
    var holder = l.closest('[data-canvas-slide]');
    var raw = holder ? holder.getAttribute('data-canvas-slide') : 'root';
    var slide = raw === 'root' ? -1 : +raw;
    var layer = l.getAttribute('data-layer');
    send('vbDraftLayer', [id, slide, layer],
      { type: 'vb-draft-layer', id: id, slide: slide, layer: layer });
  }
  // A photo of the picked block (`data-edit-image`): a click opens the
  // editor's image picker for it (`vbDraftImage(id, spec)`), as the Flutter
  // canvas's media slot.
  function photoOf(node) {
    var f = node && node.closest ? node.closest('[data-edit-image]') : null;
    return f && pick.target && part(f) === pick.target ? f : null;
  }
  function askPhoto(f) {
    var id = pick.target.getAttribute('data-block-id');
    var spec = f.getAttribute('data-edit-image');
    send('vbDraftImage', [id, spec], { type: 'vb-draft-image', id: id, image: spec });
  }
  function heat(node) {
    var target = edit ? null : (pressable(node) || editable(node) || layerOf(node) || photoOf(node));
    if (target === hot) return;
    if (hot) hot.classList.remove('vb-text-hot', 'vb-button-hot');
    hot = target;
    if (hot) hot.classList.add(hot.hasAttribute('data-edit-text') ? 'vb-text-hot' : 'vb-button-hot');
  }
  function askButton(b) {
    var id = pick.target.getAttribute('data-block-id');
    var spec = b.getAttribute('data-edit-button');
    var r = b.getBoundingClientRect();
    var where = [r.left / innerWidth, r.top / innerHeight, r.width / innerWidth, r.height / innerHeight];
    send('vbDraftButton', [id, spec, where],
      { type: 'vb-draft-button', id: id, button: spec, where: where });
  }
  // Each edit carries its own token, and an answer for another one (late,
  // or for the page before a redraw) is ignored.
  var editSeq = 0;
  function editMessage(e, phase, text, formatting) {
    send('vbDraftEdit', [e.id, e.field, phase, text === undefined ? null : text, e.token, formatting || null],
      { type: 'vb-draft-edit', id: e.id, field: e.field, phase: phase, text: text, token: e.token,
        formatting: formatting || null });
  }
  // The text as it was drawn, its look included.
  function putBack(e) {
    e.el.innerHTML = e.html;
    if (e.style === null || e.style === undefined) e.el.removeAttribute('style');
    else e.el.setAttribute('style', e.style);
  }
  // The text's toolbar while it is written, for a text with a formatting
  // (`vbDraftEditing`'s fourth argument): bold, italic, underline and the
  // size, seen at once on the text and sent with it as changes.
  function fmtValue(key) {
    return key in edit.changes ? edit.changes[key] : edit.fmt[key];
  }
  function fmtSize() {
    return fmtValue('fontSize') || Math.round(parseFloat(getComputedStyle(edit.el).fontSize)) || 16;
  }
  function drawFormatting() {
    var old = pick.el.querySelector('.vb-fmt');
    if (old) old.remove();
    if (!edit || !edit.fmt) return;
    var bar = document.createElement('div');
    bar.className = 'vb-fmt';
    bar.setAttribute('role', 'toolbar');
    bar.setAttribute('aria-label', 'Formato del texto');
    bar.style.background = (meta && meta.fill) || '#d3e3fd';
    bar.style.color = (meta && meta.onFill) || '#041e49';
    function button(name, label, title, css) {
      var b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('data-fmt', name);
      b.title = title;
      b.setAttribute('aria-label', title);
      b.textContent = label;
      if (css) b.style.cssText = css;
      bar.appendChild(b);
      return b;
    }
    button('bold', 'B', 'Negrita (⌘B)', 'font-weight:800');
    button('italic', 'I', 'Cursiva (⌘I)', 'font-style:italic;font-family:Georgia,serif');
    button('underline', 'U', 'Subrayado (⌘U)', 'text-decoration:underline');
    bar.appendChild(document.createElement('i'));
    button('smaller', 'A−', 'Más chico');
    bar.appendChild(document.createElement('output'));
    button('larger', 'A+', 'Más grande');
    pick.el.appendChild(bar);
    showFormatting();
  }
  function showFormatting() {
    var bar = pick.el.querySelector('.vb-fmt');
    if (!bar || !edit) return;
    ['bold', 'italic', 'underline'].forEach(function (key) {
      bar.querySelector('[data-fmt="' + key + '"]').setAttribute('aria-pressed', fmtValue(key) === true ? 'true' : 'false');
    });
    bar.querySelector('output').textContent = fmtSize();
  }
  function applyFormatting(name) {
    if (!edit || !edit.on || !edit.fmt) return;
    var st = edit.el.style;
    if (name === 'bold' || name === 'italic' || name === 'underline') {
      var on = fmtValue(name) !== true;
      edit.changes[name] = on;
      if (name === 'bold') st.fontWeight = on ? '700' : '400';
      if (name === 'italic') st.fontStyle = on ? 'italic' : 'normal';
      if (name === 'underline') st.textDecoration = on ? 'underline' : 'none';
    } else {
      var size = Math.max(8, Math.min(120, fmtSize() + (name === 'larger' ? 2 : -2)));
      edit.changes.fontSize = size;
      st.fontSize = size + 'px';
      st.lineHeight = '1.2';
    }
    showFormatting();
    soon();
  }
  function begin(el) {
    heat(null);
    written = null;
    edit = {
      el: el, id: pick.target.getAttribute('data-block-id'),
      field: el.getAttribute('data-edit-text'), html: el.innerHTML, on: false,
      token: Date.now().toString(36) + '.' + (++editSeq)
    };
    editMessage(edit, 'begin');
  }
  window.vbDraftEditing = function (raw, field, token, formatting) {
    if (!edit || edit.on || token !== edit.token) return;
    if (raw === null || raw === undefined || field !== edit.field) { edit = null; return; }
    var el = edit.el;
    edit.on = true;
    edit.raw = raw;
    edit.style = el.getAttribute('style');
    edit.fmt = formatting || null;
    edit.changes = {};
    drawFormatting();
    el.classList.add('vb-editing');
    el.textContent = raw;
    el.setAttribute('contenteditable', 'plaintext-only');
    if (el.contentEditable !== 'plaintext-only') el.setAttribute('contenteditable', 'true');
    el.setAttribute('spellcheck', 'true');
    el.focus();
    var range = document.createRange();
    range.selectNodeContents(el);
    var selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    pick.el.classList.add('vb-writing');
    refresh();
  };
  function done(keep) {
    var e = edit;
    if (!e) return;
    // First: leaving the element (below) takes its focus, and the focusout
    // that follows must not end the edit a second time.
    edit = null;
    if (!e.on) { editMessage(e, 'cancel'); return; }
    var text = e.el.innerText;
    if (text.slice(-1) === '\n' && e.raw.slice(-1) !== '\n') text = text.slice(0, -1);
    e.el.removeAttribute('contenteditable');
    e.el.removeAttribute('spellcheck');
    e.el.classList.remove('vb-editing');
    pick.el.classList.remove('vb-writing');
    var formatted = Object.keys(e.changes || {}).length > 0;
    if (keep && (text !== e.raw || formatted)) {
      editMessage(e, 'commit', text, formatted ? e.changes : null);
      written = e;
    } else {
      editMessage(e, 'cancel');
      putBack(e);
    }
    soon();
  }
  window.vbDraftEdited = function (ok, token) {
    if (!written || written.token !== token) return;
    if (!ok) putBack(written);
    written = null;
  };
  // A press on the toolbar keeps the text being written in focus.
  document.addEventListener('mousedown', function (event) {
    if (event.target.closest && event.target.closest('.vb-fmt')) event.preventDefault();
  }, true);
  // The text being written and its toolbar are one session: focus moving
  // between them keeps it; leaving both ends it (written).
  function inSession(node) {
    return !!(node && edit && edit.on &&
      (edit.el.contains(node) || (node.closest && node.closest('.vb-fmt'))));
  }
  document.addEventListener('focusout', function (event) {
    if (inSession(event.target) && !inSession(event.relatedTarget)) done(true);
  }, true);
  document.addEventListener('keydown', function (event) {
    if (!inSession(event.target)) return;
    event.stopPropagation();
    var shortcut = (event.metaKey || event.ctrlKey) &&
      { b: 'bold', i: 'italic', u: 'underline' }[event.key.toLowerCase()];
    if (shortcut) { event.preventDefault(); applyFormatting(shortcut); return; }
    if (event.key === 'Escape') { event.preventDefault(); done(false); return; }
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) { event.preventDefault(); done(true); return; }
    // Tab goes from the text to its toolbar and around it, back to the text.
    if (event.key === 'Tab') {
      var buttons = [].slice.call(pick.el.querySelectorAll('.vb-fmt button'));
      if (!buttons.length) return;
      var stops = [edit.el].concat(buttons);
      var at = stops.indexOf(event.target);
      if (at < 0) at = 0;
      event.preventDefault();
      stops[(at + (event.shiftKey ? stops.length - 1 : 1)) % stops.length].focus();
    }
  }, true);
  // The carousels show the slide picked in the editor's panel, as on the
  // canvas (`vbDraftSlides({blockId: index}, instant)`; instant when the
  // page has just been drawn), and a turn of one with its arrows or dots
  // picks that slide in the panel (`vbDraftSlide`).
  var slides = {};
  window.vbDraftSlides = function (wanted, instant) {
    slides = wanted || {};
    [].forEach.call(document.querySelectorAll('[data-block-id]'), function (block) {
      var id = block.getAttribute('data-block-id');
      if (!(id in slides)) return;
      [].forEach.call(block.querySelectorAll('[data-car]'), function (c) {
        var on = c.querySelector(':scope>.car-slide.on');
        if (on && +on.getAttribute('data-slide') === slides[id]) return;
        if (instant) {
          c.vbDur = c.vbDur || c.style.getPropertyValue('--car-dur');
          c.style.setProperty('--car-dur', '0ms');
        }
        c.dispatchEvent(new CustomEvent('car:go', { detail: slides[id] }));
      });
    });
  };
  document.addEventListener('car:shown', function (event) {
    var c = event.target;
    if (c.vbDur) {
      var dur = c.vbDur;
      c.vbDur = null;
      requestAnimationFrame(function () { c.style.setProperty('--car-dur', dur); });
    }
    soon();
    var block = part(c), id = block && block.getAttribute('data-block-id');
    if (!id || slides[id] === event.detail) return;
    slides[id] = event.detail;
    send('vbDraftSlide', [id, event.detail], { type: 'vb-draft-slide', id: id, index: event.detail });
  });
  // Dragging the height handle: the block takes the height as it goes (the
  // block and, when it sets its own, its first element), snapped to 10 px
  // between the editor's bounds; the editor writes it when the drag ends
  // (`vbDraftHeight` begin / commit / cancel) and the page puts the block
  // back if the write is refused (`vbDraftSized(false)`).
  var sizing = null, sized = null;
  function heightMessage(id, phase, value) {
    send('vbDraftHeight', [id, phase, value === undefined ? null : value],
      { type: 'vb-draft-height', id: id, phase: phase, value: value });
  }
  function restoreSize(s) {
    if (!s) return;
    if (s.style === null) s.el.removeAttribute('style'); else s.el.setAttribute('style', s.style);
    if (s.child) {
      if (s.childStyle === null) s.child.removeAttribute('style'); else s.child.setAttribute('style', s.childStyle);
    }
    soon();
  }
  function startSizing(event) {
    if (event.button !== 0 || !pick.target || !meta || !meta.height || edit) return;
    event.preventDefault();
    event.stopPropagation();
    var el = pick.target, child = el.firstElementChild;
    sizing = {
      id: el.getAttribute('data-block-id'), el: el,
      child: child && child.style.height ? child : null,
      style: el.getAttribute('style'),
      childStyle: child ? child.getAttribute('style') : null,
      y: event.clientY, from: el.getBoundingClientRect().height, to: null
    };
    sizing.to = Math.round(sizing.from);
    sized = null;
    document.documentElement.classList.add('vb-sizing');
  }
  document.addEventListener('mousemove', function (event) {
    if (!sizing) return;
    event.preventDefault();
    var h = sizing.from + event.clientY - sizing.y;
    h = Math.max(meta.height.min, Math.min(meta.height.max, Math.round(h / 10) * 10));
    if (h === sizing.to) return;
    // The editor leases the height at the first step, not at a mere press
    // (a double click asks for the automatic height instead).
    if (!sizing.begun) { sizing.begun = true; heightMessage(sizing.id, 'begin'); }
    sizing.to = h;
    sizing.el.style[meta.height.exact ? 'height' : 'minHeight'] = h + 'px';
    if (sizing.child) sizing.child.style.height = h + 'px';
    var label = pick.el.querySelector('.vb-size');
    if (label) label.textContent = '↕ ' + h + ' px';
    soon();
  }, true);
  function endSizing() {
    if (!sizing) return;
    var s = sizing;
    sizing = null;
    if (s.begun) dragged = Date.now();
    document.documentElement.classList.remove('vb-sizing');
    if (!s.begun) return;
    if (s.to === Math.round(s.from)) { heightMessage(s.id, 'cancel'); restoreSize(s); return; }
    sized = s;
    heightMessage(s.id, 'commit', s.to);
  }
  document.addEventListener('mouseup', endSizing, true);
  // A release the page never sees (outside its frame) ends the drag too.
  addEventListener('blur', endSizing);
  window.vbDraftSized = function (ok) {
    if (ok) { sized = null; return; }
    // Refused at the start (the block cannot be sized now) or at the end.
    var s = sizing || sized;
    if (sizing) { sizing = null; document.documentElement.classList.remove('vb-sizing'); }
    sized = null;
    restoreSize(s);
  };
  // Moving the picked canvas layer (a press inside it and a drag) or
  // resizing it (its corner grip): the layer follows the pointer in the
  // canvas's own units (`--x`/`--y`/`--w`/`--h`) and lands as the canvas
  // lands it (`landing`); the editor writes it when the drag ends, as the
  // canvas's direct manipulation (`vbDraftLayerDrag` begin / commit /
  // cancel), and the page puts it back if the write is refused
  // (`vbDraftLayered(false)`) or Escape lets it go. A press that does not
  // move is a click, which picks as always.
  var shifting = null, shifted = null;
  function layerMessage(m, phase, values) {
    send('vbDraftLayerDrag', [m.id, m.slide, m.layer, phase, m.mode, values || null],
      { type: 'vb-draft-layer-drag', id: m.id, slide: m.slide, layer: m.layer,
        phase: phase, mode: m.mode, values: values || null });
  }
  function unitsOf(el) {
    var st = el.style;
    return {
      x: parseFloat(st.getPropertyValue('--x')) || 0, y: parseFloat(st.getPropertyValue('--y')) || 0,
      w: parseFloat(st.getPropertyValue('--w')) || 0, h: parseFloat(st.getPropertyValue('--h')) || 0
    };
  }
  // How a layer of [set] lands, as `CanvasBlock` lands it: its center, then
  // its near edge, then its far edge pulled to the canvas's edges and middle
  // or to another layer's, within the document's distance in pixels
  // (`data-pull`), a line showing what it lined up with; otherwise to the
  // document's grid (`data-grid`, 0 when snapping is off). Kept inside the
  // canvas, or with a grab of it inside where the document lets layers
  // bleed (`data-bleed`). `null` for a layer the page cannot measure.
  function landing(el) {
    var u = unitsOf(el), set = el.closest('.cnv-set'), cnv = set && set.closest('.cnv');
    if (!(u.w > 0) || !el.offsetWidth || !cnv) return null;
    var s = el.offsetWidth / u.w, r = set.getBoundingClientRect();
    var dw = parseFloat(getComputedStyle(set).getPropertyValue('--dw')) || u.x + u.w;
    var dh = r.height / s;
    var grid = parseFloat(cnv.getAttribute('data-grid')), pull = parseFloat(cnv.getAttribute('data-pull'));
    var z = {
      u: u, s: s, dw: dw, dh: dh, rect: r, ox: r.left + Math.max(0, (r.width - dw * s) / 2),
      grid: grid >= 0 ? grid : 8, reach: (pull >= 0 ? pull : 6) / s,
      bleed: cnv.hasAttribute('data-bleed'),
      button: el.classList.contains('cl-btn') || el.classList.contains('cl-tbtn'),
      xs: [0, dw / 2, dw], ys: [0, dh / 2, dh]
    };
    [].forEach.call(set.querySelectorAll('[data-layer]'), function (other) {
      if (other === el || !other.getClientRects().length) return;
      var o = unitsOf(other);
      z.xs.push(o.x, o.x + o.w / 2, o.x + o.w);
      z.ys.push(o.y, o.y + o.h / 2, o.y + o.h);
    });
    return z;
  }
  // The nearest target within reach of [pos] plus each share of [size]
  // (the center, the near edge, the far edge, in that order on a tie).
  function pulled(pos, size, targets, z, shares) {
    var best = null;
    shares.forEach(function (k) {
      targets.forEach(function (t) {
        var d = Math.abs(pos + k * size - t);
        if (d <= z.reach && (!best || d < best.d)) best = { d: d, at: t - k * size, line: t };
      });
    });
    return best;
  }
  function gridded(v, z) {
    if (!(z.grid > 0)) return v;
    var g = Math.round(v / z.grid) * z.grid;
    return Math.abs(g - v) <= z.reach ? g : v;
  }
  function keptIn(v, size, room, z) {
    if (z.bleed) {
      var grab = Math.min(32, Math.max(12, size));
      return Math.max(grab - size, Math.min(v, room - grab));
    }
    return Math.max(0, Math.min(v, Math.max(0, room - size)));
  }
  var guides = ['x', 'y'].map(function (axis) {
    var el = document.createElement('div');
    el.className = 'vb-guide vb-guide-' + axis;
    document.body.appendChild(el);
    return el;
  });
  // The lines a landing lined up with, in units of [z]; `null` hides one.
  function showGuides(z, lineX, lineY) {
    var color = (meta && meta.accent) || '#1a73e8';
    [[guides[0], lineX], [guides[1], lineY]].forEach(function (g, i) {
      var el = g[0], at = g[1];
      el.style.display = at == null ? 'none' : 'block';
      if (at == null) return;
      el.style.background = color;
      if (i === 0) {
        el.style.left = (z.ox + at * z.s) + 'px';
        el.style.top = z.rect.top + 'px';
        el.style.height = z.rect.height + 'px';
      } else {
        el.style.top = (z.rect.top + at * z.s) + 'px';
        el.style.left = z.rect.left + 'px';
        el.style.width = z.rect.width + 'px';
      }
    });
  }
  function restoreLayer(m) {
    if (!m) return;
    if (m.style === null) m.el.removeAttribute('style'); else m.el.setAttribute('style', m.style);
    soon();
  }
  document.addEventListener('mousedown', function (event) {
    if (event.button !== 0 || edit || sizing || shifting || !layerPick.target || !layerSel) return;
    var el = layerPick.target;
    var grip = !!(event.target.closest && event.target.closest('.vb-grip'));
    var r = el.getBoundingClientRect();
    var inside = event.clientX >= r.left && event.clientX <= r.right &&
      event.clientY >= r.top && event.clientY <= r.bottom;
    if (!grip && !inside) return;
    var z = landing(el);
    if (!z) return;
    // Text and photos would start their own selection or drag.
    event.preventDefault();
    if (grip) event.stopPropagation();
    shifting = {
      id: pick.target.getAttribute('data-block-id'), slide: layerSel.slide, layer: layerSel.id,
      mode: grip ? 'resize' : 'move', el: el, style: el.getAttribute('style'), from: z.u, to: null,
      sx: event.clientX, sy: event.clientY, z: z, lock: null, begun: false
    };
  }, true);
  // Where the drag puts the layer: a place (Shift keeps it on one axis) or
  // a size from the corner (Shift keeps its proportions; the canvas's
  // smallest frame, larger for a button).
  function shiftedTo(m, event) {
    var z = m.z, f = m.from, dx = (event.clientX - m.sx) / z.s, dy = (event.clientY - m.sy) / z.s;
    var lineX = null, lineY = null, to, hit;
    if (m.mode === 'move') {
      if (event.shiftKey) {
        if (!m.lock) m.lock = Math.abs(dx) >= Math.abs(dy) ? 'x' : 'y';
      } else {
        m.lock = null;
      }
      if (m.lock === 'x') dy = 0;
      if (m.lock === 'y') dx = 0;
      var x = f.x + dx, y = f.y + dy;
      hit = m.lock === 'y' ? null : pulled(x, f.w, z.xs, z, [0.5, 0, 1]);
      if (hit) { x = hit.at; lineX = hit.line; } else if (m.lock !== 'y') x = gridded(x, z);
      hit = m.lock === 'x' ? null : pulled(y, f.h, z.ys, z, [0.5, 0, 1]);
      if (hit) { y = hit.at; lineY = hit.line; } else if (m.lock !== 'x') y = gridded(y, z);
      to = { x: Math.round(keptIn(x, f.w, z.dw, z)), y: Math.round(keptIn(y, f.h, z.dh, z)) };
      if (lineX != null && Math.abs(to.x - Math.round(x)) > 0) lineX = null;
      if (lineY != null && Math.abs(to.y - Math.round(y)) > 0) lineY = null;
    } else {
      var minW = z.button ? 120 : 40, minH = z.button ? 44 : 32;
      var right = f.x + f.w + dx, bottom = f.y + f.h + dy, w, h;
      var ratio = f.w / Math.max(f.h, 1);
      var byWidth = !event.shiftKey || Math.abs(dx) >= Math.abs(dy);
      var byHeight = !event.shiftKey || !byWidth;
      if (byWidth) {
        hit = pulled(right, 0, z.xs, z, [0]);
        right = hit ? hit.at : gridded(right, z);
        if (hit) lineX = hit.line;
      }
      if (byHeight) {
        hit = pulled(bottom, 0, z.ys, z, [0]);
        bottom = hit ? hit.at : gridded(bottom, z);
        if (hit) lineY = hit.line;
      }
      w = right - f.x;
      h = bottom - f.y;
      if (event.shiftKey) {
        if (byWidth) h = w / ratio; else w = h * ratio;
      }
      var maxW = z.bleed ? 20000 : Math.max(minW, z.dw - f.x);
      var maxH = z.bleed ? 20000 : Math.max(minH, z.dh - f.y);
      to = {
        w: Math.round(Math.max(minW, Math.min(w, maxW))),
        h: Math.round(Math.max(minH, Math.min(h, maxH)))
      };
      if (lineX != null && to.w !== Math.round(w)) lineX = null;
      if (lineY != null && to.h !== Math.round(h)) lineY = null;
    }
    showGuides(z, lineX, lineY);
    return to;
  }
  document.addEventListener('mousemove', function (event) {
    var m = shifting;
    if (!m) return;
    if (!m.begun) {
      if (Math.abs(event.clientX - m.sx) < 4 && Math.abs(event.clientY - m.sy) < 4) return;
      m.begun = true;
      document.documentElement.classList.add('vb-moving');
      layerMessage(m, 'begin');
    }
    event.preventDefault();
    var to = shiftedTo(m, event);
    m.to = to;
    Object.keys(to).forEach(function (k) { m.el.style.setProperty('--' + k, to[k]); });
    soon();
  }, true);
  function stopShifting() {
    shifting = null;
    showGuides(null, null, null);
    document.documentElement.classList.remove('vb-moving');
  }
  function endShifting() {
    var m = shifting;
    if (!m) return;
    stopShifting();
    if (!m.begun) return;
    dragged = Date.now();
    var to = m.to || {};
    if (Object.keys(to).every(function (k) { return to[k] === m.from[k]; })) {
      layerMessage(m, 'cancel');
      restoreLayer(m);
      return;
    }
    shifted = m;
    layerMessage(m, 'commit', to);
  }
  document.addEventListener('mouseup', endShifting, true);
  addEventListener('blur', endShifting);
  // Escape lets a drag go: the layer goes back where it was.
  function letGo() {
    var m = shifting;
    if (!m) return false;
    stopShifting();
    if (m.begun) {
      dragged = Date.now();
      layerMessage(m, 'cancel');
      restoreLayer(m);
    }
    return true;
  }
  // An arrow nudges the picked layer by one unit (ten with Shift), as on
  // the canvas: each press is a whole move, written as one step.
  function nudge(key, shift) {
    if (edit || shifting || shifted || !layerPick.target || !layerSel) return false;
    var dx = { ArrowLeft: -1, ArrowRight: 1 }[key] || 0;
    var dy = { ArrowUp: -1, ArrowDown: 1 }[key] || 0;
    if (!dx && !dy) return false;
    var el = layerPick.target, z = landing(el);
    if (!z) return false;
    var u = z.u, step = shift ? 10 : 1;
    var to = {
      x: Math.round(keptIn(u.x + dx * step, u.w, z.dw, z)),
      y: Math.round(keptIn(u.y + dy * step, u.h, z.dh, z))
    };
    if (to.x === u.x && to.y === u.y) return true;
    var m = {
      id: pick.target.getAttribute('data-block-id'), slide: layerSel.slide, layer: layerSel.id,
      mode: 'move', el: el, style: el.getAttribute('style'), from: u, to: to
    };
    layerMessage(m, 'begin');
    el.style.setProperty('--x', to.x);
    el.style.setProperty('--y', to.y);
    shifted = m;
    layerMessage(m, 'commit', to);
    soon();
    return true;
  }
  // Delete removes the picked layer and ⌘D (Ctrl+D) duplicates it, as on
  // the canvas: the editor does it (`vbDraftLayerCommand`).
  function layerCommand(command) {
    if (edit || shifting || shifted || !layerPick.target || !layerSel || !pick.target) return false;
    var id = pick.target.getAttribute('data-block-id');
    send('vbDraftLayerCommand', [id, layerSel.slide, layerSel.id, command],
      { type: 'vb-draft-layer-command', id: id, slide: layerSel.slide, layer: layerSel.id,
        command: command });
    return true;
  }
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && shifting) {
      event.preventDefault();
      event.stopPropagation();
      letGo();
      return;
    }
    // Keys typed in a field of the page are the field's.
    var t = event.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    var command = event.metaKey || event.ctrlKey, done = false;
    if (/^Arrow/.test(event.key)) {
      if (!command && !event.altKey) done = nudge(event.key, event.shiftKey);
    } else if ((event.key === 'Delete' || event.key === 'Backspace') && !command) {
      done = layerCommand('remove');
    } else if (command && !event.altKey && (event.key === 'd' || event.key === 'D')) {
      done = layerCommand('duplicate');
    }
    if (done) event.preventDefault();
  }, true);
  // The same keys when the editor holds the keyboard (macOS, where a press
  // in the page does not give it the keys).
  window.vbDraftKey = function (key, shift) {
    if (key === 'Escape') letGo(); else nudge(key, !!shift);
  };
  window.vbDraftLayered = function (ok) {
    if (ok) { shifted = null; return; }
    // Refused at the start (the layer cannot be moved now) or at the end.
    var m = shifting || shifted;
    if (shifting) stopShifting();
    shifted = null;
    restoreLayer(m);
  };
  // Dragging the picked block by its name: a line marks the seam it would
  // land on (between the page's blocks, as they show), the page scrolls near
  // its edges, and the release asks the editor to move it there
  // (`vbDraftMove(id, anchor, side)`), which does the canvas's own move.
  // Escape, or a seam next to the block itself, moves nothing.
  var moving = null;
  function pageBlocks() {
    return [].filter.call(document.querySelectorAll('.blk[data-block-id]'), function (el) {
      return el.getClientRects().length > 0;
    });
  }
  function startMoving(event) {
    if (event.button !== 0 || !pick.target || edit || sizing) return;
    event.preventDefault();
    event.stopPropagation();
    var line = document.createElement('div'), ghost = document.createElement('div');
    line.className = 'vb-drop';
    ghost.className = 'vb-ghost';
    line.style.background = (meta && meta.accent) || '#0b57d0';
    ghost.style.background = (meta && meta.fill) || '#d3e3fd';
    ghost.style.color = (meta && meta.onFill) || '#041e49';
    ghost.textContent = 'Mover «' + (pick.target.getAttribute('data-block-label') || '') + '»';
    document.body.appendChild(line);
    document.body.appendChild(ghost);
    moving = { el: pick.target, id: pick.target.getAttribute('data-block-id'), line: line, ghost: ghost,
      x: event.clientX, y: event.clientY, seam: null, speed: 0 };
    document.documentElement.classList.add('vb-moving');
    aim();
    requestAnimationFrame(scrollWhileMoving);
  }
  // The seam under the pointer: before or after the nearest block, unless
  // that leaves the dragged block where it is.
  function aim() {
    var m = moving, blocks = pageBlocks(), seam = null;
    var index = blocks.indexOf(m.el);
    blocks.some(function (el, i) {
      var r = el.getBoundingClientRect();
      if (m.y > r.bottom && i < blocks.length - 1) return false;
      var before = m.y < r.top + r.height / 2;
      var next = before ? i : i + 1;
      if (el !== m.el && next !== index && next !== index + 1) {
        seam = { anchor: el.getAttribute('data-block-id'), side: before ? 'before' : 'after',
          y: before ? r.top : r.bottom, left: r.left, width: r.width };
      }
      return true;
    });
    m.seam = seam;
    if (seam) {
      m.line.style.display = 'block';
      m.line.style.top = seam.y + 'px';
      m.line.style.left = seam.left + 'px';
      m.line.style.width = seam.width + 'px';
    } else {
      m.line.style.display = 'none';
    }
    m.ghost.style.display = 'block';
    m.ghost.style.left = (m.x + 14) + 'px';
    m.ghost.style.top = (m.y + 14) + 'px';
    var top = cover() + 48, bottom = innerHeight - 48;
    m.speed = m.y < top ? -Math.min(24, (top - m.y) / 2) : m.y > bottom ? Math.min(24, (m.y - bottom) / 2) : 0;
  }
  function scrollWhileMoving() {
    if (!moving) return;
    if (moving.speed) { window.scrollBy(0, moving.speed); aim(); }
    requestAnimationFrame(scrollWhileMoving);
  }
  function stopMoving(drop) {
    var m = moving;
    if (!m) return;
    moving = null;
    dragged = Date.now();
    m.line.remove();
    m.ghost.remove();
    document.documentElement.classList.remove('vb-moving');
    if (drop && m.seam) {
      send('vbDraftMove', [m.id, m.seam.anchor, m.seam.side],
        { type: 'vb-draft-move', id: m.id, anchor: m.seam.anchor, side: m.seam.side });
    }
    soon();
  }
  document.addEventListener('mousemove', function (event) {
    if (!moving) return;
    event.preventDefault();
    moving.x = event.clientX;
    moving.y = event.clientY;
    aim();
  }, true);
  document.addEventListener('mouseup', function () { stopMoving(true); }, true);
  addEventListener('blur', function () { stopMoving(false); });
  document.addEventListener('keydown', function (event) {
    if (moving && event.key === 'Escape') { event.preventDefault(); stopMoving(false); }
  }, true);
  window.vbDraftPicked = function (id, info, show) {
    pickedId = id || null;
    meta = info || null;
    layerSel = meta && meta.layer && typeof meta.layer.id === 'string' ? meta.layer : null;
    pick.target = pickedId ? shown(pickedId) : null;
    drawBar();
    if (show && pick.target) bring(pick.target);
    refresh();
    return !!pick.target;
  };
  // In the ERP on the web the page is a frame of another origin, which the
  // editor cannot script: it says it is ready, and the editor calls these
  // functions as messages signed with the view's nonce, only from the page
  // that holds the frame. What `vbDraftPicked` found goes back the same way.
  if (window.parent && window.parent !== window &&
      !(window.flutter_inappwebview && window.flutter_inappwebview.callHandler)) {
    var CALLS = ['vbDraftPicked', 'vbDraftEditing', 'vbDraftEdited', 'vbDraftSized', 'vbDraftSlides',
      'vbDraftLayered', 'vbDraftKey'];
    addEventListener('message', function (event) {
      var data = event.data;
      if (event.source !== window.parent || !data || data.type !== 'vb-host' ||
          data.nonce !== window.vbDraftNonce || CALLS.indexOf(data.call) < 0) return;
      var result = window[data.call].apply(null, data.args || []);
      if (data.call === 'vbDraftPicked') {
        window.parent.postMessage({ type: 'vb-draft-result', call: data.call, result: !!result,
          nonce: window.vbDraftNonce || null }, '*');
      }
    });
    window.parent.postMessage({ type: 'vb-draft-ready', nonce: window.vbDraftNonce || null }, '*');
  }
})();
''';
