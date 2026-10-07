import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The draft's own look and behaviour: the editor's outlines (the only
/// visual difference the editor contract allows), links that do not leave
/// the page, and a click that tells the editor which block it picked.
List<Component> draftExtras() => [
  Component.element(tag: 'style', children: [RawText(_draftCss)]),
  script(content: _draftScript),
];

const _draftCss = '''
[data-block-id]{position:relative}
[data-block-id]:hover{outline:1px dashed rgb(26 115 232 / .7);outline-offset:-1px}
[data-block-id].vb-picked{outline:2px solid #1a73e8;outline-offset:-2px}
.draft-missing{display:grid;place-items:center;gap:4px;min-height:160px;margin:0;padding:24px;
  border:1px dashed #9aa0a6;border-radius:8px;background:repeating-linear-gradient(135deg,#f8f9fa 0 12px,#f1f3f4 12px 24px);
  color:#5f6368;font:400 14px/1.4 var(--body,system-ui);text-align:center}
.draft-missing p{margin:0;max-width:52ch}
.draft-missing-t{font-weight:700;color:#3c4043}
''';

/// A click picks the block under it and goes nowhere: the editor hears it
/// through the web view's handler (`vbDraftPick`) or, in the ERP on the
/// web, a message to the page that holds the frame. The editor marks its
/// selection with `vbDraftPicked(id)`.
const _draftScript = r'''
(function () {
  function tell(id) {
    var host = window.flutter_inappwebview;
    if (host && host.callHandler) { host.callHandler('vbDraftPick', id); return; }
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: 'vb-draft-pick', id: id }, '*');
    }
  }
  document.addEventListener('click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    var block = event.target.closest && event.target.closest('[data-block-id]');
    tell(block ? block.getAttribute('data-block-id') : null);
  }, true);
  document.addEventListener('submit', function (event) { event.preventDefault(); }, true);
  window.vbDraftPicked = function (id) {
    [].forEach.call(document.querySelectorAll('.vb-picked'), function (el) { el.classList.remove('vb-picked'); });
    if (!id) return;
    [].forEach.call(document.querySelectorAll('[data-block-id]'), function (el) {
      if (el.getAttribute('data-block-id') === id) el.classList.add('vb-picked');
    });
  };
})();
''';
