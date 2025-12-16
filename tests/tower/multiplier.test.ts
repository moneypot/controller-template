import { describe, it } from "vitest";
import assert from "node:assert/strict";
import { computeMultiplier } from "../../src/plugins/tower.ts";

describe("computeMultiplier", () => {
  const HOUSE_EDGE = 0.01;

  it("returns 1 for level 0", () => {
    assert.equal(computeMultiplier(3, 0, HOUSE_EDGE), 1);
  });

  it("returns 1 for level 0 regardless of doors", () => {
    assert.equal(computeMultiplier(2, 0, HOUSE_EDGE), 1);
    assert.equal(computeMultiplier(4, 0, HOUSE_EDGE), 1);
  });

  it("calculates correct multiplier for 3 doors, level 1", () => {
    // 3 doors * 0.99 = 2.97
    const result = computeMultiplier(3, 1, HOUSE_EDGE);
    assert.ok(Math.abs(result - 2.97) < 0.001);
  });

  it("calculates correct multiplier for 2 doors, level 1", () => {
    // 2 doors * 0.99 = 1.98
    const result = computeMultiplier(2, 1, HOUSE_EDGE);
    assert.ok(Math.abs(result - 1.98) < 0.001);
  });

  it("calculates correct multiplier for 4 doors, level 1", () => {
    // 4 doors * 0.99 = 3.96
    const result = computeMultiplier(4, 1, HOUSE_EDGE);
    assert.ok(Math.abs(result - 3.96) < 0.001);
  });

  it("calculates correct multiplier for level 2", () => {
    // 2.97^2 = 8.8209
    const result = computeMultiplier(3, 2, HOUSE_EDGE);
    assert.ok(Math.abs(result - 8.8209) < 0.001);
  });

  it("calculates correct multiplier for level 3", () => {
    // 2.97^3 = 26.198...
    const result = computeMultiplier(3, 3, HOUSE_EDGE);
    assert.ok(Math.abs(result - 26.198) < 0.01);
  });

  it("multiplier grows exponentially", () => {
    const level1 = computeMultiplier(3, 1, HOUSE_EDGE);
    const level2 = computeMultiplier(3, 2, HOUSE_EDGE);
    const level3 = computeMultiplier(3, 3, HOUSE_EDGE);

    assert.ok(Math.abs(level2 - level1 * level1) < 0.001);
    assert.ok(Math.abs(level3 - level1 * level1 * level1) < 0.001);
  });

  it("handles zero house edge", () => {
    assert.equal(computeMultiplier(3, 1, 0), 3);
    assert.equal(computeMultiplier(3, 2, 0), 9);
  });

  it("higher house edge reduces multiplier", () => {
    const lowEdge = computeMultiplier(3, 1, 0.01);
    const highEdge = computeMultiplier(3, 1, 0.05);
    assert.ok(highEdge < lowEdge);
  });
});
