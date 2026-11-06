import express from "express";
import { OrderInput, OrderStore } from "./orders.js";

export function createApp(store = new OrderStore()) {
  const app = express();
  app.use(express.json());

  app.get("/healthz", (_req, res) => {
    res.json({ ok: true });
  });

  app.post("/orders", (req, res) => {
    const parsed = OrderInput.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.issues });
      return;
    }
    res.status(201).json(store.create(parsed.data));
  });

  app.get("/orders/:id", (req, res) => {
    const order = store.get(Number(req.params.id));
    if (!order) {
      res.status(404).json({ error: "not found" });
      return;
    }
    res.json(order);
  });

  return app;
}
