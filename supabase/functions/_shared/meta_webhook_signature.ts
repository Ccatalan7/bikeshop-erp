function hexBytes(value: string): Uint8Array | null {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null;
  const bytes = new Uint8Array(32);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

export async function verifyMetaWebhookSignature(input: {
  signatureHeader: string | null;
  rawBody: string | Uint8Array;
  appSecret: string | null;
}): Promise<boolean> {
  const header = input.signatureHeader?.trim() ?? "";
  const match = /^sha256=([0-9a-f]{64})$/i.exec(header);
  const supplied = match ? hexBytes(match[1]) : null;
  const secret = input.appSecret ?? "";
  if (!supplied || !secret) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const body: Uint8Array<ArrayBuffer> = typeof input.rawBody === "string"
    ? new TextEncoder().encode(input.rawBody)
    : Uint8Array.from(input.rawBody);
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, body),
  );

  return constantTimeEqual(expected, supplied);
}
