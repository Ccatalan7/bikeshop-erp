import { assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isAuthorizedZohoSender,
  normalizeZohoNumericId,
  resolveAuthorizedZohoSenderIdentities,
  resolveZohoOrganizationId,
  resolveZohoUserId,
} from "./zoho_sender_identities.ts";

const accountPayload = {
  data: {
    accountId: "2560636000000008002",
    zuid: 809451734,
    policyId: { zoid: 3226386 },
    primaryEmailAddress: "contacto@vinabike.cl",
    mailboxStatus: "enabled",
    status: true,
    enabled: true,
    smtpStatus: true,
    outgoingBlocked: false,
    sendMailDetails: [
      {
        fromAddress: "alias@vinabike.cl",
        displayName: "Alias Viñabike",
        status: true,
      },
      {
        fromAddress: "CONTACTO@vinabike.cl",
        displayName: "Viñabike",
        status: true,
      },
      {
        fromAddress: "disabled@vinabike.cl",
        status: false,
      },
    ],
  },
};

Deno.test("keeps active mailbox senders primary-first and adds an authorized group", () => {
  const identities = resolveAuthorizedZohoSenderIdentities({
    accountPayload,
    groupsPayload: {
      data: {
        groups: [
          {
            emailId: "ventas@vinabike.cl",
            name: "Ventas Viñabike",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: "809451734", status: "active", sendAsRight: false },
            ],
          },
        ],
      },
    },
  });

  assertEquals(identities, [
    {
      address: "CONTACTO@vinabike.cl",
      displayName: "Viñabike",
      source: "mailbox",
    },
    {
      address: "alias@vinabike.cl",
      displayName: "Alias Viñabike",
      source: "mailbox",
    },
    {
      address: "ventas@vinabike.cl",
      displayName: "Ventas Viñabike",
      source: "group",
    },
  ]);
  assertEquals(isAuthorizedZohoSender(identities, " VENTAS@VINABIKE.CL "), true);
  assertFalse(isAuthorizedZohoSender(identities, "arbitrario@vinabike.cl"));
});

Deno.test("accepts a member-specific send-as right without global mailbox rights", () => {
  const identities = resolveAuthorizedZohoSenderIdentities({
    accountPayload,
    groupsPayload: {
      data: {
        groups: [
          {
            emailId: "taller@vinabike.cl",
            name: "Taller",
            groupAdminSettings: { mailboxSendRights: false },
            mailGroupMemberList: [
              { zuid: 809451734, status: "active", sendAsRight: true },
            ],
          },
        ],
      },
    },
  });

  assertEquals(identities.at(-1), {
    address: "taller@vinabike.cl",
    displayName: "Taller",
    source: "group",
  });
});

Deno.test("rejects foreign, deactivated, unprivileged and malformed groups", () => {
  const identities = resolveAuthorizedZohoSenderIdentities({
    accountPayload,
    groupsPayload: {
      data: {
        groups: [
          {
            emailId: "foreign@vinabike.cl",
            name: "Foreign",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: 999999999, status: "active", sendAsRight: true },
            ],
          },
          {
            emailId: "inactive-group@vinabike.cl",
            status: "deactive",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: 809451734, status: "active", sendAsRight: true },
            ],
          },
          {
            emailId: "inactive-member@vinabike.cl",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: 809451734, status: "deactive", sendAsRight: true },
            ],
          },
          {
            emailId: "no-right@vinabike.cl",
            groupAdminSettings: { mailboxSendRights: false },
            mailGroupMemberList: [
              { zuid: 809451734, status: "active", sendAsRight: false },
            ],
          },
          {
            emailId: "not-an-email",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: 809451734, status: "active", sendAsRight: true },
            ],
          },
        ],
      },
    },
  });

  assertEquals(
    identities.map((identity) => identity.source),
    ["mailbox", "mailbox"],
  );
});

Deno.test("fails closed when account or membership identifiers are malformed", () => {
  assertEquals(normalizeZohoNumericId("../../groups"), null);
  assertEquals(
    resolveZohoOrganizationId({ data: { policyId: { zoid: "bad-id" } } }),
    null,
  );
  assertEquals(resolveZohoUserId({ data: { zuid: "8 OR 1=1" } }), null);

  const identities = resolveAuthorizedZohoSenderIdentities({
    accountPayload: {
      data: {
        ...accountPayload.data,
        zuid: "foreign-id",
        policyId: { zoid: "invalid" },
      },
    },
    groupsPayload: {
      data: {
        groups: [
          {
            emailId: "ventas@vinabike.cl",
            groupAdminSettings: { mailboxSendRights: true },
            mailGroupMemberList: [
              { zuid: 809451734, status: "active", sendAsRight: true },
            ],
          },
        ],
      },
    },
  });

  assertEquals(
    identities.map((identity) => identity.source),
    ["mailbox", "mailbox"],
  );
});

Deno.test("rejects every sender when the mailbox or active send details are disabled", () => {
  const disabledAccount = {
    data: {
      ...accountPayload.data,
      outgoingBlocked: true,
    },
  };
  assertEquals(
    resolveAuthorizedZohoSenderIdentities({
      accountPayload: disabledAccount,
      groupsPayload: { data: { groups: [] } },
    }),
    [],
  );

  const senderWithoutExplicitStatus = {
    data: {
      ...accountPayload.data,
      sendMailDetails: [{ fromAddress: "contacto@vinabike.cl" }],
    },
  };
  assertEquals(
    resolveAuthorizedZohoSenderIdentities({ accountPayload: senderWithoutExplicitStatus }),
    [],
  );
});
