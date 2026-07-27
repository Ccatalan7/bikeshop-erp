import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;

const FIREBASE_PREVIEW_ORIGIN = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;
const WORKER_LOGIN_EMAIL = /^[^@\s]+@worker-login\.invalid$/i;
const WORKER_USERNAME = /^[a-z0-9][a-z0-9._-]{2,31}$/;
const DUMMY_LOGIN_EMAIL = "no-account@worker.invalid";
const MAX_REQUEST_BYTES = 2048;
const MAX_PASSWORD_LENGTH = 256;

type EnvReader = (name: string) => string | undefined;

interface WorkerLoginCredentials {
  tenant: string;
  username: string;
  password: string;
}

interface WorkerLoginSession {
  refreshToken: string;
}

export interface WorkerLoginRuntime {
  resolveLoginEmail(tenant: string, username: string): Promise<string | null>;
  signInWithPassword(email: string, password: string): Promise<WorkerLoginSession | null>;
}

export interface WorkerLoginHandlerOptions {
  runtime?: WorkerLoginRuntime;
  allowedOrigins?: readonly string[];
}

interface WorkerResolverClient {
  rpc(
    name: string,
    args: Record<string, string>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

interface WorkerPasswordAuthClient {
  auth: {
    signInWithPassword(input: {
      email: string;
      password: string;
    }): PromiseLike<{
      data: { session?: { refresh_token?: string | null } | null } | null;
      error: unknown;
    }>;
  };
}

class ServiceUnavailableError extends Error {}

export async function handler(
  req: Request,
  options: WorkerLoginHandlerOptions = {},
): Promise<Response> {
  const allowedOrigins = options.allowedOrigins ?? configuredCorsOrigins();
  const origin = req.headers.get("origin");

  if (origin && !isAllowedCorsOrigin(origin, allowedOrigins)) {
    return json(
      req,
      { success: false, error: "Origen no permitido", code: "origin_not_allowed" },
      403,
      allowedOrigins,
    );
  }

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(req, allowedOrigins),
    });
  }

  if (req.method !== "POST") {
    return json(
      req,
      { success: false, error: "Método no permitido", code: "method_not_allowed" },
      405,
      allowedOrigins,
    );
  }

  const credentials = await readCredentials(req);
  if (!credentials) return invalidCredentials(req, allowedOrigins);

  let runtime: WorkerLoginRuntime;
  try {
    runtime = options.runtime ?? createProductionRuntime();
  } catch (error) {
    if (error instanceof ServiceUnavailableError) {
      return json(
        req,
        {
          success: false,
          error: "Inicio de sesión temporalmente no disponible",
          code: "service_unavailable",
        },
        503,
        allowedOrigins,
      );
    }
    return invalidCredentials(req, allowedOrigins);
  }

  try {
    const resolvedEmail = await runtime.resolveLoginEmail(
      credentials.tenant,
      credentials.username,
    );
    const loginEmail = resolvedEmail && WORKER_LOGIN_EMAIL.test(resolvedEmail)
      ? resolvedEmail
      : DUMMY_LOGIN_EMAIL;
    const session = await runtime.signInWithPassword(
      loginEmail,
      credentials.password,
    );

    if (!session?.refreshToken) {
      return invalidCredentials(req, allowedOrigins);
    }

    return json(
      req,
      { success: true, refreshToken: session.refreshToken },
      200,
      allowedOrigins,
    );
  } catch (_) {
    return invalidCredentials(req, allowedOrigins);
  }
}

if (import.meta.main) {
  Deno.serve((req) => handler(req));
}

