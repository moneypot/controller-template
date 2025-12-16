// This file contains types to represent database tables and enums.

export type DbTowerGameStatus = "ACTIVE" | "BUST" | "CASHOUT";

export type DbTowerGame = {
  id: string;
  user_id: string;
  casino_id: string;
  experience_id: string;
  currency_key: string;
  status: DbTowerGameStatus;
  wager: number;
  doors: number;
  current_level: number;
  created_at: Date;
  ended_at: Date | null;
};
