#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(scriptPath), "..", "..");
const templateRoot = path.join(projectRoot, "supabase", "templates");

const actionLinks = {
  confirmation:
    "{{ .SiteURL }}/auth-action.html#confirmation_url={{ .ConfirmationURL }}",
  invite:
    "{{ .SiteURL }}/auth-action.html#token_hash={{ .TokenHash }}&amp;type=invite&amp;redirect_to={{ .RedirectTo }}",
  recovery:
    "{{ .SiteURL }}/auth-action.html#token_hash={{ .TokenHash }}&amp;type=recovery&amp;redirect_to={{ .RedirectTo }}",
};

export const authEmailDefinitions = [
  {
    key: "confirmation",
    category: "template",
    file: "auth_confirmation.html",
    subject: "Confirma tu correo y termina de crear tu cuenta",
    title: "Confirma tu correo",
    preheader: "Te falta un paso para activar tu acceso a Viñabike.",
    eyebrow: "ACTIVACIÓN DE CUENTA",
    lead:
      "Confirma que <strong class=\"breakable\">{{ .Email }}</strong> te pertenece para terminar de crear tu cuenta Viñabike.",
    action: {
      label: "Confirmar mi correo",
      href: actionLinks.confirmation,
    },
    detailTitle: "Después de confirmar",
    detail:
      "Volverás a la aplicación donde comenzaste y podrás iniciar sesión con tu cuenta.",
    security:
      "Este enlace es personal, puede usarse una sola vez y vence en 60 minutos. Si no creaste esta cuenta, ignora el mensaje.",
  },
  {
    key: "invite",
    category: "template",
    file: "auth_invite.html",
    subject: "Te invitaron a Viñabike: configura tu acceso",
    title: "Tu acceso está listo",
    preheader: "Acepta la invitación y configura tu contraseña de acceso.",
    eyebrow: "INVITACIÓN",
    lead:
      "Se creó una invitación para <strong class=\"breakable\">{{ .Email }}</strong>. Usa el botón para configurar tu acceso de forma segura.",
    action: {
      label: "Configurar mi acceso",
      href: actionLinks.invite,
    },
    detailTitle: "Qué ocurrirá",
    detail:
      "Abrirás una pantalla segura para definir tu contraseña. Al terminar, la invitación quedará consumida.",
    security:
      "El enlace es personal, de un solo uso y vence en 60 minutos. Si no esperabas esta invitación, no lo abras ni lo compartas.",
  },
  {
    key: "recovery",
    category: "template",
    file: "auth_recovery.html",
    subject: "Crea una nueva contraseña para tu cuenta Viñabike",
    title: "Restablece tu contraseña",
    preheader:
      "Usa este enlace de un solo uso para crear una contraseña nueva.",
    eyebrow: "RECUPERACIÓN DE ACCESO",
    lead:
      "Recibimos una solicitud para cambiar la contraseña de <strong class=\"breakable\">{{ .Email }}</strong>.",
    action: {
      label: "Crear una contraseña nueva",
      href: actionLinks.recovery,
    },
    detailTitle: "Qué ocurrirá",
    detail:
      "Abrirás la pantalla segura de recuperación. Tu contraseña actual seguirá vigente hasta que completes el cambio.",
    security:
      "El enlace es personal, de un solo uso y vence en 60 minutos. Si no pediste el cambio, ignora este mensaje.",
  },
  {
    key: "magic_link",
    category: "template",
    file: "auth_magic_link.html",
    subject: "Tu enlace de acceso seguro a Viñabike",
    title: "Inicia sesión de forma segura",
    preheader:
      "Usa este enlace personal para ingresar sin escribir tu contraseña.",
    eyebrow: "ENLACE DE ACCESO",
    lead:
      "Solicitaste un enlace para iniciar sesión como <strong class=\"breakable\">{{ .Email }}</strong>.",
    action: {
      label: "Iniciar sesión",
      href: actionLinks.confirmation,
    },
    detailTitle: "Antes de continuar",
    detail:
      "Abre el enlace en el mismo dispositivo donde solicitaste el acceso y cierra esta ventana cuando termines.",
    security:
      "El enlace es personal, de un solo uso y vence en 60 minutos. Si no lo solicitaste, ignora el mensaje.",
  },
  {
    key: "email_change",
    category: "template",
    file: "auth_email_change.html",
    subject: "Confirma tu nuevo correo de acceso a Viñabike",
    title: "Confirma tu nuevo correo",
    preheader:
      "Confirma la nueva dirección antes de usarla para iniciar sesión.",
    eyebrow: "CAMBIO DE CORREO",
    lead:
      "Confirma que deseas usar <strong class=\"breakable\">{{ .NewEmail }}</strong> como correo de acceso a tu cuenta.",
    action: {
      label: "Confirmar nuevo correo",
      href: actionLinks.confirmation,
    },
    detailTitle: "Protección adicional",
    detail:
      "Viñabike utiliza confirmación segura del cambio. Según el estado de tu cuenta, también podrías recibir un aviso en la dirección anterior.",
    security:
      "El enlace vence en 60 minutos. Si no solicitaste este cambio, no lo abras y revisa la seguridad de tu cuenta.",
  },
  {
    key: "reauthentication",
    category: "template",
    file: "auth_reauthentication.html",
    subject: "Tu código de verificación de Viñabike",
    title: "Verifica que eres tú",
    preheader:
      "Ingresa el código en Viñabike para autorizar el cambio sensible.",
    eyebrow: "VERIFICACIÓN DE SEGURIDAD",
    lead:
      "Antes de cambiar información sensible de tu cuenta, necesitamos comprobar que eres tú.",
    code: "{{ .Token }}",
    detailTitle: "Cómo usarlo",
    detail:
      "Vuelve a la pantalla donde solicitaste el cambio e ingresa este código de 6 dígitos.",
    security:
      "El código vence en 60 minutos y sólo sirve una vez. Viñabike nunca te lo pedirá por teléfono, chat o redes sociales.",
  },
  {
    key: "password_changed",
    category: "notification",
    file: "auth_password_changed.html",
    subject: "Aviso de seguridad: tu contraseña cambió",
    title: "Tu contraseña fue actualizada",
    preheader:
      "Te avisamos porque la contraseña de tu cuenta Viñabike cambió.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "La contraseña de <strong class=\"breakable\">{{ .Email }}</strong> se actualizó correctamente.",
    detailTitle: "Si fuiste tú",
    detail:
      "No necesitas hacer nada. Usa la contraseña nueva en tu próximo inicio de sesión.",
    security:
      "Si no reconoces el cambio, solicita de inmediato un restablecimiento desde la pantalla de acceso y contacta a soporte.",
    danger: true,
  },
  {
    key: "email_changed",
    category: "notification",
    file: "auth_email_changed.html",
    subject: "Aviso de seguridad: tu correo de acceso cambió",
    title: "Tu correo de acceso cambió",
    preheader:
      "La dirección usada para iniciar sesión en Viñabike fue modificada.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "El correo de tu cuenta cambió de <strong class=\"breakable\">{{ .OldEmail }}</strong> a <strong class=\"breakable\">{{ .Email }}</strong>.",
    detailTitle: "Desde ahora",
    detail:
      "Usa la dirección nueva para iniciar sesión y recibir mensajes de seguridad.",
    security:
      "Si no reconoces el cambio, contacta a soporte de inmediato para proteger tu cuenta.",
    danger: true,
  },
  {
    key: "phone_changed",
    category: "notification",
    file: "auth_phone_changed.html",
    subject: "Aviso de seguridad: tu teléfono cambió",
    title: "Tu teléfono de acceso cambió",
    preheader:
      "El número asociado a la seguridad de tu cuenta Viñabike fue modificado.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "El teléfono de tu cuenta cambió de <strong class=\"breakable\">{{ .OldPhone }}</strong> a <strong class=\"breakable\">{{ .Phone }}</strong>.",
    detailTitle: "Desde ahora",
    detail:
      "El número nuevo se utilizará en los flujos de acceso o verificación que correspondan.",
    security:
      "Si no reconoces el cambio, contacta a soporte de inmediato para proteger tu cuenta.",
    danger: true,
  },
  {
    key: "identity_linked",
    category: "notification",
    file: "auth_identity_linked.html",
    subject: "Aviso de seguridad: vinculaste un método de acceso",
    title: "Nuevo método de acceso",
    preheader:
      "Se vinculó un nuevo método para ingresar a tu cuenta Viñabike.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "Se vinculó <strong class=\"breakable\">{{ .Provider }}</strong> a la cuenta <strong class=\"breakable\">{{ .Email }}</strong>.",
    detailTitle: "Qué significa",
    detail:
      "Desde ahora ese proveedor también puede utilizarse para iniciar sesión en tu cuenta.",
    security:
      "Si no reconoces esta acción, restablece tu contraseña y contacta a soporte de inmediato.",
    danger: true,
  },
  {
    key: "identity_unlinked",
    category: "notification",
    file: "auth_identity_unlinked.html",
    subject: "Aviso de seguridad: desvinculaste un método de acceso",
    title: "Método de acceso desvinculado",
    preheader:
      "Un método para ingresar a tu cuenta Viñabike fue eliminado.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "Se desvinculó <strong class=\"breakable\">{{ .Provider }}</strong> de la cuenta <strong class=\"breakable\">{{ .Email }}</strong>.",
    detailTitle: "Qué significa",
    detail:
      "Ese proveedor ya no puede utilizarse para iniciar sesión. Tus otros métodos de acceso no cambian.",
    security:
      "Si no reconoces esta acción, revisa la seguridad de tu cuenta y contacta a soporte.",
    danger: true,
  },
  {
    key: "mfa_factor_enrolled",
    category: "notification",
    file: "auth_mfa_factor_enrolled.html",
    subject: "Aviso de seguridad: agregaste una verificación adicional",
    title: "Verificación adicional activada",
    preheader:
      "Se agregó una capa adicional de seguridad a tu cuenta Viñabike.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "Se agregó el método <strong class=\"breakable\">{{ .FactorType }}</strong> como verificación adicional de tu cuenta.",
    detailTitle: "Qué significa",
    detail:
      "Viñabike podrá solicitar este segundo paso al iniciar sesión o autorizar acciones sensibles.",
    security:
      "Si no configuraste este método, revisa la seguridad de tu cuenta y contacta a soporte de inmediato.",
    danger: true,
  },
  {
    key: "mfa_factor_unenrolled",
    category: "notification",
    file: "auth_mfa_factor_unenrolled.html",
    subject: "Aviso de seguridad: eliminaste una verificación adicional",
    title: "Verificación adicional eliminada",
    preheader:
      "Se quitó una capa adicional de seguridad de tu cuenta Viñabike.",
    eyebrow: "AVISO DE SEGURIDAD",
    lead:
      "Se eliminó el método <strong class=\"breakable\">{{ .FactorType }}</strong> de la verificación adicional de tu cuenta.",
    detailTitle: "Qué significa",
    detail:
      "Ese método ya no se solicitará como segundo paso de seguridad.",
    security:
      "Si no realizaste esta acción, protege tu cuenta y contacta a soporte de inmediato.",
    danger: true,
  },
];

