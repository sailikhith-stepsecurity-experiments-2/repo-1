import { z } from "zod";

export const OrderInput = z.object({
  customer: z.string().min(1),
  items: z
    .array(
      z.object({
        sku: z.string().min(1),
        quantity: z.number().int().positive(),
        unitPrice: z.number().nonnegative(),
      })
    )
    .min(1),
});

export type OrderInput = z.infer<typeof OrderInput>;

export interface Order extends OrderInput {
  id: number;
  total: number;
}

export class OrderStore {
  private orders: Order[] = [];

  create(input: OrderInput): Order {
    const total = input.items.reduce((sum, i) => sum + i.quantity * i.unitPrice, 0);
    const order: Order = { ...input, id: this.orders.length + 1, total: Math.round(total * 100) / 100 };
    this.orders.push(order);
    return order;
  }

  get(id: number): Order | undefined {
    return this.orders.find((o) => o.id === id);
  }
}
