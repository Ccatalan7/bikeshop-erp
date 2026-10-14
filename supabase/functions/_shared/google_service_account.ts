// Access token of a Google service account (JWT bearer grant), for the
// functions that read Google with Viñabike's own account instead of a person's
// OAuth session. Same signing as google-product-diagnostics, which keeps its
// copy until it is deployed again (deploying it would also ship its
// unrelated pending changes).

export type FetchLike = typeof fetch;

export async function serviceAccountAccessToken(args: {
  email: string;
  privateKey: string;
  scopes: string[];
  fetchImpl?: FetchLike;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: args.email,
    scope: args.scopes.join(" "),
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const jwt = await signJwt(claim, args.privateKey);
  const response = await (args.fetchImpl ?? fetch)("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || typeof payload?.access_token !== "string") {
    // Google's error text never carries the key; keep it short anyway.
    throw new Error(
      `Google no entregó un token para la cuenta de servicio (${response.status} ${
        String(payload?.error ?? "").slice(0, 60)
      })`,
    );
  }
  return payload.access_token;
}

async function signJwt(claim: Record<string, unknown>, privateKey: string): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(claim)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function base64UrlJson(value: Record<string, unknown>): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
