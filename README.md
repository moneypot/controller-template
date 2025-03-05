# Controller template

This repo is intended to be a copy-and-pasteable starting point for starting a controller server.

See [moneypot/experience-react-template](https://github.com/moneypot/experience-react-template) for an experience template.

## Usage

- Rename `.env.template` to `.env` and customize it. (esp change the database urls)

## Reset database

If you clear out @moneypot/caas' migration version tracking schemas, then it will reset its own `caas` tables and rerun your migrations.

```sql
drop schema caas_core_versions cascade;
drop schema caas_user_versions cascade;
```

Then, if you make sure your 001-schema.sql migration drops and recreates its own schemas, then reseting your dev db should be as simple as running the above commands and rebooting your server.

```sql
-- Example 001-schema.sql

-- Drop and recreate your schema
drop schema if exists app cascade;
create schema app;
grant usage on schema app to app_postgraphile;

-- Now continue with your tables and such...

create table app.foo (
  id uuid primary key default gen_random_uuid(),
  name text not null
);
```