function createProductionRuntime(): WorkerLoginRuntime {
  const getEnv: EnvReader = (name) => Deno.env.get(name);
  const supabaseUrl = requiredEnv(getEnv, "SUPABASE_URL");
  const serviceRoleKey = requiredEnv(getEnv, "SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = requiredEnv(getEnv, "SUPABASE_ANON_KEY");
  const clientOptions = {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  } as const;
  const resolverClient = createClient(
    supabaseUrl,
    serviceRoleKey,
    clientOptions,
  );
  const authClient = createClient(supabaseUrl, anonKey, clientOptions);

  return buildWorkerLoginRuntime(resolverClient, authClient);
}

export function buildWorkerLoginRuntime(
  resolverClient: WorkerResolverClient,
  authClient: WorkerPasswordAuthClient,
): WorkerLoginRuntime {
  return {
    resolveLoginEmail: async (tenant, username) => {
      const { data, error } = await resolverClient.rpc("resolve_worker_login", {
        p_tenant: tenant,
        p_username: username,
      });
      if (error) throw new ServiceUnavailableError();
      return extractResolvedEmail(data);
    },
    signInWithPassword: async (email, password) => {
      const { data, error } = await authClient.auth.signInWithPassword({
        email,
        password,
      });
      const refreshToken = data?.session?.refresh_token;
      if (error || typeof refreshToken !== "string" || !refreshToken) return null;
      return { refreshToken };
    },
  };
}

function extractResolvedEmail(data: unknown): string | null {
  if (typeof data === "string") return data.trim() || null;
  if (Array.isArray(data)) {
    const first = data[0];
    if (!first || typeof first !== "object") return null;
    const email = (first as Record<string, unknown>).login_email;
    return typeof email === "string" ? email.trim() || null : null;
  }
  if (data && typeof data === "object") {
    const email = (data as Record<string, unknown>).login_email;
    return typeof email === "string" ? email.trim() || null : null;
  }
  return null;
}

async function readCredentials(req: Request): Promise<WorkerLoginCredentials | null> {
  const contentLength = Number(req.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) return null;

  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch (_) {
    return null;
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) return null;

  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch (_) {
    return null;
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;

  const input = body as Record<string, unknown>;
  const tenant = typeof input.tenant === "string" ? input.tenant.trim() : "";
  const username = typeof input.username === "string" ? input.username.trim().toLowerCase() : "";
  const password = typeof input.password === "string" ? input.password : "";

  if (
    tenant.length < 1 ||
    tenant.length > 253 ||
    hasControlCharacters(tenant) ||
    !WORKER_USERNAME.test(username) ||
    password.length < 1 ||
    password.length > MAX_PASSWORD_LENGTH
  ) {
    return null;
  }

  return { tenant, username, password };
}

function hasControlCharacters(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });
}

function invalidCredentials(
  req: Request,
  allowedOrigins: readonly string[],
): Response {
  return json(
    req,
    {
      success: false,
      error: "Credenciales inválidas",
      code: "invalid_credentials",
    },
    401,
    allowedOrigins,
  );
}

export function isAllowedCorsOrigin(
  origin: string,
  configuredOrigins: readonly string[] = configuredCorsOrigins(),
): boolean {
  const normalized = normalizeOrigin(origin);
  if (!normalized) return false;
  const allowed = new Set([
    ...DEFAULT_ALLOWED_ORIGINS,
    ...configuredOrigins
      .map(normalizeOrigin)
      .filter((value): value is string => value !== null),
  ]);
  return allowed.has(normalized) || FIREBASE_PREVIEW_ORIGIN.test(normalized);
}

function configuredCorsOrigins(): string[] {
  const values = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const appUrl = Deno.env.get("APP_URL")?.trim();
  if (appUrl) values.push(appUrl);
  return values;
}

function corsHeaders(req: Request, allowedOrigins: readonly string[]): HeadersInit {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const origin = req.headers.get("origin");
  if (origin && isAllowedCorsOrigin(origin, allowedOrigins)) {
    headers["Access-Control-Allow-Origin"] = normalizeOrigin(origin)!;
  }
  return headers;
}

function json(
  req: Request,
  data: unknown,
  status: number,
  allowedOrigins: readonly string[],
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(req, allowedOrigins),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function normalizeOrigin(value: string): string | null {
  try {
    return new URL(value).origin;
  } catch (_) {
    return null;
  }
}

function requiredEnv(getEnv: EnvReader, name: string): string {
  const value = getEnv(name)?.trim();
  if (!value) throw new ServiceUnavailableError();
  return value;
}
