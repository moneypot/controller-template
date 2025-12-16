import pg from "pg";
import { runMigrations } from "@moneypot/hub";
import { withPgClientTransaction } from "@moneypot/hub/db";

const userDatabaseMigrationsPath = new URL("../migrations", import.meta.url)
  .pathname;

const superuserDatabaseUrl = process.env.SUPERUSER_DATABASE_URL;
if (!superuserDatabaseUrl) {
  console.error("SUPERUSER_DATABASE_URL is not set");
  process.exit(1);
}

const pgClient = new pg.Client({ connectionString: superuserDatabaseUrl });
await pgClient.connect();
try {
  await pgClient.query("drop schema if exists hub_core_versions cascade");
  await pgClient.query("drop schema if exists hub_user_versions cascade");

  console.log("Running migrations...");
  await runMigrations({ pgClient, userDatabaseMigrationsPath });
  console.log("Database reset complete");
} catch (e) {
  console.error("Error running migrations:", e);
  process.exit(1);
} finally {
  await pgClient.end();
}
