# WhatsApp Direct Send contract

Status: transport implemented 2026-08-27; production WABA access pending Meta
enablement. Direct Send is a premium capability rolled out incrementally per
WABA.

## Product behavior

- Inside the customer-service window, ordinary non-template messages continue
  as service messages. Meta identifies the open 24-hour window; links remain in
  the body and Direct Send link previews are not requested.
- Outside the window, the ERP may use Direct Send only for a repository-owned
  Utility definition. The server reconstructs the body from
  `whatsapp_templates.ts`; neither Flutter nor an authenticated caller can mark
  arbitrary text as Utility.
- Marketing and Authentication are not promoted to Utility. Marketing retains
  the classic Meta template and requires a live `APPROVED` state.
- A synchronous Direct Send rejection proves Meta did not accept that attempt,
  so `whatsapp-send` retries once with the same classic approved template. A
  network/unknown outcome or a provider acceptance without durable ERP evidence
  never falls back and never retries blindly.
- Existing ERP clients inherit this behavior server-side when they send a known
  Utility template, even if they do not yet include `deliveryStrategy`.

## Evidence and pricing

Each outbound row records `delivery_strategy_requested`, the actual
`delivery_strategy`, the Direct Send resolution, Graph evidence, and any
fallback rejection. Status webhooks continue to persist the complete Meta
payload, including `template_id` and `pricing`.

The settings estimator counts only status payloads where Meta explicitly marks
the delivered message as billable (`pricing.type=regular`, with the legacy
`billable=true` accepted for old receipts). It does not infer charges from a
24-hour window or from a template name. Service/free receipts are excluded.

## Integrity response

`whatsapp-webhook` ingests `template_correct_category_detection`, generated
`message_template_status_update` pause/recovery, and Direct Send
`account_update` restriction/recovery events into
`whatsapp_webhook_events`, and emits a durable ERP notification routed to
`/settings/whatsapp`. A mapped category mismatch or pause blocks that ERP
Utility case; an unmapped Direct Send enforcement event fails closed
account-wide. An account warning or restriction also blocks Direct Send
account-wide. The newest recovery event clears an older matching restriction.
While blocked, the sender uses the classic template path.

The Meta app must subscribe to `template_correct_category_detection`,
`account_update`, and `message_template_status_update` in addition to the
existing message/status webhooks. Code readiness is not evidence that Meta has
enabled the beta for the WABA; the first real, explicitly authorized send and
its status receipt are the eligibility read-back.

## Production Meta configuration read-back

The Meta App Dashboard was read back on 2026-08-27 at 17:50 PDT for
`Viñabike App` (`26325303243793949`). Its callback remains
`https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-webhook`, and
the following fields were visibly `Suscritos`:

- `account_update` on Graph API v26.0;
- `message_template_status_update` on Graph API v26.0;
- `template_correct_category_detection` on Graph API v26.0;
- the pre-existing `messages` field on Graph API v25.0.

This proves the production dashboard routing only. Direct Send beta eligibility
still requires the first real, explicitly authorized send and its status
receipt.

## Production eligibility read-back

The first authorized production attempt ran on 2026-08-27 at 18:04 PDT for
WABA `912031294920516`. The ERP requested `direct_send_utility`, but Meta
rejected the `category: utility` request synchronously with HTTP 400, error
`#100`, and the explicit detail that Direct Send is not enabled for this
account. The normal availability fallback then delivered
`actualizacion_servicio_bicicleta` as `classic_template_fallback`; delivery of
that message is therefore **not** evidence that Direct Send worked.

The same production WABA was selected explicitly in WhatsApp Manager. Its
Direct Send banner read that the capability is not yet available for this
business. The official Meta interest form was submitted on 2026-08-27 for this
WABA and returned `Se ha registrado tu respuesta`.

Until Meta enables the WABA, an attempt count proves only that the new path was
tried. The acceptance gate is a persisted outbound receipt whose actual
`delivery_strategy` is `direct_send_utility`, with no
`direct_send_rejection` and no classic-template fallback.

## Unrelated August 2026 changes

The ERP does not onboard WABAs with Embedded Signup v2/v3 or the deprecated
`only_waba_sharing`, `marketing_messages_lite`, or `coex` flags, so the
Embedded Signup v4 deadline does not change this integration. The ERP also does
not use Marketing Messages API max-price campaigns.

Primary Meta references:

- <https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/>
- <https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/send-utility-and-authentication-messages>
- <https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/integrity-and-content-guidelines>
- <https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/supported-features-and-limits>
- <https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing>
