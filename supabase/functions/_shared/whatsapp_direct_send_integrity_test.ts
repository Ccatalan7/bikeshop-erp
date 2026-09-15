import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  directSendIntegrityEventKey,
  directSendPolicyBlockFromEvents,
  parseDirectSendIntegrityNotice,
} from "./whatsapp_direct_send_integrity.ts";

Deno.test("parses category mismatch as a blocking critical notice", () => {
  const notice = parseDirectSendIntegrityNotice(
    "template_correct_category_detection",
    {
      message_template_id: 123,
      message_template_name: "direct_send_text_123",
      category: "UTILITY",
      correct_category: "MARKETING",
    },
  );

  assertEquals(notice?.kind, "category_mismatch");
  assertEquals(notice?.blocksDirectSend, true);
  assertEquals(notice?.templateId, "123");
  assertEquals(
    directSendIntegrityEventKey({
      field: "template_correct_category_detection",
      entryTime: 456,
      notice: notice!,
    }),
    "template_correct_category_detection:123:456",
  );
});

Deno.test("parses Direct Send warning, restriction and recovery", () => {
  const warning = parseDirectSendIntegrityNotice("account_update", {
    event: "ACCOUNT_RESTRICTION",
    violation_info: {
      violation_type: "DIRECT_SEND_UTILITY_CATEGORY_ABUSE_WARN",
    },
  });
  const restriction = parseDirectSendIntegrityNotice("account_update", {
    event: "ACCOUNT_RESTRICTION",
    violation_info: {
      violation_type: "DIRECT_SEND_UTILITY_CATEGORY_ABUSE_STRIKE_1",
    },
    restriction_info: [{ expiration: "2026-09-03T00:00:00Z" }],
  });
  const recovery = parseDirectSendIntegrityNotice("account_update", {
    event: "ACCOUNT_RESTRICTION",
    violation_info: {
      violation_type: "DIRECT_SEND_UTILITY_CATEGORY_ABUSE_UNBAN",
    },
  });

  assertEquals(warning?.kind, "warning");
  assertEquals(warning?.blocksDirectSend, true);
  assertEquals(restriction?.kind, "restriction");
  assertEquals(restriction?.blocksDirectSend, true);
  assertEquals(recovery?.kind, "recovery");
  assertEquals(recovery?.blocksDirectSend, false);
});

Deno.test("ignores unrelated WhatsApp account updates", () => {
  assertEquals(
    parseDirectSendIntegrityNotice("account_update", {
      event: "ACCOUNT_RESTRICTION",
      violation_info: { violation_type: "OTHER_PRODUCT_POLICY" },
    }),
    null,
  );
});

Deno.test("parses generated-template pause and recovery but ignores classic templates", () => {
  const paused = parseDirectSendIntegrityNotice(
    "message_template_status_update",
    {
      event: "PAUSED",
      message_template_id: 456,
      message_template_name: "direct_send_text_e22a3ec4",
      message_template_language: "es_CL",
    },
  );
  const recovered = parseDirectSendIntegrityNotice(
    "message_template_status_update",
    {
      event: "APPROVED",
      message_template_id: 456,
      message_template_name: "direct_send_text_e22a3ec4",
      message_template_language: "es_CL",
    },
  );

  assertEquals(paused?.kind, "template_paused");
  assertEquals(paused?.blocksDirectSend, true);
  assertEquals(recovered?.kind, "template_recovered");
  assertEquals(recovered?.blocksDirectSend, false);
  assertEquals(
    parseDirectSendIntegrityNotice("message_template_status_update", {
      event: "PAUSED",
      message_template_id: 789,
      message_template_name: "proveedor_saludo_v1",
    }),
    null,
  );
});

Deno.test("newest recovery clears an older account restriction", () => {
  const events = [
    {
      payload: {
        field: "account_update",
        value: {
          event: "ACCOUNT_RESTRICTION",
          violation_info: {
            violation_type: "DIRECT_SEND_UTILITY_CATEGORY_ABUSE_UNBAN",
          },
        },
      },
    },
    {
      payload: {
        field: "account_update",
        value: {
          event: "ACCOUNT_RESTRICTION",
          violation_info: {
            violation_type: "DIRECT_SEND_UTILITY_CATEGORY_ABUSE_STRIKE_1",
          },
        },
      },
    },
  ];

  assertEquals(directSendPolicyBlockFromEvents(events), null);
});

Deno.test("category mismatch blocks only the mapped ERP utility case", () => {
  const events = [{
    payload: {
      field: "template_correct_category_detection",
      source_template_name: "bicicleta_lista_retiro",
      value: {
        message_template_id: 123,
        message_template_name: "direct_send_text_123",
        correct_category: "MARKETING",
      },
    },
  }];

  assertEquals(
    directSendPolicyBlockFromEvents(events, "bicicleta_lista_retiro"),
    { reason: "category_mismatch", detail: "123" },
  );
  assertEquals(
    directSendPolicyBlockFromEvents(
      events,
      "actualizacion_servicio_bicicleta",
    ),
    null,
  );
});

Deno.test("unmapped misuse fails closed and a newer approval clears a pause", () => {
  assertEquals(
    directSendPolicyBlockFromEvents([{
      payload: {
        field: "template_correct_category_detection",
        value: {
          message_template_id: 123,
          message_template_name: "direct_send_text_unknown",
          correct_category: "MARKETING",
        },
      },
    }], "bicicleta_lista_retiro"),
    { reason: "category_mismatch", detail: "123" },
  );

  const recoveredThenPaused = [
    {
      payload: {
        field: "message_template_status_update",
        value: {
          event: "APPROVED",
          message_template_id: 456,
          message_template_name: "direct_send_text_e22a3ec4",
        },
      },
    },
    {
      payload: {
        field: "message_template_status_update",
        value: {
          event: "PAUSED",
          message_template_id: 456,
          message_template_name: "direct_send_text_e22a3ec4",
        },
      },
    },
  ];
  assertEquals(
    directSendPolicyBlockFromEvents(
      recoveredThenPaused,
      "actualizacion_servicio_bicicleta",
    ),
    null,
  );

  assertEquals(
    directSendPolicyBlockFromEvents(
      recoveredThenPaused.slice(1),
      "actualizacion_servicio_bicicleta",
    ),
    { reason: "template_paused", detail: "456" },
  );
});
