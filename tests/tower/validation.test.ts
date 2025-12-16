import { describe, it } from "vitest";
import assert from "node:assert/strict";
import {
  StartInputSchema,
  ClimbInputSchema,
  CashoutInputSchema,
} from "../../src/plugins/tower.ts";

const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";

describe("StartInputSchema", () => {
  const validInput = {
    wager: 100,
    currency: "USD",
    doors: 2,
    hashChainId: VALID_UUID,
    clientSeed: "test-seed",
  };

  it("accepts valid input", () => {
    const result = StartInputSchema.safeParse(validInput);
    assert.equal(result.success, true);
  });

  it("rejects wager < 1", () => {
    const result = StartInputSchema.safeParse({ ...validInput, wager: 0 });
    assert.equal(result.success, false);
  });

  it("rejects negative wager", () => {
    const result = StartInputSchema.safeParse({ ...validInput, wager: -10 });
    assert.equal(result.success, false);
  });

  it("rejects non-integer wager", () => {
    const result = StartInputSchema.safeParse({ ...validInput, wager: 10.5 });
    assert.equal(result.success, false);
  });

  it("rejects empty currency", () => {
    const result = StartInputSchema.safeParse({ ...validInput, currency: "" });
    assert.equal(result.success, false);
  });

  it("rejects invalid doors", () => {
    // doors must be between 2 and 4
    const result1 = StartInputSchema.safeParse({ ...validInput, doors: 1 });
    assert.equal(result1.success, false);

    const result5 = StartInputSchema.safeParse({ ...validInput, doors: 5 });
    assert.equal(result5.success, false);

    // doors 2-4 are valid
    const result2 = StartInputSchema.safeParse({ ...validInput, doors: 2 });
    assert.equal(result2.success, true);
    const result3 = StartInputSchema.safeParse({ ...validInput, doors: 3 });
    assert.equal(result3.success, true);
    const result4 = StartInputSchema.safeParse({ ...validInput, doors: 4 });
    assert.equal(result4.success, true);
  });

  it("rejects invalid hashChainId", () => {
    const result = StartInputSchema.safeParse({
      ...validInput,
      hashChainId: "not-a-uuid",
    });
    assert.equal(result.success, false);
  });

  it("rejects empty clientSeed", () => {
    const result = StartInputSchema.safeParse({
      ...validInput,
      clientSeed: "",
    });
    assert.equal(result.success, false);
  });
});

describe("ClimbInputSchema", () => {
  const validInput = {
    gameId: VALID_UUID,
    door: 0,
    clientSeed: "test-seed",
  };

  it("accepts valid input", () => {
    const result = ClimbInputSchema.safeParse(validInput);
    assert.equal(result.success, true);
  });

  it("accepts door = 0", () => {
    const result = ClimbInputSchema.safeParse({ ...validInput, door: 0 });
    assert.equal(result.success, true);
  });

  it("accepts door = 1", () => {
    const result = ClimbInputSchema.safeParse({ ...validInput, door: 1 });
    assert.equal(result.success, true);
  });

  it("rejects negative door", () => {
    const result = ClimbInputSchema.safeParse({ ...validInput, door: -1 });
    assert.equal(result.success, false);
  });

  it("rejects invalid gameId", () => {
    const result = ClimbInputSchema.safeParse({
      ...validInput,
      gameId: "not-a-uuid",
    });
    assert.equal(result.success, false);
  });

  it("rejects empty clientSeed", () => {
    const result = ClimbInputSchema.safeParse({
      ...validInput,
      clientSeed: "",
    });
    assert.equal(result.success, false);
  });
});

describe("CashoutInputSchema", () => {
  it("accepts valid gameId", () => {
    const result = CashoutInputSchema.safeParse({ gameId: VALID_UUID });
    assert.equal(result.success, true);
  });

  it("rejects invalid gameId", () => {
    const result = CashoutInputSchema.safeParse({ gameId: "not-a-uuid" });
    assert.equal(result.success, false);
  });

  it("rejects missing gameId", () => {
    const result = CashoutInputSchema.safeParse({});
    assert.equal(result.success, false);
  });
});