function renderAction(action) {
  if (!action) return "";
  return `
                <table role="presentation" cellspacing="0" cellpadding="0" class="action-table" style="border-collapse:separate;margin:28px 0 18px;">
                  <tr>
                    <td class="button-cell" bgcolor="#0B6FCB" style="border-radius:9px;text-align:center;">
                      <a class="button-link" href="${action.href}" style="box-sizing:border-box;display:inline-block;min-height:48px;padding:14px 24px;color:#FFFFFF;font-size:15px;font-weight:700;line-height:20px;text-align:center;text-decoration:none;">
                        ${action.label}
                      </a>
                    </td>
                  </tr>
                </table>
                <p style="margin:0 0 26px;color:#657783;font-size:12px;line-height:19px;">
                  Si el botón no responde, <a class="breakable" href="${action.href}" style="color:#0B6FCB;font-weight:700;text-decoration:underline;">abre este enlace seguro</a>.
                </p>`;
}

function renderCode(code) {
  if (!code) return "";
  return `
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:separate;margin:26px 0 24px;table-layout:fixed;">
                  <tr>
                    <td align="center" style="padding:18px 12px;background:#F1F6FA;border:1px solid #D8E5EF;border-radius:12px;">
                      <div style="margin:0 0 7px;color:#657783;font-size:11px;font-weight:700;letter-spacing:1.1px;text-transform:uppercase;">Código de 6 dígitos</div>
                      <div style="color:#102A3A;font-family:'SFMono-Regular',Consolas,'Liberation Mono',monospace;font-size:32px;font-weight:800;letter-spacing:8px;line-height:40px;">${code}</div>
                    </td>
                  </tr>
                </table>`;
}

