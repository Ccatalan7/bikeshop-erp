import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;

const FIREBASE_PREVIEW_ORIGIN = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;
const INVITATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// The project does not generate database types for Edge Functions yet.
// deno-lint-ignore no-explicit-any
type SupabaseClient = any;
type EnvReader = (name: string) => string | undefined;

interface InvitationRequest {
  invitationId?: string;
}

interface CallerContext {
  userId: string;
  tenantId: string;
}

interface InvitationData {
  id: string;
  email: string;
  role: string;
  tenant_id: string;
  metadata: Record<string, unknown> | null;
  tenants: { shop_name?: string | null } | Array<{ shop_name?: string | null }> | null;
}

interface InvitationEmail {
  to: string;
  subject: string;
  html: string;
  text: string;
}

export interface SendInvitationRuntime {
  authenticate(): Promise<CallerContext>;
  loadInvitation(invitationId: string, tenantId: string): Promise<InvitationData | null>;
  rotateInvitationToken(input: {
    invitationId: string;
    tenantId: string;
    tokenHash: string;
    expiresAt: string;
  }): Promise<boolean>;
  sendEmail(email: InvitationEmail): Promise<boolean>;
  invitationBaseUrl(): string;
  now(): Date;
  generateToken(): string;
}

export interface SendInvitationHandlerOptions {
  runtime?: SendInvitationRuntime;
  allowedOrigins?: readonly string[];
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
  }
}

export async function handler(
  req: Request,
  options: SendInvitationHandlerOptions = {},
): Promise<Response> {
  const configuredOrigins = options.allowedOrigins ?? configuredCorsOrigins();
  const origin = req.headers.get("origin");

  if (origin && !isAllowedCorsOrigin(origin, configuredOrigins)) {
    return json(
      req,
      { error: "Origin not allowed", code: "origin_not_allowed" },
      403,
      configuredOrigins,
    );
  }

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(req, configuredOrigins),
    });
  }

  if (req.method !== "POST") {
    return json(
      req,
      { error: "Method not allowed", code: "method_not_allowed" },
      405,
      configuredOrigins,
    );
  }

  try {
    const authHeader = req.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(authHeader)) {
      throw new HttpError(401, "invalid_session", "Authentication required");
    }

    const body = await readRequestBody(req);
    const invitationId = body.invitationId?.trim() ?? "";
    if (!UUID_PATTERN.test(invitationId)) {
      throw new HttpError(400, "invalid_invitation", "A valid invitation is required");
    }

    const runtime = options.runtime ?? createProductionRuntime(authHeader);
    const caller = await runtime.authenticate();
    const invitation = await runtime.loadInvitation(invitationId, caller.tenantId);
    if (
      !invitation ||
      invitation.id !== invitationId ||
      invitation.tenant_id !== caller.tenantId
    ) {
      throw new HttpError(404, "invitation_not_found", "Invitation not found");
    }
    if (
      typeof invitation.email !== "string" ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(invitation.email)
    ) {
      throw new HttpError(409, "invitation_invalid", "The invitation cannot be delivered");
    }

    const issuedAt = runtime.now();
    const expiresAt = new Date(issuedAt.getTime() + INVITATION_TTL_MS).toISOString();
    const token = runtime.generateToken();
    if (!TOKEN_PATTERN.test(token)) {
      throw new HttpError(500, "token_generation_failed", "Unable to secure the invitation");
    }
    const tokenHash = await hashInvitationToken(token);

    const rotated = await runtime.rotateInvitationToken({
      invitationId: invitation.id,
      tenantId: caller.tenantId,
      tokenHash,
      expiresAt,
    });
    if (!rotated) {
      throw new HttpError(
        409,
        "invitation_not_pending",
        "The invitation can no longer be sent",
      );
    }

    const email = buildInvitationEmail(
      invitation,
      runtime.invitationBaseUrl(),
      token,
      new Date(expiresAt),
    );
    const emailSent = await runtime.sendEmail(email);
    if (!emailSent) {
      throw new HttpError(
        502,
        "invitation_delivery_failed",
        "The invitation email could not be delivered",
      );
    }

    return json(
      req,
      {
        success: true,
        emailSent: true,
        invitationId: invitation.id,
        expiresAt,
      },
      200,
      configuredOrigins,
    );
  } catch (error) {
    const safeError = toSafeHttpError(error);

    if (safeError.status >= 500) {
      console.error("send-invitation request failed", { code: safeError.code });
    }

    return json(
      req,
      { error: safeError.publicMessage, code: safeError.code },
      safeError.status,
      configuredOrigins,
    );
  }
}

