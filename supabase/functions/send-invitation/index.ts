import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;

const FIREBASE_PREVIEW_ORIGIN = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;
const INVITATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const RESEND_TIMEOUT_MS = 15_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const SAFE_RESEND_ERROR_CODES = new Set([
  "application_error",
  "concurrent_idempotent_requests",
  "daily_quota_exceeded",
  "internal_server_error",
  "invalid_access",
  "invalid_api_key",
  "invalid_attachment",
  "invalid_from_address",
  "invalid_idempotency_key",
  "invalid_idempotent_request",
  "invalid_parameter",
  "invalid_region",
  "method_not_allowed",
  "missing_api_key",
  "missing_required_field",
  "monthly_quota_exceeded",
  "not_found",
  "rate_limit_exceeded",
  "restricted_api_key",
  "security_error",
  "validation_error",
]);

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

export interface InvitationEmail {
  to: string;
  subject: string;
  html: string;
  text: string;
}

interface ProviderFailureDetails {
  provider: "resend";
  status: number | null;
  providerCode: string;
}

type ProviderFailureLogger = (
  event: string,
  details: ProviderFailureDetails,
) => void;

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
    const bearerMatch = /^Bearer\s+(\S+)$/i.exec(authHeader);
    if (!bearerMatch) {
      throw new HttpError(401, "invalid_session", "Authentication required");
    }
    const accessToken = bearerMatch[1];

    const body = await readRequestBody(req);
    const invitationId = body.invitationId?.trim() ?? "";
    if (!UUID_PATTERN.test(invitationId)) {
      throw new HttpError(400, "invalid_invitation", "A valid invitation is required");
    }

    const runtime = options.runtime ?? createProductionRuntime(authHeader, accessToken);
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

