import "dotenv/config";
import {
  defaultPlugins,
  startAndListen,
  type ServerOptions,
} from "@moneypot/hub";
import { join } from "node:path";
import { logger } from "@moneypot/hub/logger";
// import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.ts";

const exportSchemaSDLPath = join(import.meta.dirname, "../schema.graphql");
const userDatabaseMigrationsPath = join(
  import.meta.dirname,
  "../automigrations"
);

logger.info({ exportSchemaSDLPath }, "Exporting graphql schema");
logger.info({ userDatabaseMigrationsPath }, "Running user migrations");

const options: ServerOptions = {
  plugins: [
    ...defaultPlugins,
    // Add your plugins here
    // MakeCoinflipBetPlugin, // This plugin won't work until the 002-coinflip.sql migration is run
  ],
  // Expose our public schema to @moneypot/hub so it will generate graphql from it
  extraPgSchemas: ["app"],
  exportSchemaSDLPath,
  userDatabaseMigrationsPath,
};

startAndListen(options).then(() => {
  logger.info("hub server listening");
});