if (import.meta.main) {
  Deno.serve((req) => handler(req));
}

function createProductionRuntime(authHeader: string): SendInvitationRuntime {
  const getEnv: EnvReader = (name) => Deno.env.get(name);
  const supabaseUrl = requiredEnv(getEnv, "SUPABASE_URL");
  const serviceRoleKey = requiredEnv(getEnv, "SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = requiredEnv(getEnv, "SUPABASE_ANON_KEY");
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  return {
    authenticate: () => authenticateCaller(userClient, serviceClient),
    loadInvitation: (invitationId, tenantId) =>
      loadInvitation(serviceClient, invitationId, tenantId),
    rotateInvitationToken: (input) => rotateInvitationToken(serviceClient, input),
    sendEmail: (email) => sendInvitationEmail(email, getEnv),
    invitationBaseUrl: () => invitationBaseUrl(getEnv),
    now: () => new Date(),
    generateToken: generateInvitationToken,
  };
}

export async function authenticateCaller(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
): Promise<CallerContext> {
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    throw new HttpError(401, "invalid_session", "Authentication required");
  }

  const { data, error } = await serviceClient
    .from("user_profiles")
    .select("tenant_id, role, permissions, tenants!inner(id, is_active)")
    .eq("user_id", user.id)
    .eq("is_active", true)
    .eq("tenants.is_active", true)
    .limit(2);

  if (error) {
    throw new HttpError(503, "authorization_unavailable", "Unable to verify account access");
  }

  const profiles = Array.isArray(data) ? data : [];
  if (profiles.length !== 1) {
    throw new HttpError(403, "tenant_context_invalid", "A single active tenant is required");
  }

  const profile = profiles[0];
  const tenantRelation = Array.isArray(profile.tenants) ? profile.tenants : [profile.tenants];
  const activeTenants = tenantRelation.filter((tenant: unknown) => {
    if (!isRecord(tenant)) return false;
    return tenant.id === profile.tenant_id && tenant.is_active === true;
  });
  if (
    typeof profile.tenant_id !== "string" ||
    !UUID_PATTERN.test(profile.tenant_id) ||
    activeTenants.length !== 1
  ) {
    throw new HttpError(403, "tenant_context_invalid", "A valid active tenant is required");
  }
  const permissions = isRecord(profile.permissions) ? profile.permissions : {};
  const canManage = ["owner", "admin", "manager"].includes(profile.role) ||
    permissions.manage_users === true;
  if (!canManage) {
    throw new HttpError(403, "forbidden", "User management permission is required");
  }

  return {
    userId: user.id,
    tenantId: profile.tenant_id,
  };
}

async function loadInvitation(
  serviceClient: SupabaseClient,
  invitationId: string,
  tenantId: string,
): Promise<InvitationData | null> {
  const { data, error } = await serviceClient
    .from("user_invitations")
    .select("id, email, role, tenant_id, metadata, tenants (shop_name)")
    .eq("id", invitationId)
    .eq("tenant_id", tenantId)
    .eq("status", "pending")
    .maybeSingle();

  if (error) {
    throw new HttpError(503, "invitation_lookup_failed", "Unable to load the invitation");
  }

  return data ? data as InvitationData : null;
}

