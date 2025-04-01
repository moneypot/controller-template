import { CoinSide } from "./__generated__/graphql.ts";

// This file contains types to represent database tables and enums.

export type DbCoinflipBet = {
  id: string;
  target: CoinSide;
  outcome: CoinSide;
  wager: number;
  currency_key: string;
  user_id: string;
  casino_id: string;
  experience_id: string;
};
