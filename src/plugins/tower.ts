import { extendSchema, gql } from "@moneypot/hub/graphile";
import { GraphQLError } from "@moneypot/hub/graphql";
import {
  access,
  context,
  object,
  ObjectStep,
  sideEffect,
} from "@moneypot/hub/grafast";
import {
  dbLockPlayerBalance,
  dbLockHouseBankroll,
  withPgPoolTransaction,
  type DbCurrency,
} from "@moneypot/hub/db";
import { exactlyOneRow, maybeOneRow } from "@moneypot/hub/db/util";
import { validateRisk, type RiskPolicy } from "@moneypot/hub";
import {
  dbLockHubHashChain,
  dbInsertHubHash,
  getIntermediateHash,
  makeFinalHash,
  normalizeHash,
} from "@moneypot/hub/hash-chain";
import { z } from "zod";
import type { DbTowerGame } from "../dbtypes.ts";

// Tower game: climb levels by picking the safe door
// Each level has N doors, 1 is safe
// Multiplier grows exponentially with each level cleared

const HOUSE_EDGE = 0.01;

export interface TowerPluginOptions {
  maxFloor: number;
  riskPolicy: RiskPolicy;
}

// Multiplier = (doors * (1 - houseEdge))^level
export function computeMultiplier(
  doors: number,
  level: number,
  houseEdge: number,
): number {
  if (level === 0) return 1;
  return Math.pow(doors * (1 - houseEdge), level);
}

export const StartInputSchema = z.object({
  wager: z.number().int().gte(1, { message: "Wager must be at least 1" }),
  currency: z.string().min(1, { message: "Currency is required" }),
  doors: z
    .number()
    .int()
    .gte(2, { message: "Must have at least 2 doors" })
    .lte(4, { message: "Maximum 4 doors" }),
  hashChainId: z.uuid({ message: "Invalid hash chain ID" }),
  clientSeed: z
    .string()
    .max(32, { message: "Client seed must be at most 32 characters" }),
});

export const ClimbInputSchema = z.object({
  gameId: z.string().uuid({ message: "Invalid game ID" }),
  door: z.number().int().gte(0, { message: "Door must be >= 0" }),
  clientSeed: z
    .string()
    .max(32, { message: "Client seed must be at most 32 characters" }),
});

export const CashoutInputSchema = z.object({
  gameId: z.uuid({ message: "Invalid game ID" }),
});