async function rotateInvitationToken(
  serviceClient: SupabaseClient,
  input: {
    invitationId: string;
    tenantId: string;
    tokenHash: string;
    expiresAt: string;
  },
): Promise<boolean> {
  const { data, error } = await serviceClient.rpc("rotate_user_invitation_token", {
    p_invitation_id: input.invitationId,
    p_tenant_id: input.tenantId,
    p_token_hash: input.tokenHash,
    p_expires_at: input.expiresAt,
  });

  if (error) {
    if (isInvitationRotationRateLimit(error)) {
      throw new HttpError(
        429,
        "invitation_rate_limited",
        "Please wait before sending this invitation again",
      );
    }
    throw new HttpError(503, "invitation_rotation_failed", "Unable to secure the invitation");
  }

  return data === true;
}

function toSafeHttpError(error: unknown): HttpError {
  if (error instanceof HttpError) return error;
  if (isInvitationRotationRateLimit(error)) {
    return new HttpError(
      429,
      "invitation_rate_limited",
      "Please wait before sending this invitation again",
    );
  }
  return new HttpError(500, "internal_error", "Unable to send the invitation");
}

export function isInvitationRotationRateLimit(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as Record<string, unknown>;
  const code = typeof record.code === "string" ? record.code : "";
  const message = typeof record.message === "string" ? record.message : "";
  return code === "55000" &&
    message.toLowerCase().includes("invitation token rotation is rate limited");
}

async function sendInvitationEmail(
  email: InvitationEmail,
  getEnv: EnvReader,
): Promise<boolean> {
  const resendApiKey = requiredEnv(getEnv, "RESEND_API_KEY");
  const from = getEnv("INVITATION_FROM_EMAIL")?.trim() ||
    "Ventas Viñabike <ventas@vinabike.cl>";
  const replyTo = getEnv("INVITATION_REPLY_TO")?.trim() || "ventas@vinabike.cl";

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      reply_to: replyTo,
      to: [email.to],
      subject: email.subject,
      html: email.html,
      text: email.text,
    }),
  });

  return response.ok;
}

export function generateInvitationToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export async function hashInvitationToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function buildInvitationEmail(
  invitation: InvitationData,
  baseUrl: string,
  token: string,
  expiresAt: Date,
): InvitationEmail {
  const tenant = Array.isArray(invitation.tenants) ? invitation.tenants[0] : invitation.tenants;
  const shopName = cleanText(tenant?.shop_name) || "Viñabike";
  const firstName = cleanText(invitation.metadata?.first_name);
  const roleDisplay = getRoleDisplayName(invitation.role);
  const invitationUrl = new URL("/accept-invitation.html", `${baseUrl}/`);
  invitationUrl.hash = `token=${encodeURIComponent(token)}`;
  const link = invitationUrl.toString();
  const expiryLabel = expiresAt.toLocaleDateString("es-CL", {
    timeZone: "America/Santiago",
  });

  const safeGreeting = firstName ? `Hola ${escapeHtml(firstName)},` : "Hola,";
  const safeShopName = escapeHtml(shopName);
  const safeRole = escapeHtml(roleDisplay);
  const safeLink = escapeHtml(link);

  return {
    to: invitation.email,
    subject: `Invitación al Sistema - ${shopName}`,
    html: `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Invitación al sistema</title>
</head>
<body style="font-family:Arial,sans-serif;line-height:1.6;color:#262626">
  <main style="max-width:600px;margin:0 auto;padding:24px">
    <div style="background:#1976d2;color:#fff;padding:20px;text-align:center">
      <h1 style="margin:0;font-size:24px">Invitación al sistema</h1>
    </div>
    <div style="padding:28px 20px;background:#f7f7f7">
      <p>${safeGreeting}</p>
      <p>Has sido invitado a unirte a <strong>${safeShopName}</strong> con el rol de <strong>${safeRole}</strong>.</p>
      <p style="text-align:center;margin:28px 0">
        <a href="${safeLink}" style="display:inline-block;padding:12px 28px;background:#1976d2;color:#fff;text-decoration:none;border-radius:5px">Aceptar invitación</a>
      </p>
      <p style="font-size:13px;color:#555">Este enlace es personal, puede utilizarse una sola vez y expira el ${expiryLabel}. No lo compartas.</p>
    </div>
    <footer style="padding:20px;text-align:center;font-size:12px;color:#666">
      © ${expiresAt.getUTCFullYear()} ${safeShopName}
    </footer>
  </main>
</body>
</html>`,
    text: [
      firstName ? `Hola ${firstName},` : "Hola,",
      "",
      `Has sido invitado a unirte a ${shopName} con el rol de ${roleDisplay}.`,
      `Acepta la invitación: ${link}`,
      "",
      `Este enlace es personal, puede utilizarse una sola vez y expira el ${expiryLabel}.`,
    ].join("\n"),
  };
}