export function renderAuthEmail(definition) {
  const warningColor = definition.danger ? "#9F3A38" : "#315C76";
  const warningBackground = definition.danger ? "#FFF6F5" : "#F4F8FB";
  const warningBorder = definition.danger ? "#F0D3D0" : "#D8E5EF";

  return `<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="format-detection" content="telephone=no,date=no,address=no,email=no">
    <meta name="color-scheme" content="light">
    <meta name="supported-color-schemes" content="light">
    <title>${definition.title}</title>
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
      ${definition.preheader}
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
                      <div style="color:#102A3A;font-size:18px;font-weight:800;letter-spacing:.1px;line-height:22px;">Viñabike</div>
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
                <div style="margin:0 0 10px;color:#0B6FCB;font-size:11px;font-weight:800;letter-spacing:1.2px;line-height:16px;">${definition.eyebrow}</div>
                <h1 style="margin:0 0 17px;color:#102A3A;font-size:28px;font-weight:760;line-height:35px;">${definition.title}</h1>
                <p style="margin:0;color:#3C4D57;font-size:15px;line-height:24px;">${definition.lead}</p>
${renderCode(definition.code)}
${renderAction(definition.action)}
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin-top:${definition.action || definition.code ? "0" : "24px"};background:#F6F9FB;border-collapse:separate;border-radius:12px;table-layout:fixed;">
                  <tr>
                    <td style="padding:16px 18px;overflow-wrap:anywhere;word-break:break-word;">
                      <div style="margin:0 0 5px;color:#102A3A;font-size:13px;font-weight:750;line-height:18px;">${definition.detailTitle}</div>
                      <div style="color:#586A75;font-size:13px;line-height:20px;">${definition.detail}</div>
                    </td>
                  </tr>
                </table>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin-top:16px;background:${warningBackground};border:1px solid ${warningBorder};border-collapse:separate;border-radius:12px;table-layout:fixed;">
                  <tr>
                    <td width="38" valign="top" style="width:38px;padding:16px 0 16px 16px;color:${warningColor};font-size:18px;font-weight:800;line-height:20px;">!</td>
                    <td valign="top" style="padding:16px 16px 16px 4px;color:${warningColor};font-size:12px;line-height:19px;overflow-wrap:anywhere;word-break:break-word;">
                      ${definition.security}
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td class="footer-cell" style="padding:19px 38px 24px;border-top:1px solid #E7EDF1;color:#7A8992;font-size:11px;line-height:17px;overflow-wrap:anywhere;word-break:break-word;">
                Este es un mensaje automático de seguridad de Viñabike. Nunca te pediremos tu contraseña ni este código por correo, teléfono, chat o redes sociales. Si necesitas ayuda, escribe a <a href="mailto:contacto@vinabike.cl" style="color:#315C76;text-decoration:underline;">contacto@vinabike.cl</a>.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
`;
}

export function expectedTemplateFiles() {
  return new Map(
    authEmailDefinitions.map((definition) => [
      definition.file,
      renderAuthEmail(definition),
    ]),
  );
}

export function writeTemplates({ check = false } = {}) {
  const mismatches = [];
  for (const [file, expected] of expectedTemplateFiles()) {
    const target = path.join(templateRoot, file);
    const current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : null;
    if (current === expected) continue;
    if (check) {
      mismatches.push(file);
      continue;
    }
    fs.writeFileSync(target, expected, "utf8");
  }
  assert.deepEqual(
    mismatches,
    [],
    `Generated Auth email templates are stale: ${mismatches.join(", ")}`,
  );
}

const invokedAsMain =
  process.argv[1] && path.resolve(process.argv[1]) === scriptPath;
if (invokedAsMain) {
  const unexpected = process.argv.slice(2).filter((value) => value !== "--check");
  assert.deepEqual(unexpected, [], `Unexpected arguments: ${unexpected.join(", ")}`);
  const check = process.argv.includes("--check");
  writeTemplates({ check });
  console.log(
    JSON.stringify({
      mode: check ? "check" : "generate",
      templateCount: authEmailDefinitions.length,
      output: path.relative(projectRoot, templateRoot),
    }),
  );
}
