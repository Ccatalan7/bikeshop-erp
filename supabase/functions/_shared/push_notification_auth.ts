export const PUSH_NOTIFICATION_WEBHOOK_HEADER = "x-push-webhook-secret";

function constantTimeEqual(actual: string, expected: string): boolean {
  // The loop length depends only on the configured secret, not attacker input.
  // Folding the actual length into the mismatch avoids an early length oracle.
  let mismatch = actual.length ^ expected.length;
  for (let index = 0; index < expected.length; index++) {
    mismatch |= expected.charCodeAt(index) ^ (actual.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

export function pushWebhookAuthorized(
  headers: Headers,
  expectedSecret: string | null | undefined,
): boolean {
  if (!expectedSecret) return false;
  const providedSecret = headers.get(PUSH_NOTIFICATION_WEBHOOK_HEADER) ?? "";
  if (!providedSecret) return false;
  return constantTimeEqual(providedSecret, expectedSecret);
}
