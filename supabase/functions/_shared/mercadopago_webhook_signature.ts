function signatureParts(header: string): { timestamp: string; hashes: string[] } | null {
  let timestamp = "";
  const hashes: string[] = [];

  for (const part of header.split(",")) {
    const separator = part.indexOf("=");
    if (separator < 1) continue;
    const key = part.slice(0, separator).trim().toLowerCase();
    const value = part.slice(separator + 1).trim().toLowerCase();
    if (key === "ts") timestamp = value;
    if (key === "v1" && /^[0-9a-f]{64}$/.test(value)) hashes.push(value);
  }

  if (!/^\d{9,16}$/.test(timestamp) || hashes.length === 0) return null;
  return { timestamp, hashes };
}

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function verifyMercadoPagoWebhookSignature(input: {
  signatureHeader: string | null;
  requestId: string | null;
  dataId: string | null;
  secret: string | null;
}): Promise<boolean> {
  const signature = signatureParts(input.signatureHeader?.trim() ?? "");
  const requestId = input.requestId?.trim() ?? "";
  const dataId = input.dataId?.trim().toLowerCase() ?? "";
  const secret = input.secret?.trim() ?? "";

  // Checkout Pro notifications are expected to contain all three manifest
  // fields. Rejecting incomplete manifests prevents accepting a signature over
  // a weaker, ambiguous message.
  if (!signature || !requestId || !dataId || !secret) return false;

  const manifest = `id:${dataId};request-id:${requestId};ts:${signature.timestamp};`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = hex(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(manifest),
    ),
  );

  return signature.hashes.some((candidate) => constantTimeEqual(expected, candidate));
}