export function TowerPlugin({ maxFloor, riskPolicy }: TowerPluginOptions) {
  return extendSchema((build) => {
    const towerGameResource = build.input.pgRegistry.pgResources.tower_game;

    return {
      /*

      These will be defined for us since we granted select access to app_postgraphile:

      enum TowerGameStatus {
        ACTIVE
        BUST
        CASHOUT
      }

      type TowerGame {
        id: UUID!
        status: TowerGameStatus!
        wager: BigInt!
        doors: Int!
        currentLevel: Int!
        currentMultiplier: Float!
      }
      */
      typeDefs: gql`
        input StartTowerGameInput {
          wager: Int!
          currency: String!
          doors: Int!
          hashChainId: UUID!
          clientSeed: String!
        }

        type StartTowerGameSuccess {
          game: TowerGame!
        }

        union StartTowerGameResult = StartTowerGameSuccess | HubRiskError | HubBadHashChainError

        type StartTowerGamePayload {
          result: StartTowerGameResult!
        }

        input ClimbTowerInput {
          gameId: UUID!
          door: Int!
          clientSeed: String!
        }

        type ClimbTowerSuccess {
          game: TowerGame!
          safe: Boolean!
          safeDoor: Int!
          "Present when player reaches MAX_FLOOR and is auto-cashed out"
          autoCashout: Boolean
          "Payout amount (only present on auto-cashout)"
          payout: BigInt
        }

        union ClimbTowerResult = ClimbTowerSuccess | HubBadHashChainError

        type ClimbTowerPayload {
          result: ClimbTowerResult!
        }

        input CashoutTowerInput {
          gameId: UUID!
        }

        type CashoutTowerPayload {
          game: TowerGame!
          payout: BigInt!
        }

        extend type Mutation {
          startTowerGame(input: StartTowerGameInput!): StartTowerGamePayload!
          climbTower(input: ClimbTowerInput!): ClimbTowerPayload!
          cashoutTower(input: CashoutTowerInput!): CashoutTowerPayload!
        }
      `,
      objects: {
        Mutation: {
          plans: {
            // ─────────────────────────────────────────────────────────────────
            // START TOWER GAME
            // ─────────────────────────────────────────────────────────────────
            startTowerGame(_, { $input }) {
              const $identity = context().get("identity");
              const $superuserPool = context().get("superuserPool");

              const $result = sideEffect(
                [$input, $identity, $superuserPool],
                ([rawInput, identity, superuserPool]) => {
                  if (identity?.kind !== "user") {
                    throw new GraphQLError("Unauthorized");
                  }

                  const { session } = identity;
                  const input = (() => {
                    const result = StartInputSchema.safeParse(rawInput);
                    if (!result.success) {
                      throw new GraphQLError(result.error.issues[0].message);
                    }
                    return result.data;
                  })();

                  return withPgPoolTransaction(
                    superuserPool,
                    async (pgClient) => {
                      // Verify currency exists and get display info
                      const dbCurrency = await superuserPool
                        .query<
                          Pick<
                            DbCurrency,
                            "key" | "display_unit_name" | "display_unit_scale"
                          >
                        >(`SELECT key, display_unit_name, display_unit_scale FROM hub.currency WHERE key = $1 AND casino_id = $2`, [input.currency, session.casino_id])
                        .then(maybeOneRow);

                      if (!dbCurrency) {
                        throw new GraphQLError("Currency not found");
                      }

                      // Check for existing active game
                      const existingGame = await pgClient
                        .query<DbTowerGame>(
                          `SELECT * FROM app.tower_game
                         WHERE user_id = $1 AND experience_id = $2 AND casino_id = $3 AND status = 'ACTIVE'`,
                          [
                            session.user_id,
                            session.experience_id,
                            session.casino_id,
                          ],
                        )
                        .then(maybeOneRow);

                      if (existingGame) {
                        throw new GraphQLError(
                          "You already have an active tower game",
                        );
                      }

                      // Lock player balance
                      const dbLockedPlayerBalance = await dbLockPlayerBalance(
                        pgClient,
                        {
                          userId: session.user_id,
                          casinoId: session.casino_id,
                          experienceId: session.experience_id,
                          currencyKey: dbCurrency.key,
                        },
                      );

                      if (
                        !dbLockedPlayerBalance ||
                        dbLockedPlayerBalance.amount < input.wager
                      ) {
                        throw new GraphQLError("Insufficient balance");
                      }

                      // Lock hash chain
                      const hashChain = await dbLockHubHashChain(pgClient, {
                        userId: session.user_id,
                        experienceId: session.experience_id,
                        casinoId: session.casino_id,
                        hashChainId: input.hashChainId,
                        active: "must-be-active",
                      });

                      if (!hashChain) {
                        return {
                          __typename: "HubBadHashChainError" as const,
                          message: "Hash chain not found or inactive",
                        };
                      }

                      // Calculate max potential payout for risk check
                      const maxMultiplier = computeMultiplier(
                        input.doors,
                        maxFloor,
                        HOUSE_EDGE,
                      );
                      const maxPayout = input.wager * maxMultiplier;

                      // Lock house bankroll (do this last to minimize lock time)
                      const dbLockedHouseBankroll = await dbLockHouseBankroll(
                        pgClient,
                        {
                          casinoId: session.casino_id,
                          currencyKey: dbCurrency.key,
                        },
                      );

                      if (!dbLockedHouseBankroll) {
                        throw new GraphQLError("House bankroll not found");
                      }

                      // Validate bet against risk policy
                      const riskLimits = riskPolicy({
                        type: "get-limits",
                        currency: dbCurrency.key,
                        bankroll: dbLockedHouseBankroll.amount,
                      });

                      const riskResult = validateRisk({
                        type: "validate-bet",
                        currency: dbCurrency.key,
                        wager: input.wager,
                        bankroll: dbLockedHouseBankroll.amount,
                        riskLimits,
                        maxPotentialPayout: maxPayout,
                        displayUnitName: dbCurrency.display_unit_name,
                        displayUnitScale: dbCurrency.display_unit_scale,
                        outcomes: [],
                      });

                      if (!riskResult.ok) {
                        return {
                          __typename: "HubRiskError" as const,
                          message: riskResult.error.message,
                          riskLimits: riskResult.error.riskLimits,
                        };
                      }

                      // Deduct wager from player
                      await pgClient.query(
                        `UPDATE hub.balance SET amount = amount - $1 WHERE id = $2`,
                        [input.wager, dbLockedPlayerBalance.id],
                      );

                      // Create game record
                      const game = await pgClient
                        .query<DbTowerGame>(
                          `INSERT INTO app.tower_game (user_id, casino_id, experience_id, currency_key, wager, doors)
                         VALUES ($1, $2, $3, $4, $5, $6)
                         RETURNING *`,
                          [
                            session.user_id,
                            session.casino_id,
                            session.experience_id,
                            dbCurrency.key,
                            input.wager,
                            input.doors,
                          ],
                        )
                        .then(exactlyOneRow);

                      return {
                        __typename: "StartTowerGameSuccess" as const,
                        gameId: game.id,
                      };
                    },
                  );
                },
              );

              return object({ result: $result });
            },

            // ─────────────────────────────────────────────────────────────────
            // CLIMB TOWER
            // ─────────────────────────────────────────────────────────────────
            climbTower(_, { $input }) {
              const $identity = context().get("identity");
              const $superuserPool = context().get("superuserPool");

              const $result = sideEffect(
                [$input, $identity, $superuserPool],
                ([rawInput, identity, superuserPool]) => {
                  if (identity?.kind !== "user") {
                    throw new GraphQLError("Unauthorized");
                  }

                  const { session } = identity;
                  const input = (() => {
                    const result = ClimbInputSchema.safeParse(rawInput);
                    if (!result.success) {
                      throw new GraphQLError(result.error.issues[0].message);
                    }
                    return result.data;
                  })();

                  // Note: Since we're using superuserPool so that it has insertion privileges,
                  // RLS will be bypassed.
                  return withPgPoolTransaction(
                    superuserPool,
                    async (pgClient) => {
                      // Lock the game row
                      const dbLockedGame = await pgClient
                        .query<DbTowerGame>(
                          `SELECT * FROM app.tower_game WHERE id = $1 AND user_id = $2 AND experience_id = $3 AND casino_id = $4 FOR UPDATE`,
                          [
                            input.gameId,
                            session.user_id,
                            session.experience_id,
                            session.casino_id,
                          ],
                        )
                        .then(maybeOneRow);

                      if (!dbLockedGame) {
                        throw new GraphQLError("Game not found");
                      }

                      if (dbLockedGame.status !== "ACTIVE") {
                        throw new GraphQLError("Game is not active");
                      }

                      if (input.door < 0 || input.door >= dbLockedGame.doors) {
                        throw new GraphQLError(
                          `Door must be between 0 and ${dbLockedGame.doors - 1}`,
                        );
                      }

                      // Lock hash chain
                      const dbLockedHashChain = await pgClient
                        .query<{ id: string; current_iteration: number }>(
                          `SELECT id, current_iteration FROM hub.hash_chain
                         WHERE user_id = $1 AND experience_id = $2 AND casino_id = $3 AND active = true
                         FOR UPDATE`,
                          [
                            session.user_id,
                            session.experience_id,
                            session.casino_id,
                          ],
                        )
                        .then(maybeOneRow);

                      if (!dbLockedHashChain) {
                        return {
                          __typename: "HubBadHashChainError" as const,
                          message: "No active hash chain",
                        };
                      }

                      const iteration = dbLockedHashChain.current_iteration - 1;
                      if (iteration < 1) {
                        return {
                          __typename: "HubBadHashChainError" as const,
                          message: "Hash chain exhausted",
                        };
                      }

                      // Get hash from hash-herald
                      const hashResult = await getIntermediateHash({
                        hashChainId: dbLockedHashChain.id,
                        iteration,
                      });

                      if (hashResult.type !== "success") {
                        throw new GraphQLError(
                          "Failed to get hash: " + hashResult.reason,
                        );
                      }

                      // Decrement hash chain
                      await pgClient.query(
                        `UPDATE hub.hash_chain SET current_iteration = $1 WHERE id = $2`,
                        [iteration, dbLockedHashChain.id],
                      );

                      // Store hash
                      await dbInsertHubHash(pgClient, {
                        hashChainId: dbLockedHashChain.id,
                        kind: "INTERMEDIATE",
                        digest: hashResult.hash,
                        iteration,
                        clientSeed: input.clientSeed,
                        metadata: {
                          type: "TOWER_CLIMB",
                          gameId: dbLockedGame.id,
                          door: input.door,
                        },
                      });

                      // Determine outcome
                      const finalHash = makeFinalHash({
                        serverHash: hashResult.hash,
                        clientSeed: input.clientSeed,
                      });
                      const normalized = normalizeHash(finalHash);
                      const safeDoor = Math.floor(
                        normalized * dbLockedGame.doors,
                      );
                      const isSafe = input.door === safeDoor;

                      if (isSafe) {
                        // Advance level
                        const updatedGame = await pgClient
                          .query<DbTowerGame>(
                            `UPDATE app.tower_game
                           SET current_level = current_level + 1
                           WHERE id = $1
                           RETURNING *`,
                            [dbLockedGame.id],
                          )
                          .then(exactlyOneRow);

                        const newMultiplier = computeMultiplier(
                          updatedGame.doors,
                          updatedGame.current_level,
                          HOUSE_EDGE,
                        );

                        // Auto-cashout at MAX_FLOOR
                        if (updatedGame.current_level === maxFloor) {
                          const payout = Math.floor(
                            updatedGame.wager * newMultiplier,
                          );
                          const houseProfit = updatedGame.wager - payout;

                          // Lock player balance
                          const dbLockedPlayerBalance =
                            await dbLockPlayerBalance(pgClient, {
                              userId: session.user_id,
                              casinoId: session.casino_id,
                              experienceId: session.experience_id,
                              currencyKey: updatedGame.currency_key,
                            });

                          if (!dbLockedPlayerBalance) {
                            throw new GraphQLError("Player balance not found");
                          }

                          // Lock house bankroll
                          const dbLockedHouseBankroll =
                            await dbLockHouseBankroll(pgClient, {
                              casinoId: session.casino_id,
                              currencyKey: updatedGame.currency_key,
                            });

                          if (!dbLockedHouseBankroll) {
                            throw new GraphQLError("House bankroll not found");
                          }

                          // Pay player
                          await pgClient.query(
                            `UPDATE hub.balance SET amount = amount + $1 WHERE id = $2`,
                            [payout, dbLockedPlayerBalance.id],
                          );

                          // Update house bankroll
                          await pgClient.query(
                            `UPDATE hub.bankroll
                           SET amount = amount + $1, wagered = wagered + $2, bets = bets + 1
                           WHERE id = $3`,
                            [
                              houseProfit,
                              updatedGame.wager,
                              dbLockedHouseBankroll.id,
                            ],
                          );

                          // Update game status
                          const finalGame = await pgClient
                            .query<DbTowerGame>(
                              `UPDATE app.tower_game
                             SET status = 'CASHOUT', ended_at = now()
                             WHERE id = $1
                             RETURNING *`,
                              [updatedGame.id],
                            )
                            .then(exactlyOneRow);

                          return {
                            __typename: "ClimbTowerSuccess" as const,
                            gameId: finalGame.id,
                            safe: true,
                            safeDoor,
                            autoCashout: true,
                            payout,
                          };
                        }

                        return {
                          __typename: "ClimbTowerSuccess" as const,
                          gameId: updatedGame.id,
                          safe: true,
                          safeDoor,
                        };
                      } else {
                        // Bust - house wins the wager
                        const dbLockedHouseBankroll = await dbLockHouseBankroll(
                          pgClient,
                          {
                            casinoId: session.casino_id,
                            currencyKey: dbLockedGame.currency_key,
                          },
                        );

                        if (!dbLockedHouseBankroll) {
                          throw new GraphQLError("House bankroll not found");
                        }

                        // House collects wager
                        await pgClient.query(
                          `UPDATE hub.bankroll
                         SET amount = amount + $1, wagered = wagered + $1, bets = bets + 1
                         WHERE id = $2`,
                          [dbLockedGame.wager, dbLockedHouseBankroll.id],
                        );

                        // Update game status
                        const updatedGame = await pgClient
                          .query<DbTowerGame>(
                            `UPDATE app.tower_game
                           SET status = 'BUST', ended_at = now()
                           WHERE id = $1
                           RETURNING *`,
                            [dbLockedGame.id],
                          )
                          .then(exactlyOneRow);

                        return {
                          __typename: "ClimbTowerSuccess" as const,
                          gameId: updatedGame.id,
                          safe: false,
                          safeDoor,
                        };
                      }
                    },
                  );
                },
              );

              return object({ result: $result });
            },

            // ─────────────────────────────────────────────────────────────────
            // CASHOUT TOWER
            // ─────────────────────────────────────────────────────────────────
            cashoutTower(_, { $input }) {
              const $identity = context().get("identity");
              const $superuserPool = context().get("superuserPool");

              const $result = sideEffect(
                [$input, $identity, $superuserPool],
                ([rawInput, identity, superuserPool]) => {
                  if (identity?.kind !== "user") {
                    throw new GraphQLError("Unauthorized");
                  }

                  const { session } = identity;
                  const input = (() => {
                    const result = CashoutInputSchema.safeParse(rawInput);
                    if (!result.success) {
                      throw new GraphQLError(result.error.issues[0].message);
                    }
                    return result.data;
                  })();

                  return withPgPoolTransaction(
                    superuserPool,
                    async (pgClient) => {
                      // Lock the game row
                      const dbLockedGame = await pgClient
                        .query<DbTowerGame>(
                          `SELECT * FROM app.tower_game WHERE id = $1 AND user_id = $2 AND experience_id = $3 AND casino_id = $4 FOR UPDATE`,
                          [
                            input.gameId,
                            session.user_id,
                            session.experience_id,
                            session.casino_id,
                          ],
                        )
                        .then(maybeOneRow);

                      if (!dbLockedGame) {
                        throw new GraphQLError("Game not found");
                      }

                      if (dbLockedGame.status !== "ACTIVE") {
                        throw new GraphQLError("Game is not active");
                      }

                      if (dbLockedGame.current_level === 0) {
                        throw new GraphQLError(
                          "Must climb at least one level before cashing out",
                        );
                      }

                      const multiplier = computeMultiplier(
                        dbLockedGame.doors,
                        dbLockedGame.current_level,
                        HOUSE_EDGE,
                      );
                      const payout = Math.floor(
                        dbLockedGame.wager * multiplier,
                      );
                      const houseProfit = dbLockedGame.wager - payout; // negative = house loss

                      // Lock player balance
                      const dbLockedPlayerBalance = await dbLockPlayerBalance(
                        pgClient,
                        {
                          userId: session.user_id,
                          casinoId: session.casino_id,
                          experienceId: session.experience_id,
                          currencyKey: dbLockedGame.currency_key,
                        },
                      );

                      if (!dbLockedPlayerBalance) {
                        throw new GraphQLError("Player balance not found");
                      }

                      // Lock house bankroll
                      const dbLockedHouseBankroll = await dbLockHouseBankroll(
                        pgClient,
                        {
                          casinoId: session.casino_id,
                          currencyKey: dbLockedGame.currency_key,
                        },
                      );

                      if (!dbLockedHouseBankroll) {
                        throw new GraphQLError("House bankroll not found");
                      }

                      // Pay player
                      await pgClient.query(
                        `UPDATE hub.balance SET amount = amount + $1 WHERE id = $2`,
                        [payout, dbLockedPlayerBalance.id],
                      );

                      // Update house bankroll (house pays out profit, wager was never added)
                      await pgClient.query(
                        `UPDATE hub.bankroll
                       SET amount = amount + $1, wagered = wagered + $2, bets = bets + 1
                       WHERE id = $3`,
                        [
                          houseProfit,
                          dbLockedGame.wager,
                          dbLockedHouseBankroll.id,
                        ],
                      );

                      // Update game status
                      const updatedGame = await pgClient
                        .query<DbTowerGame>(
                          `UPDATE app.tower_game
                         SET status = 'CASHOUT', ended_at = now()
                         WHERE id = $1
                         RETURNING *`,
                          [dbLockedGame.id],
                        )
                        .then(exactlyOneRow);

                      return {
                        gameId: updatedGame.id,
                        payout,
                      };
                    },
                  );
                },
              );

              return $result;
            },
          },
        },

        // Success type for startTowerGame - fetches the game from DB
        StartTowerGameSuccess: {
          assertStep: ObjectStep,
          plans: {
            game($data: ObjectStep) {
              const $id = access($data, "gameId");
              return towerGameResource.get({ id: $id });
            },
          },
        },

        // Payload for startTowerGame
        StartTowerGamePayload: {
          assertStep: ObjectStep,
          plans: {
            result($data: ObjectStep) {
              return $data.get("result");
            },
          },
        },

        // Payload for climbTower
        ClimbTowerPayload: {
          assertStep: ObjectStep,
          plans: {
            result($data: ObjectStep) {
              return $data.get("result");
            },
          },
        },

        // Success type for climbTower - fetches the game from DB
        ClimbTowerSuccess: {
          assertStep: ObjectStep,
          plans: {
            game($data: ObjectStep) {
              const $id = access($data, "gameId");
              return towerGameResource.get({ id: $id });
            },
          },
        },

        // Payload for cashoutTower - fetches the game from DB
        CashoutTowerPayload: {
          plans: {
            game($data) {
              const $id = access($data, "gameId");
              return towerGameResource.get({ id: $id });
            },
          },
        },
      },
    };
  });
}
