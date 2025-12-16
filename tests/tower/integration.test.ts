import { describe, it, beforeAll, afterAll } from "vitest";
import assert from "node:assert/strict";
import { gql } from "graphql-request";
import { resolve } from "path";
import {
  startTestServer,
  createPlayer,
  createExperience,
  createPlayerBalance,
  createHashChain,
  createHouseBankroll,
  getPlayerBalance,
  type HubTestServer,
} from "@moneypot/hub/test";
import { defaultPlugins } from "@moneypot/hub";
import { TowerPlugin } from "../../src/plugins/tower.ts";

// Risk policy: allow up to 10% of bankroll as max payout
// For tower with 10 levels and 2 doors: maxPayout = wager * (2 * 0.99)^10 ≈ 817 * wager
// With wager=100 and bankroll=1M, maxPayout=81,700 which is < 10% of 1M = 100,000
const testRiskPolicy = ({ bankroll }: { bankroll: number }) => ({
  maxPayout: bankroll * 0.1,
});

describe("Tower Integration", () => {
  let hub: HubTestServer;

  beforeAll(async () => {
    hub = await startTestServer({
      plugins: [
        ...defaultPlugins,
        TowerPlugin({ maxFloor: 10, riskPolicy: testRiskPolicy }),
      ],
      extraPgSchemas: ["app"],
      userDatabaseMigrationsPath: resolve(
        import.meta.dirname,
        "../../migrations"
      ),
    });
  }, 30000);

  afterAll(async () => {
    if (hub) {
      await hub.stop();
    }
  });

  it("tower mutations are registered", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "schema-check",
    });
    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    const query = gql`
      query {
        __schema {
          mutationType {
            fields {
              name
            }
          }
        }
      }
    `;

    const result = await graphqlClient.request<{
      __schema: { mutationType: { fields: { name: string }[] } };
    }>(query);

    const mutationNames = result.__schema.mutationType.fields.map(
      (f) => f.name
    );
    assert.ok(
      mutationNames.includes("startTowerGame"),
      "startTowerGame mutation missing"
    );
    assert.ok(
      mutationNames.includes("climbTower"),
      "climbTower mutation missing"
    );
    assert.ok(
      mutationNames.includes("cashoutTower"),
      "cashoutTower mutation missing"
    );
  });

  it("can start a tower game", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "starter",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 1000,
    });
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    const result = await graphqlClient.request<{
      startTowerGame: {
        result: {
          __typename: string;
          game?: {
            id: string;
            status: string;
            wager: string;
            currentLevel: number;
          };
        };
      };
    }>(
      gql`
        mutation StartGame($input: StartTowerGameInput!) {
          startTowerGame(input: $input) {
            result {
              __typename
              ... on StartTowerGameSuccess {
                game {
                  id
                  status
                  wager
                  currentLevel
                }
              }
            }
          }
        }
      `,
      {
        input: {
          wager: 100,
          currency: "HOUSE",
          doors: 2,
          hashChainId: hashChain.id,
          clientSeed: "test-seed",
        },
      }
    );

    assert.equal(
      result.startTowerGame.result.__typename,
      "StartTowerGameSuccess"
    );
    const game = result.startTowerGame.result.game;
    assert.ok(game);
    assert.equal(game.status, "ACTIVE");
    assert.equal(game.wager, "100");
    assert.equal(game.currentLevel, 0);

    // Balance should be deducted
    const balance = await getPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
    });
    assert.equal(balance?.amount, 900);
  });

  it("can climb and cashout", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "climber",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 1000,
    });
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
      maxIterations: 20,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    // Start game
    const startResult = await graphqlClient.request<{
      startTowerGame: { result: { game?: { id: string } } };
    }>(
      gql`
        mutation StartGame($input: StartTowerGameInput!) {
          startTowerGame(input: $input) {
            result {
              ... on StartTowerGameSuccess {
                game {
                  id
                }
              }
            }
          }
        }
      `,
      {
        input: {
          wager: 100,
          currency: "HOUSE",
          doors: 2,
          hashChainId: hashChain.id,
          clientSeed: "start",
        },
      }
    );
    assert.ok(startResult.startTowerGame.result.game);
    let gameId = startResult.startTowerGame.result.game.id;

    // Try climbing until we either succeed once or bust
    let climbed = false;
    for (let attempt = 0; attempt < 10; attempt++) {
      const climbResult = await graphqlClient.request<{
        climbTower: {
          game: { status: string; currentLevel: number };
          safe: boolean;
          safeDoor: number;
        };
      }>(
        gql`
          mutation Climb($input: ClimbTowerInput!) {
            climbTower(input: $input) {
              game {
                status
                currentLevel
              }
              safe
              safeDoor
            }
          }
        `,
        { input: { gameId, door: attempt % 2, clientSeed: `climb-${attempt}` } }
      );

      if (climbResult.climbTower.safe) {
        climbed = true;
        assert.equal(climbResult.climbTower.game.currentLevel, 1);
        assert.equal(climbResult.climbTower.game.status, "ACTIVE");
        break;
      } else {
        // Busted - start a new game and try again
        assert.equal(climbResult.climbTower.game.status, "BUST");

        // Need fresh balance for next attempt
        await hub.dbPool.query(
          `UPDATE hub.balance SET amount = 1000 WHERE user_id = $1 AND experience_id = $2`,
          [player.id, experience.id]
        );

        const newGame = await graphqlClient.request<{
          startTowerGame: { result: { game?: { id: string } } };
        }>(
          gql`
            mutation StartGame($input: StartTowerGameInput!) {
              startTowerGame(input: $input) {
                result {
                  ... on StartTowerGameSuccess {
                    game {
                      id
                    }
                  }
                }
              }
            }
          `,
          {
            input: {
              wager: 100,
              currency: "HOUSE",
              doors: 2,
              hashChainId: hashChain.id,
              clientSeed: `restart-${attempt}`,
            },
          }
        );
        // Update gameId for next climb attempt
        assert.ok(newGame.startTowerGame.result.game);
        gameId = newGame.startTowerGame.result.game.id;
      }
    }

    // If we successfully climbed at least once, try to cashout
    if (climbed) {
      const cashoutResult = await graphqlClient.request<{
        cashoutTower: { game: { status: string }; payout: string };
      }>(
        gql`
          mutation Cashout($input: CashoutTowerInput!) {
            cashoutTower(input: $input) {
              game {
                status
              }
              payout
            }
          }
        `,
        { input: { gameId } }
      );

      assert.equal(cashoutResult.cashoutTower.game.status, "CASHOUT");
      // With 2 doors and 1% house edge, level 1 multiplier = 2 * 0.99 = 1.98
      // payout = floor(100 * 1.98) = 198
      assert.equal(cashoutResult.cashoutTower.payout, "198");
    }
  });

  it("rejects unauthorized requests", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "unauth",
    });
    // Don't authenticate - just use a raw client
    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    // Create a different player who shouldn't be able to access first player's game
    const player2 = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "other",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 1000,
    });
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
    });

    // Start a game as player1
    const result = await graphqlClient.request<{
      startTowerGame: { result: { game?: { id: string } } };
    }>(
      gql`
        mutation StartGame($input: StartTowerGameInput!) {
          startTowerGame(input: $input) {
            result {
              ... on StartTowerGameSuccess {
                game {
                  id
                }
              }
            }
          }
        }
      `,
      {
        input: {
          wager: 100,
          currency: "HOUSE",
          doors: 2,
          hashChainId: hashChain.id,
          clientSeed: "test",
        },
      }
    );
    assert.ok(result.startTowerGame.result.game);
    const gameId = result.startTowerGame.result.game.id;

    // Try to climb as player2
    const { graphqlClient: client2 } = await hub.authenticate(
      player2.id,
      experience.id
    );
    await assert.rejects(
      client2.request(
        gql`
          mutation Climb($input: ClimbTowerInput!) {
            climbTower(input: $input) {
              safe
            }
          }
        `,
        { input: { gameId, door: 0, clientSeed: "hack" } }
      ),
      /Not your game/
    );
  });

  it("rejects insufficient balance", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "broke",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 50,
    });
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    await assert.rejects(
      graphqlClient.request(
        gql`
          mutation StartGame($input: StartTowerGameInput!) {
            startTowerGame(input: $input) {
              result {
                ... on StartTowerGameSuccess {
                  game {
                    id
                  }
                }
              }
            }
          }
        `,
        {
          input: {
            wager: 100,
            currency: "HOUSE",
            doors: 2,
            hashChainId: hashChain.id,
            clientSeed: "test",
          },
        }
      ),
      /Insufficient balance/
    );
  });
});

