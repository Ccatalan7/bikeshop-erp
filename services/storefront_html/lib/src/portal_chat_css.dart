part of 'portal_page_css.dart';

/// «Soporte»'s styles, added to [portalPageCss] on that page only: the
/// page fits the window under the store's header (`--pt-top`, which the
/// chat's script measures) as Flutter's portal fits a page that scrolls
/// itself; the frame of `_ChatFrame`, the bubbles, cards and composer of
/// `CustomerChatView`, the rows of `_ConversationRow` and the job beside the
/// conversation in wide. Square, in the portal's colors and type.
String portalChatCss(WebsiteThemeRoles roles) {
  final head = _family(roles.headingFont);
  final body = _family(roles.bodyFont);
  FlutterTextCss heading(
    double size, {
    int weight = 600,
    double spacing = 1,
    double height = 1.05,
  }) => FlutterTextCss(head, size, height, weight, spacing, heading: true);
  FlutterTextCss text(double size, {int weight = 400, double height = 1.45}) =>
      FlutterTextCss(body, size, height, weight, 0.25, heading: false);
  String rule(String selector, FlutterTextCss style, [String extra = '']) =>
      '$selector{${style.font}$extra}'
      '$selector>.pt-x{left:${cssPx(style.spacing / 2)}}';

  final micro = heading(11, weight: 500, spacing: 1.3, height: 1.25);
  final rowMeta = text(14, height: 1.4);

  return '''
/* La página es el chat: sin el botón flotante que lleva a ella. */
.chat-fab{display:none}
.pt-chatpage{display:flex;flex-direction:column;height:calc(100vh - var(--pt-top,56px));height:calc(100dvh - var(--pt-top,56px));min-height:440px}
.pt-chatpage>.pt-tabs{flex:none}
.pt-chat-main{flex:1;min-height:0;display:flex;gap:32px;padding-block:28px 16px}
.pt-chat-main.side{max-width:calc(1120px + 336px + 2 * var(--pt-g))}
@container pt (max-width:899.98px){.pt-chat-main{padding-top:16px}}
.pt-chat-body{container:ptchat/inline-size;flex:1;min-width:0;min-height:0;display:flex;flex-direction:column}
.pt-chat-body>.pt-back{flex:none;align-self:flex-start;margin-bottom:8px}
.pt-chat-head{flex:none;display:flex;align-items:center;gap:16px;margin-bottom:20px}
${rule('.pt-chat-title', heading(28, height: 1), ';flex:1;min-width:0;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis')}
${rule('.pt-chat-lead', rowMeta, ';flex:none;max-width:620px;margin:-8px 0 24px;color:var(--pt-ink2)')}
@container pt (max-width:899.98px){
.pt-chat-main.thread .pt-chat-head{display:none}
.pt-chat-main.thread .pt-chat-body>.pt-back{margin-bottom:12px}
}

/* La lista: filas del portal bajo su línea fuerte. */
.pt-chat-list{flex:1;min-height:0;overflow-y:auto;padding-bottom:48px}
.pt-crow{padding-block:14px}
.pt-crow-in{display:flex;align-items:center}
.pt-crow-in>.pt-thumb{margin-right:16px}
.pt-crow-in>.pt-what{flex:1;min-width:0}
.pt-crow-in>svg{flex:none;margin-left:12px}
.pt-crow-meta{max-width:100%;overflow:hidden;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical}
.pt-crow-when,.pt-crow-foot{display:none}
.pt-crow-foot{margin-top:10px}
.pt-crow-end{flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:8px;margin-left:16px}
@container ptchat (max-width:559.98px){.pt-crow-end{display:none}.pt-crow-when{display:inline}.pt-crow-foot{display:flex}}

/* La conversación: el marco recto, los avisos, los mensajes y el campo. */
.pt-chat-frame{flex:1;min-height:0;display:flex;flex-direction:column;border:1px solid var(--pt-line);border-top-color:var(--pt-ink);background:var(--pt-page)}
.pt-chat-info{flex:none;display:none;justify-content:flex-end;padding-inline:16px;border-bottom:1px solid var(--pt-line)}
@container pt (max-width:899.98px){.pt-chat-info{display:flex}}
.pt-chat-banner{display:flex;align-items:center;gap:12px;padding:12px 16px;border-bottom:1px solid var(--pt-line);background:var(--pt-well)}
.pt-chat-banner-dot{flex:none;width:8px;height:8px;background:var(--pt-muted)}
.pt-chat-banner.pending .pt-chat-banner-dot{background:var(--pt-att)}
.pt-chat-banner.rejected .pt-chat-banner-dot,.pt-chat-banner.unavailable .pt-chat-banner-dot,.pt-chat-banner.offline .pt-chat-banner-dot{background:var(--pt-bad)}
${rule('.pt-chat-banner>p', rowMeta, ';flex:1;min-width:0;color:var(--pt-ink)')}
.pt-chat-banner .pt-tbtn{flex:none;min-height:36px;margin:-8px -8px -8px 0;padding:0 12px}
.pt-chat-scroll{position:relative;flex:1;min-height:0;overflow-y:auto;overscroll-behavior:contain;padding:16px}
.pt-chat-scroll:focus-visible{outline:2px solid var(--pt-act);outline-offset:-2px}
.pt-chat-log{display:flex;flex-direction:column;justify-content:flex-end;min-height:100%}
.pt-chat-edge{display:flex;justify-content:center;padding-bottom:4px}
${rule('.pt-chat-edge.start', text(11, weight: 500, height: 1.45), ';padding-block:10px;text-align:center;color:var(--pt-ink2)')}
.pt-chat-older{display:inline-flex;align-items:center;gap:8px;min-height:40px;padding:0 12px;color:var(--pt-act)}
${rule('.pt-chat-older', text(14, weight: 500, height: 1.43))}
.pt-chat-older:hover{background:color-mix(in srgb,currentColor 8%,transparent)}
.pt-chat-older:disabled{color:var(--pt-muted);background:none;cursor:default}
.pt-chat-day{display:flex;align-items:center;gap:12px;padding-block:12px}
.pt-chat-day::before,.pt-chat-day::after{content:'';flex:1;height:1px;background:var(--pt-line)}
${rule('.pt-chat-day-label', micro, ';color:var(--pt-ink2)')}
.pt-msg{display:flex;margin-bottom:10px}
.pt-msg.mine{justify-content:flex-end}
.pt-msg-b{display:flex;flex-direction:column;align-items:flex-start;max-width:75%;min-width:0;padding:12px 16px;background:var(--pt-well);color:var(--pt-ink)}
.pt-msg.mine .pt-msg-b{align-items:flex-end;background:var(--pt-ink);color:var(--pt-page)}
.pt-msg.sending .pt-msg-b{opacity:.62}
${rule('.pt-msg-text', text(15, height: 1.5), ';max-width:100%;white-space:pre-wrap;overflow-wrap:anywhere;user-select:text')}
${rule('.pt-msg-time', heading(10, weight: 500, spacing: 1.3, height: 1.25), ';display:block;margin-top:6px;opacity:.7')}
.pt-msg-img{position:relative;display:block;width:260px;max-width:100%;height:180px;overflow:hidden;background:var(--pt-hi)}
.pt-msg-img img{display:block;width:100%;height:100%;object-fit:cover}
${rule('.pt-msg-img-bad', rowMeta, ';position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:12px;text-align:center;color:var(--pt-ink)')}
.pt-msg-file{display:flex;align-items:center;gap:9px;max-width:100%;min-height:40px;text-align:left}
${rule('.pt-msg-file-name', text(15, weight: 700, height: 1.4), ';min-width:0;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical')}
.pt-msg-file.none{gap:8px}
${rule('.pt-msg-file.none>span', text(15, height: 1.4))}
.pt-msg-img:focus-visible,.pt-msg-file:focus-visible,.pt-chat-older:focus-visible,.pt-chat-send:focus-visible{outline:2px solid var(--pt-act);outline-offset:2px}

/* La solicitud de la tienda: una tarjeta recta con su estado. */
.pt-ask{align-self:flex-start;width:420px;max-width:100%;margin-bottom:12px;padding:12px 15px 10px;border:1px solid var(--pt-line);border-top:3px solid var(--pt-ink);background:var(--pt-page)}
.pt-ask-head{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px}
${rule('.pt-ask-title', heading(18), ';text-transform:uppercase')}
${rule('.pt-ask-text', text(14, height: 1.45), ';margin-top:10px;white-space:pre-wrap;overflow-wrap:anywhere')}
${rule('.pt-ask-note', rowMeta, ';margin-top:10px;padding:10px;background:var(--pt-well);color:var(--pt-ink);white-space:pre-wrap;overflow-wrap:anywhere')}
${rule('.pt-ask-pay', rowMeta, ';margin-top:10px;color:var(--pt-ink2)')}
.pt-ask-actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.pt-ask .pt-msg-time{margin-top:8px;opacity:1;color:var(--pt-ink2)}

/* El campo de escribir, al pie. */
.pt-chat-compose{flex:none;display:flex;align-items:flex-end;gap:8px;padding:12px 12px calc(12px + env(safe-area-inset-bottom,0px));border-top:1px solid var(--pt-line);background:var(--pt-page)}
.pt-chat-input{flex:1;min-width:0;height:48px;max-height:148px;margin:0;padding:13px 16px;border:1px solid var(--pt-line);border-radius:0;background:var(--pt-page);color:var(--pt-ink);font:400 16px/20px var(--body);letter-spacing:.5px;resize:none;outline:0;-webkit-appearance:none;appearance:none}
.pt-chat-input::placeholder{color:var(--pt-muted);opacity:1}
.pt-chat-input:hover{background:color-mix(in srgb,var(--pt-ink) 4%,var(--pt-page))}
.pt-chat-input:focus{padding:12px 15px;border:2px solid var(--pt-act)}
.pt-chat-send{flex:none;display:flex;align-items:center;justify-content:center;width:48px;height:48px;background:var(--pt-act);color:var(--pt-onact)}
.pt-chat-send:hover{background-image:linear-gradient(color-mix(in srgb,currentColor 10%,transparent),color-mix(in srgb,currentColor 10%,transparent))}

/* Al lado, en ancho: el trabajo de la conversación. */
.pt-chat-side{flex:none;display:none;flex-direction:column;align-items:flex-start;width:304px;max-height:100%;overflow-y:auto;padding-top:64px}
@container pt (min-width:900px){.pt-chat-side{display:flex}}
.pt-chat-side>.pt-sh-bar{margin-bottom:14px}
${rule('.pt-chat-side-title', heading(24, spacing: 0.5, height: 1.1), ';margin-top:8px;text-transform:uppercase;overflow-wrap:anywhere')}
.pt-chat-side-tag{display:flex;margin-top:14px}
.pt-chat-side>.pt-facts{align-self:stretch;margin-top:20px;padding-top:16px;border-top:1px solid var(--pt-ink)}
.pt-chat-side>.pt-link{margin-top:12px}

/* Los diálogos: el campo de varias líneas, el rótulo arriba. */
.pt-f.ta.pt-chat-field{--pt-fh:128px}
.pt-chat-field textarea{height:128px}
.pt-f.ta.pt-chat-field label{top:15px}
.pt-f.ta.pt-chat-field :is(input,textarea):is(:focus,:not(:placeholder-shown))~label{transform:translate(0,-22px) scale(.75)}
#pt-chat-new .pt-alert-sub{margin-bottom:20px}
''';
}
