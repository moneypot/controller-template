import { gql, makeExtendSchemaPlugin } from "@moneypot/hub/graphile";
import { GraphQLError } from "@moneypot/hub/graphql";
import {
  dbLockPlayerBalance,
  dbLockHouseBankroll,
  withPgPoolTransaction,
  type DbCurrency,
} from "@moneypot/hub/db";
import { exactlyOneRow, maybeOneRow } from "@moneypot/hub/db/util";
import * as crypto from "crypto";
import { CoinSide } from "../__generated__/graphql.ts";
import type { DbCoinflipBet } from "../dbtypes.ts";
import { z } from "zod";

// Example hub plugin that defines a coinflip game that uses
// tables defined in 002-coinflip.sql.
//
// If you really wanted to implement a simple finite-outcome game like this,
// you would use hub's builtin hubMakeOutcomeBet system which gives you various
// benefits like provably fair and avoiding common bugs.
//
// but this is just a hello-world example to give you an idea of how you
// might implement your own more complex game.

const HOUSE_EDGE = 0.01; // 1% house edge

// Try to put as much validation as possible in the zod schema
// so that we don't have to remember to do it.
const InputSchema = z.object({
  wager: z.number().int().gte(1, { error: "Wager must be at least 1" }),
  currency: z.string().min(1, { error: "Currency is required" }),
  target: z.enum(CoinSide, {
    error: `Target must be ${CoinSide.Heads} or ${CoinSide.Tails}`,
  }),
});

export const MakeCoinflipBetPlugin = makeExtendSchemaPlugin(() => {
  return {
    typeDefs: gql`
      input MakeCoinflipBetInput {
        wager: Int!
        currency: String!
        target: CoinSide!
      }

      type MakeCoinflipBetPayload {
        id: UUID!
        result: CoinSide!
      }

      extend type Mutation {
        makeCoinflipBet(input: MakeCoinflipBetInput!): MakeCoinflipBetPayload!
      }
    `,
    resolvers: {
      Mutation: {
        async makeCoinflipBet(_query, args, context: Grafast.Context) {
          const { identity, superuserPool } = context;
          const { input: rawInput } = args;

          if (identity?.kind !== "user") {
            throw new GraphQLError("Unauthorized");
          }

          // This is how you get the info of the user making the request
          const { session } = identity;

          // Validate input
          const input = (() => {
            const result = InputSchema.safeParse(rawInput);
            if (!result.success) {
              throw new GraphQLError(result.error.issues[0].message);
            }
            return result.data;
          })();

          // Ensure currency is found in casino currency list
          const dbCurrency = await superuserPool
            .query<Pick<DbCurrency, "key">>(
              `
              SELECT key
              FROM hub.currency
              WHERE key = $1 AND casino_id = $2
              `,
              [input.currency, session.casino_id]
            )
            .then(maybeOneRow);

          if (!dbCurrency) {
            throw new GraphQLError("Currency not found");
          }

          return withPgPoolTransaction(superuserPool, async (pgClient) => {
            // Lock the user balance for the transaction
            const dbLockedPlayerBalance = await dbLockPlayerBalance(pgClient, {
              userId: session.user_id,
              casinoId: session.casino_id,
              experienceId: session.experience_id,
              currencyKey: dbCurrency.key,
            });

            if (
              !dbLockedPlayerBalance ||
              dbLockedPlayerBalance.amount < input.wager
            ) {
              throw new GraphQLError("Player cannot afford wager");
            }

            // Ensure house can afford the max payout
            const multiplier = (1 - HOUSE_EDGE) * 2; // e.g. 1.98x if house edge is 1%
            const maxPayout = input.wager * multiplier;

            // Generate a random coin flip
            const result =
              crypto.randomInt(2) === 0 ? CoinSide.Heads : CoinSide.Tails;
            const net =
              result === input.target
                ? input.wager * multiplier - input.wager
                : -input.wager;

            await pgClient.query(
              `
              UPDATE hub.balance
              SET amount = amount + $2
              WHERE id = $1
              `,
              [dbLockedPlayerBalance.id, net]
            );

            const bet = await pgClient
              .query<Pick<DbCoinflipBet, "id">>(
                `
                INSERT INTO app.coinflip_bet (wager, target, outcome, multiplier, net, currency_key, user_id, casino_id, experience_id)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                RETURNING id
                `,
                [
                  input.wager,
                  input.target,
                  result,
                  multiplier,
                  net,
                  dbCurrency.key,
                  session.user_id,
                  session.casino_id,
                  session.experience_id,
                ]
              )
              .then(exactlyOneRow);

            // Lock the house bankroll after all other work is done to
            // minimize lock contention and hold the lock for the shortest
            // time possible
            const dbLockedHouseBankroll = await dbLockHouseBankroll(pgClient, {
              casinoId: session.casino_id,
              currencyKey: dbCurrency.key,
            });

            if (
              !dbLockedHouseBankroll ||
              dbLockedHouseBankroll.amount < maxPayout
            ) {
              throw new GraphQLError("House cannot afford payout");
            }

            // Update bankroll amount + stats
            await pgClient.query(
              `
              UPDATE hub.bankroll
              SET amount = amount - $2,
                  wagered = wagered + $3,
                  expected_value = expected_value + $4,
                  bets = bets + 1
              WHERE id = $1
              `,
              [
                dbLockedHouseBankroll.id,
                net,
                input.wager,
                input.wager * HOUSE_EDGE,
              ]
            );

            return {
              id: bet.id,
              result,
            };
          });
        },
      },
    },
  };
});
