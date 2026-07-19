export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let difference = leftBytes.length ^ rightBytes.length;

  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }

  return difference === 0;
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padding = "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(normalized + padding);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function encodeBase64(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export async function signSvixPayload(
  secret: string,
  messageId: string,
  timestamp: string,
  rawBody: string,
): Promise<string> {
  const encodedSecret = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  let secretBytes: Uint8Array;
  try {
    secretBytes = decodeBase64(encodedSecret);
  } catch {
    throw new Error("Invalid webhook signing secret encoding");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(secretBytes).buffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${messageId}.${timestamp}.${rawBody}`),
  );
  return encodeBase64(signature);
}

export async function verifyResendWebhookSignature(params: {
  rawBody: string;
  messageId: string | null;
  timestamp: string | null;
  signature: string | null;
  secret: string;
  now?: Date;
  toleranceSeconds?: number;
}): Promise<boolean> {
  const {
    rawBody,
    messageId,
    timestamp,
    signature,
    secret,
    now = new Date(),
    toleranceSeconds = 300,
  } = params;
  if (!messageId || !timestamp || !signature || !secret) return false;

  const timestampSeconds = Number(timestamp);
  if (!Number.isInteger(timestampSeconds)) return false;
  const ageSeconds = Math.abs(Math.floor(now.getTime() / 1000) - timestampSeconds);
  if (ageSeconds > toleranceSeconds) return false;

  let expected: string;
  try {
    expected = await signSvixPayload(secret, messageId, timestamp, rawBody);
  } catch {
    return false;
  }

  return signature
    .split(/\s+/)
    .map((candidate) => candidate.trim())
    .filter(Boolean)
    .some((candidate) => {
      const separator = candidate.indexOf(",");
      if (separator < 0 || candidate.slice(0, separator) !== "v1") return false;
      return constantTimeEqual(candidate.slice(separator + 1), expected);
    });
}
