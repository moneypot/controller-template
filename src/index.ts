import "dotenv/config";
import {
  defaultPlugins,
  startAndListen,
  type ServerOptions,
} from "@moneypot/caas";
import { join } from "node:path";
import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.js";

const options: ServerOptions = {
  plugins: [...defaultPlugins, MakeCoinflipBetPlugin],
  // Expose our public schema to @moneypot/caas
  extraPgSchemas: ["app"],
  exportSchemaSDLPath: join(
    new URL(".", import.meta.url).pathname,
    "..",
    "schema.graphql"
  ),
  userDatabaseMigrationsPath: join(
    new URL(".", import.meta.url).pathname,
    "..",
    "automigrations"
  ),
};

startAndListen(options, ({ port }) => {
  console.log(`controller listening on ${port}`);
});
