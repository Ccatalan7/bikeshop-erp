/// `/cotizacion`. The store's own roles (`--primary`, `--ink`, `--line`,
/// `--body`, `--head`) so a theme change in the editor reaches it; one tone
/// per kind of line: green on the shelf, the store color on order, amber
/// still to confirm. The notices are two square toggles of 44 px (email,
/// WhatsApp), either or both. Accepting asks two single choices (how it
/// arrives, how it is paid) as 56 px cards with a round mark, then the total
/// and one button. Under 900 px the form goes under the lines; under 560 the
/// side margin is 16 and the choices stack.
const quotePageCss = '''
.qt-page{--q-ink:var(--ink,#111827);--q-sec:var(--muted,#5b6470);--q-line:var(--line,#e5e7eb);--q-soft:var(--soft,#f6f7f9);--q-ok:#0f8a5f;--q-wait:#b45309;--q-bad:var(--bad,#c62828);--q-pri:var(--primary,#111827)}
.qt-page [hidden]{display:none!important}
.qt-in{width:min(1180px,calc(100% - 48px));margin:40px auto 64px}
.qt-load{margin:80px 0;text-align:center;font:500 15px/22px var(--body);color:var(--q-sec)}
.qt-kick{margin:0;font:800 12px/16px var(--body);letter-spacing:1.6px;text-transform:uppercase;color:var(--q-pri)}
.qt-title{margin:8px 0 0;font:800 40px/44px var(--head,var(--body));letter-spacing:-.5px;color:var(--q-ink);text-wrap:balance}
.qt-lede{max-width:640px;margin:12px 0 0;font:400 16px/25px var(--body);color:var(--q-sec)}
.qt-h2{margin:0 0 14px;font:700 18px/24px var(--body);color:var(--q-ink)}
.qt-grid{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:40px;margin-top:32px;align-items:start}
.qt-lines{list-style:none;margin:0;padding:0;border-top:1px solid var(--q-line)}
.qt-line{display:grid;grid-template-columns:76px minmax(0,1fr) auto;gap:16px;padding:18px 0;border-bottom:1px solid var(--q-line);align-items:center}
.qt-ph{display:grid;place-items:center;width:76px;height:76px;border-radius:10px;background:var(--q-soft);overflow:hidden;color:var(--q-sec)}
.qt-ph img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.qt-name{display:block;font:600 15px/21px var(--body);color:var(--q-ink);text-decoration:none}
.qt-name:hover{text-decoration:underline}
.qt-meta{margin:4px 0 0;font:400 13px/19px var(--body);color:var(--q-sec)}
.qt-tag{display:inline-flex;align-items:center;gap:6px;margin-top:8px;padding:4px 10px;border-radius:999px;font:700 11px/16px var(--body);letter-spacing:.3px;--t:var(--q-sec);color:var(--t);background:color-mix(in srgb,var(--t) 10%,transparent)}
.qt-tag[data-kind=in_stock]{--t:var(--q-ok)}
.qt-tag[data-kind=on_order]{--t:var(--q-pri)}
.qt-tag[data-kind=to_confirm],.qt-tag[data-kind=pending]{--t:var(--q-wait)}
.qt-tag[data-kind=unavailable]{--t:var(--q-bad)}
.qt-side{display:flex;flex-direction:column;align-items:flex-end;gap:10px}
.qt-qty{display:inline-flex;align-items:center;border:1px solid var(--q-line);border-radius:8px}
.qt-qty button{width:36px;height:36px;border:0;background:none;font:600 18px/1 var(--body);color:var(--q-ink);cursor:pointer}
.qt-qty output{min-width:28px;text-align:center;font:600 14px/20px var(--body);font-variant-numeric:tabular-nums}
.qt-rm{border:0;background:none;padding:4px 0;font:600 13px/18px var(--body);color:var(--q-sec);cursor:pointer;text-decoration:underline}
.qt-ref{margin:14px 0 0;font:400 13px/20px var(--body);color:var(--q-sec)}
.qt-form{position:sticky;top:96px;padding:24px;border:1px solid var(--q-line);border-radius:14px;background:#fff}
.qt-field{display:block;margin:0 0 14px}
.qt-field>span{display:block;margin:0 0 6px;font:600 13px/18px var(--body);color:var(--q-ink)}
.qt-field i{font-style:normal;font-weight:400;color:var(--q-sec)}
.qt-field input,.qt-field textarea{box-sizing:border-box;width:100%;padding:11px 12px;border:1px solid var(--q-line);border-radius:8px;background:#fff;font:400 15px/21px var(--body);color:var(--q-ink)}
.qt-field textarea{resize:vertical}
.qt-field input:focus,.qt-field textarea:focus{outline:2px solid color-mix(in srgb,var(--q-pri) 40%,transparent);border-color:var(--q-pri)}
.qt-copy{margin:0 0 16px;font:400 14px/21px var(--body);color:var(--q-sec)}
.qt-who{margin:0 0 18px;padding:0 0 16px;border-bottom:1px solid var(--q-line)}
.qt-who-name{margin:0;font:600 15px/21px var(--body);color:var(--q-ink)}
.qt-who-line{margin:2px 0 0;font:400 14px/20px var(--body);color:var(--q-sec);overflow-wrap:anywhere}
.qt-who-edit{display:inline-block;margin-top:6px;font:600 13px/18px var(--body);color:var(--q-pri)}
.qt-notify{margin:0 0 16px;padding:0;border:0;min-width:0}
.qt-notify legend{margin:0 0 8px;padding:0;font:600 13px/18px var(--body);color:var(--q-ink)}
.qt-notify-row{display:flex;gap:8px}
.qt-notify label{flex:1;position:relative;min-width:0}
.qt-notify input{position:absolute;width:1px;height:1px;opacity:0}
.qt-notify span{display:flex;align-items:center;justify-content:center;gap:8px;min-height:44px;padding:0 12px;border:1px solid var(--q-line);border-radius:8px;font:600 14px/20px var(--body);color:var(--q-ink);cursor:pointer}
.qt-notify span::before{content:"";flex:none;box-sizing:border-box;width:16px;height:16px;border:1.5px solid var(--q-sec);border-radius:4px}
.qt-notify input:checked+span{border-color:var(--q-pri);background:color-mix(in srgb,var(--q-pri) 8%,transparent);color:var(--q-pri)}
.qt-notify input:checked+span::before{border-color:var(--q-pri);background:var(--q-pri) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpath d='M2.5 6.2l2.2 2.2 4.8-4.9' fill='none' stroke='white' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center/12px no-repeat}
.qt-notify input:focus-visible+span{outline:2px solid var(--q-pri);outline-offset:2px}
.qt-notify input:disabled+span{opacity:.45;cursor:default}
.qt-hint{margin:8px 0 0;font:400 12px/18px var(--body);color:var(--q-sec)}
.qt-hint a{color:var(--q-pri);font-weight:600}
.qt-notice{margin:12px 0 0;font:400 14px/20px var(--body);color:var(--q-sec)}
.qt-notice .qt-btn.text{min-height:0;padding:0 0 0 6px;font-size:14px}
.qt-notice-edit{max-width:380px;margin-top:14px}
.qt-notice-edit .qt-acts{margin-top:4px}
.qt-err{margin:0 0 12px;font:600 13px/19px var(--body);color:var(--q-bad)}
.qt-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;box-sizing:border-box;min-height:48px;padding:0 22px;border-radius:8px;font:700 15px/20px var(--body);text-decoration:none;cursor:pointer}
.qt-form .qt-btn{width:100%}
.qt-btn.fill{border:0;background:var(--q-pri);color:#fff}
.qt-btn.fill:hover:not(:disabled){filter:brightness(1.08)}
.qt-btn.line{border:1px solid var(--q-ink);background:none;color:var(--q-ink)}
.qt-btn.text{border:0;background:none;color:var(--q-sec);text-decoration:underline}
.qt-btn:disabled{opacity:.5;cursor:default}
.qt-btn:focus-visible{outline:2px solid var(--q-pri);outline-offset:2px}
.qt-fine{margin:12px 0 0;font:400 12px/18px var(--body);color:var(--q-sec);text-align:center}
.qt-empty{max-width:560px;margin:40px 0}
.qt-empty .qt-btn{margin-top:24px}
.qt-stale .qt-offer,.qt-stale .qt-totals{opacity:.55}
.qt-card{margin-top:28px;padding:24px;border:1px solid var(--q-line);border-radius:14px;background:#fff}
.qt-status{display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin-top:14px}
.qt-pill{padding:6px 12px;border-radius:999px;font:700 12px/16px var(--body);--t:var(--q-sec);color:var(--t);background:color-mix(in srgb,var(--t) 10%,transparent)}
.qt-pill[data-s=confirming]{--t:var(--q-wait)}
.qt-pill[data-s=offered]{--t:var(--q-pri)}
.qt-pill[data-s=accepted]{--t:var(--q-ok)}
.qt-pill[data-s=rejected],.qt-pill[data-s=cancelled]{--t:var(--q-bad)}
.qt-when{font:400 14px/20px var(--body);color:var(--q-sec)}
.qt-offer{width:100%;border-collapse:collapse;font:400 14px/20px var(--body);color:var(--q-ink)}
.qt-offer th{padding:0 0 10px;text-align:left;font:700 12px/16px var(--body);letter-spacing:.4px;text-transform:uppercase;color:var(--q-sec)}
.qt-offer td{padding:14px 0;border-top:1px solid var(--q-line);vertical-align:top}
.qt-offer .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap;padding-left:16px}
.qt-offer .qt-tag{margin-top:6px}
.qt-note{margin:6px 0 0;font:400 13px/19px var(--body);color:var(--q-sec)}
.qt-totals{margin:16px 0 0 auto;max-width:320px;font:400 14px/22px var(--body);color:var(--q-sec)}
.qt-totals div{display:flex;justify-content:space-between;font-variant-numeric:tabular-nums}
.qt-totals .total{margin-top:6px;padding-top:8px;border-top:1px solid var(--q-line);font:800 20px/28px var(--body);color:var(--q-ink)}
.qt-acts{display:flex;flex-wrap:wrap;gap:12px;margin-top:22px}
.qt-change input{width:64px;padding:8px;border:1px solid var(--q-line);border-radius:8px;font:600 14px/20px var(--body);text-align:center}
.qt-history{list-style:none;margin:0;padding:0}
.qt-history li{display:flex;justify-content:space-between;gap:16px;padding:8px 0;border-bottom:1px solid var(--q-line);font:400 14px/20px var(--body);color:var(--q-ink)}
.qt-history time{color:var(--q-sec);white-space:nowrap}
.qt-link{display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin-top:18px;font:400 13px/19px var(--body);color:var(--q-sec)}
.qt-others{margin-top:28px;font:400 14px/20px var(--body);color:var(--q-sec)}
.qt-others a{color:var(--q-pri);font-weight:600}
.qt-accept{margin-top:24px;padding-top:22px;border-top:1px solid var(--q-line)}
.qt-accept .qt-h2{margin-top:18px}
.qt-accept .qt-h2:first-child{margin-top:0}
.qt-choice{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin:0 0 6px}
.qt-choice label{position:relative;min-width:0}
.qt-choice input{position:absolute;width:1px;height:1px;opacity:0}
.qt-choice span{display:flex;flex-direction:column;gap:2px;min-height:56px;padding:10px 14px 10px 40px;border:1px solid var(--q-line);border-radius:10px;cursor:pointer;position:relative}
.qt-choice span::before{content:"";position:absolute;left:14px;top:14px;box-sizing:border-box;width:16px;height:16px;border:1.5px solid var(--q-sec);border-radius:50%}
.qt-choice b{font:600 14px/20px var(--body);color:var(--q-ink)}
.qt-choice small{font:400 12px/17px var(--body);color:var(--q-sec)}
.qt-choice input:checked+span{border-color:var(--q-pri);background:color-mix(in srgb,var(--q-pri) 6%,transparent)}
.qt-choice input:checked+span::before{border:5px solid var(--q-pri)}
.qt-choice input:focus-visible+span{outline:2px solid var(--q-pri);outline-offset:2px}
.qt-choice input:disabled+span{opacity:.45;cursor:default}
.qt-address{margin:12px 0 4px;max-width:560px}
.qt-pair{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px}
.qt-field select{box-sizing:border-box;width:100%;min-height:44px;padding:10px 12px;border:1px solid var(--q-line);border-radius:8px;background:#fff;font:400 15px/21px var(--body);color:var(--q-ink)}
.qt-field select:focus{outline:2px solid color-mix(in srgb,var(--q-pri) 40%,transparent);border-color:var(--q-pri)}
.qt-accept .qt-totals{margin-top:18px}
.qt-accept .qt-err{margin:14px 0 0}
.qt-order-state{margin:0;font:500 15px/22px var(--body);color:var(--q-ink)}
.qt-order-lines{list-style:none;margin:14px 0 0;padding:0}
.qt-order-lines li{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:6px 16px;padding:10px 0;border-top:1px solid var(--q-line);font:400 14px/20px var(--body);color:var(--q-ink)}
.qt-order-lines .qt-tag{margin-top:0;justify-self:end}
.qt-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);max-width:calc(100% - 32px);padding:12px 18px;border-radius:10px;background:var(--q-ink);color:#fff;font:600 14px/20px var(--body);z-index:50}
.qt-toast.bad{background:var(--q-bad)}
@media (max-width:900px){.qt-grid{grid-template-columns:1fr}.qt-form{position:static}}
@media (max-width:560px){.qt-in{width:calc(100% - 32px);margin-top:24px}.qt-title{font-size:30px;line-height:34px}.qt-line{grid-template-columns:60px minmax(0,1fr);}.qt-ph{width:60px;height:60px}.qt-side{grid-column:1/-1;flex-direction:row;justify-content:space-between;align-items:center}.qt-card{padding:18px}.qt-offer th:nth-child(2){display:none}.qt-offer td:nth-child(2){display:none}.qt-choice,.qt-pair{grid-template-columns:1fr}.qt-accept .qt-acts .qt-btn.fill{width:100%}.qt-order-lines li{grid-template-columns:minmax(0,1fr)}.qt-order-lines .qt-tag{justify-self:start}}
''';
