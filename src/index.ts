import "dotenv/config";
import {
  defaultPlugins,
  startAndListen,
  type ServerOptions,
} from "@moneypot/hub";
import { join } from "node:path";
import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.ts";

const exportSchemaSDLPath = join(
  new URL(".", import.meta.url).pathname,
  "..",
  "schema.graphql"
);

console.log(`Exporting graphql schema to "${exportSchemaSDLPath}"`);

const userDatabaseMigrationsPath = join(
  new URL(".", import.meta.url).pathname,
  "..",
  "automigrations"
);

console.log(
  `Running user migrations from folder "${userDatabaseMigrationsPath}"`
);

const options: ServerOptions = {
  plugins: [...defaultPlugins, MakeCoinflipBetPlugin],
  // Expose our public schema to @moneypot/hub so it will generate graphql from it
  extraPgSchemas: ["app"],
  exportSchemaSDLPath,
  userDatabaseMigrationsPath,
};

startAndListen(options, ({ port }) => {
  console.log(`controller listening on ${port}`);
});
