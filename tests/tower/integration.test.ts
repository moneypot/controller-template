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
        "../../migrations",
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
      (f) => f.name,
    );
    assert.ok(
      mutationNames.includes("startTowerGame"),
      "startTowerGame mutation missing",
    );
    assert.ok(
      mutationNames.includes("climbTower"),
      "climbTower mutation missing",
    );
    assert.ok(
      mutationNames.includes("cashoutTower"),
      "cashoutTower mutation missing",
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
      },
    );

    assert.equal(
      result.startTowerGame.result.__typename,
      "StartTowerGameSuccess",
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
      },
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
        {
          input: { gameId, door: attempt % 2, clientSeed: `climb-${attempt}` },
        },
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
          [player.id, experience.id],
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
          },
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
        { input: { gameId } },
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
      },
    );
    assert.ok(result.startTowerGame.result.game);
    const gameId = result.startTowerGame.result.game.id;

    // Try to climb as player2
    const { graphqlClient: client2 } = await hub.authenticate(
      player2.id,
      experience.id,
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
        { input: { gameId, door: 0, clientSeed: "hack" } },
      ),
      /Game not found/,
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
        },
      ),
      /Insufficient balance/,
    );
  });

  it("rejects wager exceeding risk policy limits", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "high-roller",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 1_000_000,
    });
    // Small bankroll - 10% of 1000 = 100 max payout
    // With 10 floors and 2 doors, multiplier ≈ 817x, so wager of 1 would need 817 max payout
    await createHouseBankroll(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      currencyKey: "HOUSE",
      amount: 1000,
    });
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    // Wager of 100 with max multiplier ~817x = 81,700 max payout
    // But 10% of 1000 bankroll = 100 max payout allowed
    const result = await graphqlClient.request<{
      startTowerGame: {
        result: {
          __typename: string;
          message?: string;
        };
      };
    }>(
      gql`
        mutation StartGame($input: StartTowerGameInput!) {
          startTowerGame(input: $input) {
            result {
              __typename
              ... on HubRiskError {
                message
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
      },
    );

    assert.equal(result.startTowerGame.result.__typename, "HubRiskError");
    assert.ok(result.startTowerGame.result.message);
  });

  it("supports different door counts", async () => {
    const experience = await createExperience(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
    });
    const player = await createPlayer(hub.dbPool, {
      casinoId: hub.playgroundCasinoId,
      uname: "door-tester",
    });
    await createPlayerBalance(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      currencyKey: "HOUSE",
      amount: 10000,
    });
    // Need large bankroll for 4 doors: (4*0.99)^10 ≈ 948,313x multiplier
    // wager 100 * 948,313 = 94,831,300 max payout
    // With 10% risk policy, need bankroll >= 948,313,000
    await hub.dbPool.query(
      `INSERT INTO hub.bankroll (casino_id, currency_key, amount)
       VALUES ($1, $2, $3)
       ON CONFLICT (casino_id, currency_key) DO UPDATE SET amount = $3`,
      [hub.playgroundCasinoId, "HOUSE", 1_000_000_000],
    );
    const hashChain = await createHashChain(hub.dbPool, {
      userId: player.id,
      experienceId: experience.id,
      casinoId: hub.playgroundCasinoId,
      maxIterations: 100,
    });

    const { graphqlClient } = await hub.authenticate(player.id, experience.id);

    // Test with 3 doors - multiplier (3*0.99)^10 ≈ 7,374x, max payout 737,400
    const result3 = await graphqlClient.request<{
      startTowerGame: {
        result: {
          __typename: string;
          game?: { id: string; doors: number };
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
                  doors
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
          doors: 3,
          hashChainId: hashChain.id,
          clientSeed: "three-doors",
        },
      },
    );

    assert.equal(
      result3.startTowerGame.result.__typename,
      "StartTowerGameSuccess",
    );
    assert.ok(result3.startTowerGame.result.game);
    assert.equal(result3.startTowerGame.result.game.doors, 3);

    // Complete or bust the game so we can start another
    const gameId = result3.startTowerGame.result.game.id;
    let gameActive = true;
    while (gameActive) {
      const climbResult = await graphqlClient.request<{
        climbTower: { game: { status: string }; safe: boolean };
      }>(
        gql`
          mutation Climb($input: ClimbTowerInput!) {
            climbTower(input: $input) {
              game {
                status
              }
              safe
            }
          }
        `,
        { input: { gameId, door: 0, clientSeed: "climb" } },
      );
      if (
        !climbResult.climbTower.safe ||
        climbResult.climbTower.game.status !== "ACTIVE"
      ) {
        gameActive = false;
      }
    }

    // Restore balance and bankroll for next test
    await hub.dbPool.query(
      `UPDATE hub.balance SET amount = 10000 WHERE user_id = $1 AND experience_id = $2`,
      [player.id, experience.id],
    );
    await hub.dbPool.query(
      `UPDATE hub.bankroll SET amount = 1000000000 WHERE casino_id = $1 AND currency_key = $2`,
      [hub.playgroundCasinoId, "HOUSE"],
    );

    // Test with 4 doors - multiplier (4*0.99)^10 ≈ 948,313x, max payout 94,831,300
    const result4 = await graphqlClient.request<{
      startTowerGame: {
        result: {
          __typename: string;
          game?: { id: string; doors: number };
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
                  doors
                }
              }
              ... on HubRiskError {
                message
              }
            }
          }
        }
      `,
      {
        input: {
          wager: 100,
          currency: "HOUSE",
          doors: 4,
          hashChainId: hashChain.id,
          clientSeed: "four-doors",
        },
      },
    );

    assert.equal(
      result4.startTowerGame.result.__typename,
      "StartTowerGameSuccess",
    );
    assert.ok(result4.startTowerGame.result.game);
    assert.equal(result4.startTowerGame.result.game.doors, 4);
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
        "../../migrations",
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
        },
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
        { input: { gameId, door: 0, clientSeed: `climb-${attempt}` } },
      );

      if (climbResult.climbTower.safe) {
        // With maxFloor=1, a successful climb should trigger auto-cashout
        assert.equal(
          climbResult.climbTower.autoCashout,
          true,
          "Should auto-cashout at maxFloor",
        );
        assert.equal(
          climbResult.climbTower.game.status,
          "CASHOUT",
          "Game should be CASHOUT",
        );
        assert.equal(
          climbResult.climbTower.game.currentLevel,
          1,
          "Should be at level 1",
        );
        assert.ok(climbResult.climbTower.payout, "Should have payout");
        // With 2 doors, 1% house edge, level 1 multiplier = 2 * 0.99 = 1.98
        // payout = floor(100 * 1.98) = 198
        assert.equal(
          climbResult.climbTower.payout,
          "198",
          "Payout should be 198",
        );
        autoCashoutTriggered = true;
      } else {
        // Busted - restore balance for next attempt
        await hub.dbPool.query(
          `UPDATE hub.balance SET amount = 10000 WHERE user_id = $1 AND experience_id = $2`,
          [player.id, experience.id],
        );
      }
    }

    assert.ok(
      autoCashoutTriggered,
      "Should have triggered auto-cashout within 50 attempts",
    );
  });
});
