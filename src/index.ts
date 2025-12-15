import "dotenv/config";
import {
  defaultPlugins,
  startAndListen,
  type ServerOptions,
} from "@moneypot/hub";
import { logger } from "@moneypot/hub/logger";
// import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.ts";

const exportSchemaSDLPath = new URL("../schema.graphql", import.meta.url)
  .pathname;
const userDatabaseMigrationsPath = new URL("../automigrations", import.meta.url)
  .pathname;

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

startAndListen(options).then(({ port }) => {
  logger.info({ port }, "hub server listening");
});
