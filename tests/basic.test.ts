// Test @moneypot/hub/test basics

import { resolve } from "path";
import { assert, describe, it } from "vitest";
import {
  startTestServer,
  createPlayer,
  createExperience,
  createPlayerBalance,
  getPlayerBalance,
} from "@moneypot/hub/test";

describe("basic", () => {
  it("should work", async () => {
    const hub = await startTestServer({
      userDatabaseMigrationsPath: resolve(import.meta.dirname, "../migrations"),
    });
    const dbExperience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const dbPlayer = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "player1",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: dbPlayer.id,
      experienceId: dbExperience.id,
      currencyKey: "HOUSE",
      amount: 100,
    });

    assert.ok(dbExperience.id);
    assert.strictEqual(dbPlayer.uname, "player1");

    const dbBalance = await getPlayerBalance(hub.dbPool, {
      userId: dbPlayer.id,
      experienceId: dbExperience.id,
      currencyKey: "HOUSE",
    });

    assert.strictEqual(dbBalance?.amount, 100);

    await hub.stop();
  });
});
