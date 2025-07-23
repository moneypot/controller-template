import "dotenv/config";
import {
  defaultPlugins,
  startAndListen,
  type ServerOptions,
} from "@moneypot/hub";
import { join } from "node:path";
// import { MakeCoinflipBetPlugin } from "./plugins/make-coinflip-bet.ts";

const exportSchemaSDLPath = join(import.meta.dirname, "../schema.graphql");
const userDatabaseMigrationsPath = join(
  import.meta.dirname,
  "../automigrations"
);

console.log(`Exporting graphql schema to "${exportSchemaSDLPath}"`);
console.log(
  `Running user migrations from folder "${userDatabaseMigrationsPath}"`
);

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
  console.log("hub server listening");
});
