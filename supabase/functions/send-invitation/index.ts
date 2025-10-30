// Supabase Edge Function: Send Employee Invitation Email
// Triggered by HR module when granting system access to employees

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface InvitationRequest {
  invitationId: string;
}

interface InvitationData {
  id: string;
  email: string;
  role: string;
  tenant_id: string;
  metadata: {
    first_name: string;
    last_name: string;
  };
  tenants: {
    shop_name: string;
    subdomain: string;
  };
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // Only allow POST requests
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // Parse request body
    const { invitationId }: InvitationRequest = await req.json();

    if (!invitationId) {
      return new Response(JSON.stringify({ error: "invitationId is required" }), {
        status: 400,
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // Create Supabase client with service role (bypasses RLS)
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fetch invitation data with tenant info
    const { data: invitation, error: fetchError } = await supabase
      .from("user_invitations")
      .select(`
        id,
        email,
        role,
        tenant_id,
        metadata,
        tenants (
          shop_name,
          subdomain
        )
      `)
      .eq("id", invitationId)
      .single();

    if (fetchError) {
      console.error("❌ Error fetching invitation:", fetchError);
      return new Response(
        JSON.stringify({ 
          error: "Failed to fetch invitation", 
          details: fetchError.message,
          code: fetchError.code 
        }),
        { 
          status: 404, 
          headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    if (!invitation) {
      console.error("❌ Invitation not found for ID:", invitationId);
      return new Response(
        JSON.stringify({ error: "Invitation not found" }),
        { 
          status: 404, 
          headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    console.log("✅ Invitation found:", invitation.email, "Role:", invitation.role);

    const invitationData = invitation as unknown as InvitationData;

    // Generate invitation token (secure random string)
    const token = crypto.randomUUID();
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7); // 7 days expiration

    // Update invitation with token
    const { error: updateError } = await supabase
      .from("user_invitations")
      .update({ 
        metadata: {
          ...invitationData.metadata,
          invitation_token: token,
        },
        expires_at: expiresAt.toISOString(),
      })
      .eq("id", invitationId);

    if (updateError) {
      console.error("❌ Error updating invitation with token:", updateError);
      return new Response(
        JSON.stringify({ 
          error: "Failed to update invitation", 
          details: updateError.message 
        }),
        { 
          status: 500, 
          headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    console.log("✅ Invitation updated with token");

    // Build invitation link
    // Use redirect page to handle email client issues with hash routes
    let baseUrl = Deno.env.get("APP_URL") || "https://project-vinabike.web.app";
    
    // If request has origin header, use it for local development
    const origin = req.headers.get("origin");
    if (origin && (origin.includes("localhost") || origin.includes("127.0.0.1"))) {
      baseUrl = origin;
    }
    
    // Use path-based URL that redirects to hash route (email-safe)
    const invitationLink = `${baseUrl}/accept-invitation.html?token=${token}`;

    // Build email content
    const firstName = invitationData.metadata.first_name;
    const shopName = invitationData.tenants.shop_name;
    const roleDisplay = getRoleDisplayName(invitationData.role);

    const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #2196F3; color: white; padding: 20px; text-align: center; }
    .content { padding: 30px 20px; background: #f9f9f9; }
    .button { display: inline-block; padding: 12px 30px; background: #2196F3; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; }
    .footer { padding: 20px; text-align: center; font-size: 12px; color: #666; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚴 Invitación al Sistema</h1>
    </div>
    <div class="content">
      <p>Hola ${firstName},</p>
      <p>Has sido invitado a unirte al sistema de <strong>${shopName}</strong> con el rol de <strong>${roleDisplay}</strong>.</p>
      <p>Para aceptar esta invitación y configurar tu cuenta, haz clic en el siguiente botón:</p>
      <div style="text-align: center;">
        <a href="${invitationLink}" class="button">Aceptar Invitación</a>
      </div>
      <p style="font-size: 12px; color: #666;">
        O copia y pega este enlace en tu navegador:<br>
        <a href="${invitationLink}">${invitationLink}</a>
      </p>
      <p style="font-size: 12px; color: #666;">
        Esta invitación expira el ${expiresAt.toLocaleDateString('es-CL')}.
      </p>
    </div>
    <div class="footer">
      <p>Este es un correo automático, por favor no respondas.</p>
      <p>&copy; ${new Date().getFullYear()} ${shopName}. Todos los derechos reservados.</p>
    </div>
  </div>
</body>
</html>
    `;

    // Send email using Resend API
    // Free tier: 3,000 emails/month, 100 emails/day
    // Sign up at https://resend.com and get API key
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    
    if (!resendApiKey) {
      console.error("⚠️ RESEND_API_KEY not configured. Logging invitation link instead.");
      console.log("========================================");
      console.log("📧 INVITATION EMAIL (would be sent to):", invitationData.email);
      console.log("🔗 Invitation Link:", invitationLink);
      console.log("========================================");
      
      // Return success but indicate email wasn't sent
      return new Response(
        JSON.stringify({ 
          success: true,
          message: "Invitation created (email service not configured - check logs for link)",
          invitationId,
          invitationLink, // Include link in response for debugging
          expiresAt: expiresAt.toISOString(),
        }),
        { 
          status: 200, 
          headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Vinabike <noreply@yourdomain.com>", // TODO: Replace yourdomain.com with your actual domain
        to: [invitationData.email],
        subject: `Invitación al Sistema - ${shopName}`,
        html: emailHtml,
      }),
    });

    if (!emailResponse.ok) {
      const errorData = await emailResponse.text();
      console.error("❌ Error sending email via Resend:", errorData);
      
      // Email failed, but still return link for manual sharing
      console.log("🔗 Returning invitation link for manual sharing:", invitationLink);
      return new Response(
        JSON.stringify({ 
          success: false,
          error: "Failed to send email", 
          details: errorData,
          invitationLink, // ✅ Include link even when email fails
          invitationId,
          expiresAt: expiresAt.toISOString(),
        }),
        { 
          status: 200, // Changed to 200 so UI can still get the link
          headers: { 
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    console.log("✅ Email sent successfully via Resend");
    console.log("🔗 Invitation link:", invitationLink);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Invitation email sent successfully",
        invitationId,
        invitationLink, // ✅ ALWAYS include link (for UI dialog)
        expiresAt: expiresAt.toISOString(),
      }),
      { 
        status: 200, 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );

  } catch (error) {
    console.error("❌ Unexpected error:", error);
    console.error("❌ Error stack:", error instanceof Error ? error.stack : 'No stack trace');
    console.error("❌ Error message:", error instanceof Error ? error.message : String(error));
    
    return new Response(
      JSON.stringify({ 
        error: "Internal server error", 
        details: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined
      }),
      { 
        status: 500, 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});

function getRoleDisplayName(role: string): string {
  const roleMap: Record<string, string> = {
    admin: "Administrador",
    manager: "Gerente",
    cashier: "Cajero",
    mechanic: "Mecánico",
    accountant: "Contador",
  };
  return roleMap[role] || role;
}