function getRoleDisplayName(role: string): string {
  const roles: Record<string, string> = {
    owner: "Propietario",
    admin: "Administrador",
    manager: "Gerente",
    cashier: "Cajero",
    mechanic: "Mecánico",
    accountant: "Contador",
  };
  return roles[role] ?? "Usuario";
}

function invitationBaseUrl(getEnv: EnvReader): string {
  const configured = getEnv("INVITATION_APP_URL")?.trim() ||
    getEnv("APP_URL")?.trim() ||
    "https://project-vinabike.web.app";

  try {
    const parsed = new URL(configured);
    const isLoopback = parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1";
    if (parsed.protocol !== "https:" && !(parsed.protocol === "http:" && isLoopback)) {
      throw new Error("unsafe protocol");
    }
    return parsed.origin;
  } catch (_) {
    throw new HttpError(
      503,
      "invitation_url_unavailable",
      "Invitation delivery is not configured",
    );
  }
}

async function readRequestBody(req: Request): Promise<InvitationRequest> {
  try {
    const body = await req.json();
    return isRecord(body) ? body as InvitationRequest : {};
  } catch (_) {
    throw new HttpError(400, "invalid_request", "A valid JSON request is required");
  }
}

export function isAllowedCorsOrigin(
  origin: string,
  configuredOrigins: readonly string[] = configuredCorsOrigins(),
): boolean {
  const normalized = normalizeOrigin(origin);
  if (!normalized) return false;

  const allowed = new Set([
    ...DEFAULT_ALLOWED_ORIGINS,
    ...configuredOrigins.map(normalizeOrigin).filter((value): value is string => value !== null),
  ]);

  return allowed.has(normalized) || FIREBASE_PREVIEW_ORIGIN.test(normalized);
}

function configuredCorsOrigins(): string[] {
  const values = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  for (const name of ["APP_URL", "INVITATION_APP_URL"]) {
    const value = Deno.env.get(name)?.trim();
    if (value) values.push(value);
  }

  return values;
}

function corsHeaders(req: Request, configuredOrigins: readonly string[]): HeadersInit {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const origin = req.headers.get("origin");
  if (origin && isAllowedCorsOrigin(origin, configuredOrigins)) {
    headers["Access-Control-Allow-Origin"] = normalizeOrigin(origin)!;
  }
  return headers;
}

function json(
  req: Request,
  data: unknown,
  status: number,
  configuredOrigins: readonly string[],
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(req, configuredOrigins),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function requiredEnv(getEnv: EnvReader, name: string): string {
  const value = getEnv(name)?.trim();
  if (!value) {
    throw new HttpError(503, "service_not_configured", "Invitation delivery is unavailable");
  }
  return value;
}

function normalizeOrigin(value: string): string | null {
  try {
    return new URL(value).origin;
  } catch (_) {
    return null;
  }
}

function cleanText(value: unknown): string {
  if (typeof value !== "string") return "";
  return Array.from(value, (character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127 ? " " : character;
  }).join("").trim();
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
