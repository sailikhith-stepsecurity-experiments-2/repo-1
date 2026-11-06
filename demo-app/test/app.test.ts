import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";

describe("orders-api", () => {
  it("reports health", async () => {
    const res = await request(createApp()).get("/healthz");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
  });

  it("creates an order and computes the total", async () => {
    const app = createApp();
    const res = await request(app)
      .post("/orders")
      .send({ customer: "acme", items: [{ sku: "A1", quantity: 3, unitPrice: 2.5 }, { sku: "B2", quantity: 1, unitPrice: 10 }] });
    expect(res.status).toBe(201);
    expect(res.body.total).toBe(17.5);

    const fetched = await request(app).get(`/orders/${res.body.id}`);
    expect(fetched.body.customer).toBe("acme");
  });

  it("rejects an invalid order", async () => {
    const res = await request(createApp()).post("/orders").send({ customer: "", items: [] });
    expect(res.status).toBe(400);
  });

  it("returns 404 for a missing order", async () => {
    const res = await request(createApp()).get("/orders/999");
    expect(res.status).toBe(404);
  });
});
