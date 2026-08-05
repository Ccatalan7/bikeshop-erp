import { ProviderError } from "./provider.ts";

const DEFAULT_MAX_PROVIDER_RESPONSE_BYTES = 2 * 1024 * 1024;

export async function readProviderJson(
  response: Response,
  signal: AbortSignal,
  maxBytes = DEFAULT_MAX_PROVIDER_RESPONSE_BYTES,
): Promise<unknown> {
  const contentLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    await discardProviderBody(response);
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new ProviderError("provider_invalid_response", 502, false);
  const abortReader = () => {
    void reader.cancel("provider_timeout").catch(() => {});
  };
  signal.addEventListener("abort", abortReader, { once: true });
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      if (signal.aborted) throw new ProviderError("provider_unavailable", 503, true);
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel("provider_response_too_large");
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof ProviderError) throw error;
    throw new ProviderError(
      signal.aborted ? "provider_unavailable" : "provider_invalid_response",
      signal.aborted ? 503 : 502,
      signal.aborted,
    );
  } finally {
    signal.removeEventListener("abort", abortReader);
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const raw = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(raw);
  } catch (_) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
}

export async function discardProviderBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch (_) {
    // Upstream error details are deliberately neither parsed nor logged.
  }
}