function createProductionRuntime(
  authHeader: string,
  accessToken: string,
): SendInvitationRuntime {
  const getEnv: EnvReader = (name) => Deno.env.get(name);
  const supabaseUrl = requiredEnv(getEnv, "SUPABASE_URL");
  const serviceRoleKey = requiredEnv(getEnv, "SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = requiredEnv(getEnv, "SUPABASE_ANON_KEY");
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  return {
    authenticate: () => authenticateCaller(userClient, serviceClient, accessToken),
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
  accessToken: string,
): Promise<CallerContext> {
  const { data: userData, error: userError } = await userClient.auth.getUser(accessToken);
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

export async function sendInvitationEmail(
  email: InvitationEmail,
  getEnv: EnvReader,
  fetchImpl: typeof fetch = fetch,
  logFailure: ProviderFailureLogger = logProviderFailure,
): Promise<boolean> {
  const resendApiKey = requiredEnv(getEnv, "RESEND_API_KEY");
  const from = getEnv("INVITATION_FROM_EMAIL")?.trim() ||
    "Ventas Viñabike <ventas@vinabike.cl>";
  const replyTo = getEnv("INVITATION_REPLY_TO")?.trim() || "ventas@vinabike.cl";

  try {
    const response = await fetchImpl("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
        "User-Agent": "vinabike-erp-send-invitation/1.0",
      },
      body: JSON.stringify({
        from,
        reply_to: replyTo,
        to: [email.to],
        subject: email.subject,
        html: email.html,
        text: email.text,
      }),
      signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
    });

    if (response.ok) return true;

    logFailure("send-invitation provider rejected request", {
      provider: "resend",
      status: response.status,
      providerCode: await classifyResendFailure(response),
    });
    return false;
  } catch (_) {
    logFailure("send-invitation provider request failed", {
      provider: "resend",
      status: null,
      providerCode: "network_error",
    });
    return false;
  }
}

function logProviderFailure(
  event: string,
  details: ProviderFailureDetails,
): void {
  console.error(event, details);
}

async function classifyResendFailure(response: Response): Promise<string> {
  try {
    const raw = await response.text();
    if (!raw || raw.length > 16_384) return `http_${response.status}`;

    const parsed = JSON.parse(raw);
    if (!isRecord(parsed)) return `http_${response.status}`;

    const message = typeof parsed.message === "string" ? parsed.message.toLowerCase() : "";
    if (
      message.includes("only send testing emails to your own email address")
    ) {
      return "testing_recipient_restriction";
    }
    if (message.includes("domain") && message.includes("not verified")) {
      return "unverified_sender_domain";
    }
    if (
      message.includes("invalid from address") ||
      message.includes("invalid `from` field")
    ) {
      return "invalid_from_address";
    }

    const providerCode = typeof parsed.name === "string"
      ? parsed.name
      : typeof parsed.code === "string"
      ? parsed.code
      : "";
    return SAFE_RESEND_ERROR_CODES.has(providerCode) ? providerCode : `http_${response.status}`;
  } catch (_) {
    return `http_${response.status}`;
  }
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
    subject: `Te invitaron a ${shopName}: configura tu acceso`,
    html: `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="format-detection" content="telephone=no,date=no,address=no,email=no">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
  <title>Configura tu acceso a ${safeShopName}</title>
  <style>
    html, body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
    body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
    table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
    table { border-collapse: collapse; table-layout: fixed; }
    .breakable, .content-cell { overflow-wrap: anywhere; word-break: break-word; }
    a[x-apple-data-detectors] { color: inherit !important; text-decoration: none !important; }
    @media only screen and (max-width: 600px) {
      .outer-cell { padding: 16px 10px !important; }
      .header-cell { padding: 22px 20px 18px !important; }
      .content-cell { padding: 28px 20px !important; }
      .footer-cell { padding: 18px 20px 22px !important; }
      .security-badge { display: none !important; }
      .action-table, .button-cell, .button-link { width: 100% !important; }
      .button-link { display: block !important; }
      h1 { font-size: 25px !important; line-height: 32px !important; }
    }
  </style>
</head>
<body style="margin:0;padding:0;background:#EDF3F7;color:#263842;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;line-height:1px;">
    Acepta la invitación y configura tu acceso a ${safeShopName}.
  </div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;background:#EDF3F7;border-collapse:collapse;table-layout:fixed;">
    <tr>
      <td class="outer-cell" align="center" style="padding:34px 16px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;background:#FFFFFF;border:1px solid #DCE6EC;border-collapse:separate;border-radius:18px;box-shadow:0 10px 28px rgba(16,42,58,.08);table-layout:fixed;">
          <tr>
            <td style="height:6px;background:#0B6FCB;border-radius:18px 18px 0 0;font-size:0;line-height:0;">&nbsp;</td>
          </tr>
          <tr>
            <td class="header-cell" style="padding:24px 32px 20px;border-bottom:1px solid #E7EDF1;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;table-layout:fixed;">
                <tr>
                  <td width="48" valign="middle" style="width:48px;">
                    <div style="width:40px;height:40px;border-radius:12px;background:#0B6FCB;color:#FFFFFF;font-size:20px;font-weight:800;line-height:40px;text-align:center;">V</div>
                  </td>
                  <td valign="middle" style="min-width:0;padding-left:2px;">
                    <div class="breakable" style="color:#102A3A;font-size:18px;font-weight:800;letter-spacing:.1px;line-height:22px;">${safeShopName}</div>
                    <div style="margin-top:2px;color:#71818B;font-size:12px;line-height:16px;">Cuenta y seguridad</div>
                  </td>
                  <td class="security-badge" width="116" align="right" valign="middle" style="width:116px;">
                    <span style="display:inline-block;padding:6px 9px;border:1px solid #D8E5EF;border-radius:999px;color:#315C76;font-size:10px;font-weight:700;letter-spacing:.5px;line-height:14px;text-transform:uppercase;">Mensaje seguro</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td class="content-cell" style="padding:36px 38px 34px;overflow-wrap:anywhere;word-break:break-word;">
              <div style="margin:0 0 10px;color:#0B6FCB;font-size:11px;font-weight:800;letter-spacing:1.2px;line-height:16px;">INVITACIÓN AL EQUIPO</div>
              <h1 style="margin:0 0 17px;color:#102A3A;font-size:28px;font-weight:760;line-height:35px;">Configura tu acceso</h1>
              <p style="margin:0 0 10px;color:#3C4D57;font-size:15px;line-height:24px;">${safeGreeting}</p>
              <p style="margin:0;color:#3C4D57;font-size:15px;line-height:24px;">Te invitaron a unirte a <strong class="breakable">${safeShopName}</strong>.</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin-top:22px;background:#F6F9FB;border-collapse:separate;border-radius:12px;table-layout:fixed;">
                <tr>
                  <td width="34%" style="width:34%;padding:14px 8px 14px 18px;color:#71818B;font-size:12px;line-height:18px;">Perfil asignado</td>
                  <td class="breakable" style="padding:14px 18px 14px 8px;color:#102A3A;font-size:13px;font-weight:750;line-height:18px;text-align:right;">${safeRole}</td>
                </tr>
              </table>
              <table role="presentation" cellspacing="0" cellpadding="0" class="action-table" style="border-collapse:separate;margin:28px 0 18px;">
                <tr>
                  <td class="button-cell" bgcolor="#0B6FCB" style="border-radius:9px;text-align:center;">
                    <a class="button-link" href="${safeLink}" style="box-sizing:border-box;display:inline-block;min-height:48px;padding:14px 24px;color:#FFFFFF;font-size:15px;font-weight:700;line-height:20px;text-align:center;text-decoration:none;">Aceptar invitación</a>
                  </td>
                </tr>
              </table>
              <p style="margin:0 0 26px;color:#657783;font-size:12px;line-height:19px;">
                Si el botón no responde, <a class="breakable" href="${safeLink}" style="color:#0B6FCB;font-weight:700;text-decoration:underline;">abre este enlace seguro</a>.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;background:#F6F9FB;border-collapse:separate;border-radius:12px;table-layout:fixed;">
                <tr>
                  <td style="padding:16px 18px;overflow-wrap:anywhere;word-break:break-word;">
                    <div style="margin:0 0 5px;color:#102A3A;font-size:13px;font-weight:750;line-height:18px;">Qué ocurrirá</div>
                    <div style="color:#586A75;font-size:13px;line-height:20px;">Primero aceptarás la invitación. Si tu correo todavía no tiene una cuenta, después recibirás un segundo mensaje para verificar la dirección y terminar el alta.</div>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin-top:16px;background:#F4F8FB;border:1px solid #D8E5EF;border-collapse:separate;border-radius:12px;table-layout:fixed;">
                <tr>
                  <td width="38" valign="top" style="width:38px;padding:16px 0 16px 16px;color:#315C76;font-size:18px;font-weight:800;line-height:20px;">!</td>
                  <td valign="top" style="padding:16px 16px 16px 4px;color:#315C76;font-size:12px;line-height:19px;overflow-wrap:anywhere;word-break:break-word;">Este enlace es personal, puede utilizarse una sola vez y expira el ${expiryLabel}. Si no esperabas la invitación, ignora el mensaje y no compartas el enlace.</td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td class="footer-cell" style="padding:19px 38px 24px;border-top:1px solid #E7EDF1;color:#7A8992;font-size:11px;line-height:17px;overflow-wrap:anywhere;word-break:break-word;">
              Este es un mensaje automático de seguridad de ${safeShopName}. Nunca te pediremos tu contraseña por correo, teléfono, chat o redes sociales. Si necesitas ayuda, escribe a <a href="mailto:contacto@vinabike.cl" style="color:#315C76;text-decoration:underline;">contacto@vinabike.cl</a>.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`,
    text: [
      firstName ? `Hola ${firstName},` : "Hola,",
      "",
      `Te invitaron a unirte a ${shopName}.`,
      `Perfil asignado: ${roleDisplay}.`,
      `Acepta la invitación: ${link}`,
      "",
      "Si tu correo todavía no tiene una cuenta, después recibirás un segundo mensaje para verificar la dirección y terminar el alta.",
      "",
      `El enlace es personal, puede utilizarse una sola vez y expira el ${expiryLabel}. No lo compartas.`,
      "Si necesitas ayuda, escribe a contacto@vinabike.cl.",
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
