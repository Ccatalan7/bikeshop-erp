import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
  MagickGeometry,
} from "npm:@imagemagick/magick-wasm@0.0.35";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const bucket = "vinabike-assets";
const sourcePrefix = "website/media/sources/";
const outputPrefix = "website/media/";
const maxSourceBytes = 6 * 1024 * 1024;
const maxLongEdge = 1920;
const webQuality = 84;
const thumbnailLongEdge = 420;
const thumbnailQuality = 74;

const wasmBytes = await Deno.readFile(
  new URL(
    "magick.wasm",
    import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.35"),
  ),
);
await initializeImageMagick(wasmBytes);

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function cleanText(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function safeSourcePath(value: unknown) {
  const path = cleanText(value);
  return path.startsWith(sourcePrefix) &&
      !path.includes("..") &&
      !path.includes("\\") &&
      path.length <= 500
    ? path
    : "";
}

function safeFileStem(value: unknown) {
  const raw = cleanText(value).replace(/\.[^.]+$/, "");
  const normalized = raw
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
  return (normalized || "website-image").slice(0, 72);
}

function plainMetadata(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {} as Record<string, string | number | boolean>;
  }
  const result: Record<string, string | number | boolean> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (
      typeof raw === "string" ||
      typeof raw === "number" ||
      typeof raw === "boolean"
    ) {
      result[key.slice(0, 64)] = typeof raw === "string" ? raw.slice(0, 500) : raw;
    }
  }
  return result;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return jsonResponse({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Server configuration is incomplete" }, 500);
  }

  try {
    const body = await req.json() as Record<string, unknown>;
    const sourcePath = safeSourcePath(body.sourcePath);
    if (!sourcePath) {
      return jsonResponse({ error: "Invalid Website Builder source path" }, 400);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: profile, error: profileError } = await adminClient
      .from("user_profiles")
      .select("tenant_id, role")
      .eq("user_id", user.id)
      .maybeSingle();
    const role = cleanText(profile?.role);
    if (profileError || !profile?.tenant_id) {
      return jsonResponse({ error: "Unable to resolve user tenant" }, 400);
    }
    if (!["owner", "admin", "manager"].includes(role)) {
      return jsonResponse({ error: "Insufficient permissions" }, 403);
    }
    const tenantId = String(profile.tenant_id);
    if (!sourcePath.startsWith(`${sourcePrefix}${tenantId}/`)) {
      return jsonResponse({ error: "Tenant source mismatch" }, 403);
    }

    const { data: sourceBlob, error: downloadError } = await adminClient.storage
      .from(bucket)
      .download(sourcePath);
    if (downloadError || !sourceBlob) {
      console.error("[website-optimize-image] source download failed", downloadError);
      return jsonResponse({ error: "Unable to read the source image" }, 400);
    }
    const sourceBytes = new Uint8Array(await sourceBlob.arrayBuffer());
    if (sourceBytes.length === 0 || sourceBytes.length > maxSourceBytes) {
      return jsonResponse(
        { error: "The prepared source image exceeds the safe processing limit" },
        413,
      );
    }

    let conversion: {
      optimized: Uint8Array;
      thumbnail: Uint8Array;
      width: number;
      height: number;
    };
    try {
      conversion = ImageMagick.read(sourceBytes, (image) => {
        image.autoOrient();
        if (image.width > maxLongEdge || image.height > maxLongEdge) {
          const geometry = new MagickGeometry(maxLongEdge, maxLongEdge);
          geometry.greater = true;
          image.resize(geometry);
        }
        image.removeProfile("exif");
        image.removeProfile("iptc");
        image.removeProfile("xmp");
        image.settings.setDefine(MagickFormat.WebP, "method", 6);
        image.settings.setDefine(MagickFormat.WebP, "alpha-quality", 92);
        image.quality = webQuality;
        const width = image.width;
        const height = image.height;
        const optimized = image.write(
          MagickFormat.WebP,
          (data) => Uint8Array.from(data),
        );

        if (
          image.width > thumbnailLongEdge ||
          image.height > thumbnailLongEdge
        ) {
          const thumbnailGeometry = new MagickGeometry(
            thumbnailLongEdge,
            thumbnailLongEdge,
          );
          thumbnailGeometry.greater = true;
          image.resize(thumbnailGeometry);
        }
        image.quality = thumbnailQuality;
        const thumbnail = image.write(
          MagickFormat.WebP,
          (data) => Uint8Array.from(data),
        );
        return { optimized, thumbnail, width, height };
      });
    } catch (error) {
      console.error("[website-optimize-image] conversion failed", error);
      return jsonResponse({ error: "Unable to optimize this image" }, 422);
    }
    if (
      conversion.optimized.length === 0 ||
      conversion.optimized.length > maxSourceBytes ||
      conversion.thumbnail.length === 0
    ) {
      return jsonResponse({ error: "The optimized image is not valid" }, 422);
    }
    const { optimized, thumbnail, width, height } = conversion;

    const fileStem = safeFileStem(body.fileName);
    const assetId = crypto.randomUUID();
    const outputName = `${fileStem}-${assetId}-web.webp`;
    const tenantOutputPrefix = `${outputPrefix}${tenantId}/`;
    const outputPath = `${tenantOutputPrefix}${outputName}`;
    const thumbnailName = `${fileStem}-${assetId}-thumb.webp`;
    const thumbnailPath = `${tenantOutputPrefix}thumbnails/${thumbnailName}`;
    const sourceUrl = cleanText(body.sourceUrl);
    const originalUrl = cleanText(body.originalUrl);
    const operation = cleanText(body.operation) || "upload";
    const sourceMetadata = plainMetadata(body.sourceMetadata);
    const storageMetadata: Record<string, string | number | boolean> = {
      website_variant: "web",
      tenant_id: tenantId,
      source_path: sourcePath,
      source_url: sourceUrl,
      operation,
      original_url: originalUrl,
      source_bytes: sourceBytes.length,
      web_bytes: optimized.length,
      width,
      height,
      quality: webQuality,
      ...sourceMetadata,
    };
    const { data: thumbnailPublicData } = adminClient.storage
      .from(bucket)
      .getPublicUrl(thumbnailPath);
    storageMetadata.thumbnail_path = thumbnailPath;
    storageMetadata.thumbnail_url = thumbnailPublicData.publicUrl;
    storageMetadata.thumbnail_bytes = thumbnail.length;

    const { error: thumbnailUploadError } = await adminClient.storage
      .from(bucket)
      .upload(thumbnailPath, thumbnail, {
        contentType: "image/webp",
        cacheControl: "31536000",
        upsert: false,
        metadata: {
          website_variant: "thumbnail",
          tenant_id: tenantId,
          source_path: sourcePath,
          operation,
          width: Math.min(width, thumbnailLongEdge),
          quality: thumbnailQuality,
        },
      });
    if (thumbnailUploadError) {
      console.error(
        "[website-optimize-image] thumbnail upload failed",
        thumbnailUploadError,
      );
      return jsonResponse({ error: "Unable to store the image preview" }, 500);
    }

    const { error: uploadError } = await adminClient.storage
      .from(bucket)
      .upload(outputPath, optimized, {
        contentType: "image/webp",
        cacheControl: "31536000",
        upsert: false,
        metadata: storageMetadata,
      });
    if (uploadError) {
      console.error("[website-optimize-image] output upload failed", uploadError);
      await adminClient.storage.from(bucket).remove([thumbnailPath]);
      return jsonResponse({ error: "Unable to store the optimized image" }, 500);
    }

    const { data: publicData } = adminClient.storage
      .from(bucket)
      .getPublicUrl(outputPath);
    return jsonResponse({
      name: outputName,
      path: outputPath,
      publicUrl: publicData.publicUrl,
      thumbnailPath,
      thumbnailUrl: thumbnailPublicData.publicUrl,
      sourcePath,
      sourceUrl,
      width,
      height,
      sourceBytes: sourceBytes.length,
      webBytes: optimized.length,
      thumbnailBytes: thumbnail.length,
      quality: webQuality,
      format: "webp",
    });
  } catch (error) {
    console.error("[website-optimize-image] unexpected error", error);
    return jsonResponse({ error: "Unable to optimize image" }, 400);
  }
});

export { cleanText, plainMetadata, safeFileStem, safeSourcePath };
