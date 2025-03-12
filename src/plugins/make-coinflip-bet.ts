import { gql, makeExtendSchemaPlugin } from "@moneypot/hub/graphile";
import { GraphQLError } from "@moneypot/hub/graphql";
import { superuserPool, withPgPoolTransaction } from "@moneypot/hub/db";
import { exactlyOneRow, maybeOneRow } from "@moneypot/hub/db/util";
import * as crypto from "crypto";
import { type PluginContext } from "@moneypot/hub";

const HOUSE_EDGE = 0.01; // 1% house edge

export const MakeCoinflipBetPlugin = makeExtendSchemaPlugin(() => {
  return {
    typeDefs: gql`
      enum CoinState {
        HEADS
        TAILS
      }

      input MakeCoinflipBetInput {
        wager: Float!
        currency: String!
        target: CoinState!
      }

      type MakeCoinflipBetPayload {
        id: UUID!
        result: CoinState!
      }

      extend type Mutation {
        makeCoinflipBet(input: MakeCoinflipBetInput!): MakeCoinflipBetPayload!
      }
    `,
    resolvers: {
      Mutation: {
        async makeCoinflipBet(_query, args, context: PluginContext) {
          const { identity } = context;
          const { input } = args;

          if (identity?.kind !== "user") {
            throw new GraphQLError("Unauthorized");
          }

          const { session } = identity;

          if (input.wager < 1) {
            throw new GraphQLError("Wager must be >= 1");
          }

          return withPgPoolTransaction(superuserPool, async (pgClient) => {
            // Ensure currency is found in casino currency list
            const dbCurrency = await pgClient
              .query<{ key: string }>({
                text: `
                  SELECT key
                  FROM hub.currency
                  WHERE key = $1 AND casino_id = $2
                `,
                values: [input.currency, session.casino_id],
              })
              .then(maybeOneRow);

            if (!dbCurrency) {
              throw new GraphQLError("Currency not found");
            }

            // Lock the user's balance row and ensure they can afford the wager
            const balance = await pgClient
              .query<{ amount: number }>({
                text: `
                  select amount from hub.balance
                  where user_id = $1
                    and casino_id = $2
                    and experience_id = $3
                    and currency_key = $4
                  for update
                `,
                values: [
                  session.user_id,
                  session.casino_id,
                  session.experience_id,
                  dbCurrency.key,
                ],
              })
              .then(maybeOneRow)
              .then((row) => row?.amount);

            if (!balance || balance < input.wager) {
              throw new GraphQLError("Insufficient funds for wager");
            }

            // Ensure the house can afford the potential payout
            // Lock the bankroll row
            const bankrollBalance = await pgClient
              .query<{ amount: number }>({
                text: `
                      select amount 
                      from hub.bankroll
                      where currency_key = $1 
                        and casino_id = $2 
                      for update
                    `,
                values: [dbCurrency.key, session.casino_id],
              })
              .then(maybeOneRow)
              .then((row) => row?.amount);

            // Ensure house can afford the max payout
            const multiplier = (1 - HOUSE_EDGE) * 2; // e.g. 1.98x if house edge is 1%
            const maxPayout = input.wager * multiplier;

            if (!bankrollBalance || bankrollBalance < maxPayout) {
              throw new GraphQLError("House cannot afford payout");
            }

            // Generate a random coin flip
            const result = crypto.randomInt(2) === 0 ? "HEADS" : "TAILS";
            const net =
              result === input.target
                ? input.wager * multiplier - input.wager
                : -input.wager;

            await pgClient.query({
              text: `
                UPDATE hub.balance
                SET amount = amount + $1 
                WHERE user_id = $2 
                  AND casino_id = $3
                  AND experience_id = $4 
                  AND currency_key = $5
              `,
              values: [
                net,
                session.user_id,
                session.casino_id,
                session.experience_id,
                dbCurrency.key,
              ],
            });

            await pgClient.query({
              text: `
                UPDATE hub.bankroll
                SET amount = amount - $1 
                WHERE currency_key = $2
                  AND casino_id = $3
              `,
              values: [net, dbCurrency.key, session.casino_id],
            });

            const bet = await pgClient
              .query<{ id: string }>({
                text: `
                INSERT INTO app.coinflip_bet (wager, heads, net, currency_key, user_id, casino_id, experience_id)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id
              `,
                values: [
                  input.wager,
                  result === "HEADS",
                  net,
                  dbCurrency.key,
                  session.user_id,
                  session.casino_id,
                  session.experience_id,
                ],
              })
              .then(exactlyOneRow);

            // Update bankroll stats
            await pgClient.query({
              text: `
                update hub.bankroll
                set bets = bets + 1,
                    wagered = wagered + $1
                    expected_value = expected_value + $4
                where currency_key = $2
                  and casino_id = $3
              `,
              values: [
                input.wager,
                dbCurrency.key,
                session.casino_id,
                input.wager * HOUSE_EDGE,
              ],
            });

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
