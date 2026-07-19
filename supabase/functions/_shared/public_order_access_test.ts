import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authorizePublicOrderAccess,
  normalizePublicOrderAccessInput,
  PublicOrderAccessDeniedError,
} from "./public_order_access.ts";

const orderId = "97000000-0000-4000-8000-000000000010";
const token = "a".repeat(43);

Deno.test("normalizes an order id and opaque access token", () => {
  assertEquals(
    normalizePublicOrderAccessInput({
      order_id: orderId.toUpperCase(),
      order_access_token: ` ${token} `,
    }),
    {
      orderId,
      orderAccessToken: token,
    },
  );
});

Deno.test("rejects missing, short or URL-shaped credentials", () => {
  for (
    const value of [
      {},
      { order_id: orderId, order_access_token: "short" },
      { order_id: orderId, order_access_token: `https://example.com/${token}` },
      { order_id: "not-an-order", order_access_token: token },
    ]
  ) {
    try {
      normalizePublicOrderAccessInput(value);
      throw new Error("Expected access denial");
    } catch (error) {
      assertEquals(error instanceof PublicOrderAccessDeniedError, true);
    }
  }
});

Deno.test("authorizes only a token projection bound to the requested order", async () => {
  const calls: Array<{ name: string; params: Record<string, unknown> }> = [];
  const result = await authorizePublicOrderAccess({
    rpc(name, params) {
      calls.push({ name, params });
      return Promise.resolve({
        data: { order: { id: orderId, total: 990 }, items: [] },
        error: null,
      });
    },
  }, {
    order_id: orderId,
    order_access_token: token,
  });

  assertEquals(result.orderId, orderId);
  assertEquals(calls, [{
    name: "get_public_online_order_by_access_token",
    params: { p_token: token },
  }]);
});

Deno.test("rejects RPC errors and cross-order tokens", async () => {
  await assertRejects(
    () =>
      authorizePublicOrderAccess({
        rpc() {
          return Promise.resolve({ data: null, error: { message: "not found" } });
        },
      }, { order_id: orderId, order_access_token: token }),
    PublicOrderAccessDeniedError,
  );

  await assertRejects(
    () =>
      authorizePublicOrderAccess({
        rpc() {
          return Promise.resolve({
            data: {
              order: { id: "97000000-0000-4000-8000-000000000011" },
            },
            error: null,
          });
        },
      }, { order_id: orderId, order_access_token: token }),
    PublicOrderAccessDeniedError,
  );
});