describe("Tower Auto-Cashout", () => {
  let hub: HubTestServer;

  beforeAll(async () => {
    hub = await startTestServer({
      plugins: [
        ...defaultPlugins,
        TowerPlugin({ maxFloor: 1, riskPolicy: testRiskPolicy }), // Only 1 level needed for auto-cashout
      ],
      extraPgSchemas: ["app"],
      userDatabaseMigrationsPath: resolve(
        import.meta.dirname,
        "../../migrations"
      ),
    });
  }, 30000);

  afterAll(async () => {
    if (hub) {
      await hub.stop();
    }
  });

  it("auto-cashout at maxFloor", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "auto-cashout",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 10000,
    });
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
      maxIterations: 100,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    // Keep trying until we successfully climb (50% chance each attempt)
    let autoCashoutTriggered = false;
    for (let attempt = 0; attempt < 50 && !autoCashoutTriggered; attempt++) {
      // Start a new game
      const startResult = await graphqlClient.request<{
        startTowerGame: { result: { game?: { id: string } } };
      }>(
        gql`
          mutation StartGame($input: StartTowerGameInput!) {
            startTowerGame(input: $input) {
              result {
                ... on StartTowerGameSuccess {
                  game {
                    id
                  }
                }
              }
            }
          }
        `,
        {
          input: {
            wager: 100,
            currency: "HOUSE",
            doors: 2,
            hashChainId: hashChain.id,
            clientSeed: `start-${attempt}`,
          },
        }
      );
      assert.ok(startResult.startTowerGame.result.game);
      const gameId = startResult.startTowerGame.result.game.id;

      // Try to climb
      const climbResult = await graphqlClient.request<{
        climbTower: {
          game: { status: string; currentLevel: number };
          safe: boolean;
          autoCashout?: boolean;
          payout?: string;
        };
      }>(
        gql`
          mutation Climb($input: ClimbTowerInput!) {
            climbTower(input: $input) {
              game {
                status
                currentLevel
              }
              safe
              autoCashout
              payout
            }
          }
        `,
        { input: { gameId, door: 0, clientSeed: `climb-${attempt}` } }
      );

      if (climbResult.climbTower.safe) {
        // With maxFloor=1, a successful climb should trigger auto-cashout
        assert.equal(
          climbResult.climbTower.autoCashout,
          true,
          "Should auto-cashout at maxFloor"
        );
        assert.equal(
          climbResult.climbTower.game.status,
          "CASHOUT",
          "Game should be CASHOUT"
        );
        assert.equal(
          climbResult.climbTower.game.currentLevel,
          1,
          "Should be at level 1"
        );
        assert.ok(climbResult.climbTower.payout, "Should have payout");
        // With 2 doors, 1% house edge, level 1 multiplier = 2 * 0.99 = 1.98
        // payout = floor(100 * 1.98) = 198
        assert.equal(
          climbResult.climbTower.payout,
          "198",
          "Payout should be 198"
        );
        autoCashoutTriggered = true;
      } else {
        // Busted - restore balance for next attempt
        await hub.dbPool.query(
          `UPDATE hub.balance SET amount = 10000 WHERE user_id = $1 AND experience_id = $2`,
          [player.id, experience.id]
        );
      }
    }

    assert.ok(
      autoCashoutTriggered,
      "Should have triggered auto-cashout within 50 attempts"
    );
  });
});
