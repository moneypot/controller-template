import "dotenv/config";
import {
  defaultPlugins,
  HubGameConfigPlugin,
  startAndListen,
  type CustomGameConfigMap,
  type OutcomeBetConfigMap,
  type RiskPolicy,
  type ServerOptions,
} from "@moneypot/hub";
import { logger } from "@moneypot/hub/logger";
import { TowerPlugin } from "./plugins/tower.ts";
// import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.ts";

const exportSchemaSDLPath = new URL("../schema.graphql", import.meta.url)
  .pathname;
const userDatabaseMigrationsPath = new URL("../migrations", import.meta.url)
  .pathname;

logger.info({ exportSchemaSDLPath }, "Exporting graphql schema");
logger.info({ userDatabaseMigrationsPath }, "Running user migrations");

const riskPolicy: RiskPolicy = ({ bankroll }) => {
  // Reject any bet if it's trying to win more than 1% of our bankroll
  return {
    maxPayout: bankroll * 0.01,
  };
};

// Outcome bets are atomic bets for games that can be encoded with a finite array of { probability, payout } outcomes.
//
// The client sends us makeOutcomeBet({ kind: "GENERAL", outcomes: [...], wager, ... }) and our OutcomeBetConfigMap
// tells hub how to process it based on the request's `kind`.

type OutcomeBetKind = "GENERAL";

const outcomeBetConfigs: OutcomeBetConfigMap<OutcomeBetKind> = {
  GENERAL: {
    // Accept any bet if it's 1% in our favor and satisfies the risk policy
    houseEdge: 0.01,
    saveOutcomes: false,
    riskPolicy,
  },
};

// Custom games are games that we've implemented ourselves without hub's atomic makeOutcomeBet system.
//
// If we have any, we declare them with unique names so that clients can query for their risk limit policy
// i.e. so they can display "Max bet: 1,000 tokens"

type CustomGameKind = "TOWER";

const customGameConfigs: CustomGameConfigMap<CustomGameKind> = {
  TOWER: {
    riskPolicy,
  },
};

const options: ServerOptions = {
  plugins: [
    ...defaultPlugins,

    // Tower game plugin - demonstrates multi-step game flow
    TowerPlugin({ maxFloor: 10, riskPolicy }),

    // This plugin is optional, but here is how you can set up a GENERAL bet and a custom TOWER game
    HubGameConfigPlugin({ outcomeBetConfigs, customGameConfigs }),
  ],
  // Expose our public schema to @moneypot/hub so it will generate graphql from it
  extraPgSchemas: ["app"],
  exportSchemaSDLPath,
  userDatabaseMigrationsPath,
};

startAndListen(options).then(({ port }) => {
  logger.info({ port }, "hub server listening");
});
