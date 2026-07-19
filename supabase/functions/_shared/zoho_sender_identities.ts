export type ZohoSenderIdentity = {
  address: string;
  displayName?: string;
  source: "mailbox" | "group";
};

type UnknownRecord = Record<string, unknown>;

const EMAIL_PATTERN = /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/;
const NUMERIC_ID_PATTERN = /^\d{1,30}$/;

function asRecord(value: unknown): UnknownRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as UnknownRecord
    : null;
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}

function normalizedEmail(value: unknown): string | null {
  const address = cleanText(value);
  return EMAIL_PATTERN.test(address) ? address.toLowerCase() : null;
}

function isExplicitlyEnabled(value: unknown): boolean {
  if (value === true) return true;
  if (typeof value === "number") return value === 1;
  return ["true", "1", "yes", "active", "enabled"].includes(
    cleanText(value).toLowerCase(),
  );
}

function isExplicitlyDisabled(value: unknown): boolean {
  if (value === false) return true;
  if (typeof value === "number") return value === 0;
  return ["false", "0", "no", "inactive", "deactive", "disabled", "blocked"]
    .includes(cleanText(value).toLowerCase());
}

function isAccountEnabled(account: UnknownRecord): boolean {
  if (isExplicitlyDisabled(account.status)) return false;
  if (isExplicitlyDisabled(account.enabled)) return false;
  if (isExplicitlyDisabled(account.smtpStatus)) return false;
  if (isExplicitlyEnabled(account.outgoingBlocked)) return false;

  const mailboxStatus = cleanText(account.mailboxStatus).toLowerCase();
  return !mailboxStatus || ["enabled", "active"].includes(mailboxStatus);
}

function isGroupEnabled(group: UnknownRecord): boolean {
  for (const key of ["status", "enabled", "isActive", "groupStatus"]) {
    if (key in group && isExplicitlyDisabled(group[key])) return false;
  }
  const mailboxStatus = cleanText(group.mailboxStatus).toLowerCase();
  return !mailboxStatus || ["enabled", "active"].includes(mailboxStatus);
}

function isMemberActive(member: UnknownRecord): boolean {
  return ["active", "enabled", "accepted"].includes(
    cleanText(member.status).toLowerCase(),
  );
}

export function normalizeZohoNumericId(value: unknown): string | null {
  const normalized = cleanText(value);
  return NUMERIC_ID_PATTERN.test(normalized) ? normalized : null;
}

export function resolveZohoOrganizationId(accountPayload: unknown): string | null {
  const account = zohoDataRecord(accountPayload);
  if (!account) return null;

  const policy = asRecord(account.policyId);
  return normalizeZohoNumericId(
    policy?.zoid ?? account.zoid ?? account.organizationId ?? account.orgId,
  );
}

export function resolveZohoUserId(accountPayload: unknown): string | null {
  const account = zohoDataRecord(accountPayload);
  return normalizeZohoNumericId(account?.zuid ?? account?.userId);
}

export function zohoDataRecord(payload: unknown): UnknownRecord | null {
  const root = asRecord(payload);
  if (!root) return null;
  return asRecord(root.data) ?? root;
}

export function zohoGroups(payload: unknown): UnknownRecord[] {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? root;
  const groups = data?.groups;
  if (!Array.isArray(groups)) return [];
  return groups.map(asRecord).filter((value): value is UnknownRecord => value !== null);
}

function appendIdentity(
  output: ZohoSenderIdentity[],
  seen: Set<string>,
  addressValue: unknown,
  displayNameValue: unknown,
  source: ZohoSenderIdentity["source"],
) {
  const normalized = normalizedEmail(addressValue);
  if (!normalized || seen.has(normalized)) return;

  const displayName = cleanText(displayNameValue);
  seen.add(normalized);
  output.push({
    address: cleanText(addressValue),
    ...(displayName ? { displayName } : {}),
    source,
  });
}

/**
 * Resolves only sender identities that Zoho currently authorizes.
 *
 * The account payload must be from /api/accounts/{accountId}; the groups
 * payload must be from /api/organization/{zoid}/groups using the same OAuth
 * token. No caller-provided address participates in this discovery step.
 */
export function resolveAuthorizedZohoSenderIdentities(input: {
  accountPayload: unknown;
  groupsPayload?: unknown;
}): ZohoSenderIdentity[] {
  const account = zohoDataRecord(input.accountPayload);
  if (!account || !isAccountEnabled(account)) return [];

  const identities: ZohoSenderIdentity[] = [];
  const seen = new Set<string>();
  const primaryAddress = normalizedEmail(account.primaryEmailAddress) ??
    normalizedEmail(account.mailboxAddress) ??
    normalizedEmail(account.incomingUserName);
  const rawSenders = account.sendMailDetails;

  if (Array.isArray(rawSenders)) {
    const enabledSenders = rawSenders
      .map(asRecord)
      .filter((sender): sender is UnknownRecord =>
        sender !== null && isExplicitlyEnabled(sender.status)
      );

    enabledSenders.sort((left, right) => {
      const leftPrimary = normalizedEmail(left.fromAddress) === primaryAddress;
      const rightPrimary = normalizedEmail(right.fromAddress) === primaryAddress;
      return Number(rightPrimary) - Number(leftPrimary);
    });

    for (const sender of enabledSenders) {
      appendIdentity(
        identities,
        seen,
        sender.fromAddress,
        sender.displayName ?? account.displayName ?? account.accountDisplayName,
        "mailbox",
      );
    }
  }

  const accountZuid = resolveZohoUserId(account);
  const accountZoid = resolveZohoOrganizationId(account);
  if (!accountZuid || !accountZoid || input.groupsPayload === undefined) {
    return identities;
  }

  for (const group of zohoGroups(input.groupsPayload)) {
    if (!isGroupEnabled(group)) continue;

    const members = Array.isArray(group.mailGroupMemberList)
      ? group.mailGroupMemberList.map(asRecord).filter(
        (member): member is UnknownRecord => member !== null,
      )
      : [];
    const currentMember = members.find((member) =>
      normalizeZohoNumericId(member.zuid) === accountZuid && isMemberActive(member)
    );
    if (!currentMember) continue;

    const adminSettings = asRecord(group.groupAdminSettings);
    const globalSendRight = isExplicitlyEnabled(adminSettings?.mailboxSendRights);
    const memberSendRight = isExplicitlyEnabled(currentMember.sendAsRight);
    if (!globalSendRight && !memberSendRight) continue;

    appendIdentity(
      identities,
      seen,
      group.emailId,
      group.name,
      "group",
    );
  }

  return identities;
}

export function isAuthorizedZohoSender(
  identities: readonly ZohoSenderIdentity[],
  requestedAddress: unknown,
): boolean {
  const normalized = normalizedEmail(requestedAddress);
  return normalized !== null && identities.some(
    (identity) => normalizedEmail(identity.address) === normalized,
  );
}
