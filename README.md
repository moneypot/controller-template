# Controller template

This repo is intended to be a copy-and-pasteable starting point for starting a controller server.

See [moneypot/experience-react-template](https://github.com/moneypot/experience-react-template) for an experience template.

## Usage

- Rename `.env.template` to `.env` and customize it. (esp change the database urls)

## Codegen graphql types

```bash
npm run codegen
```

This will generate the `src/__generated__/graphql.ts` file from the schema.graphql file that hub generates every time it launches.

## Reset database

If you clear out @moneypot/hub' migration version tracking schemas, then it will reset its own `hub` tables and rerun your migrations.

```sql
drop schema hub_core_versions cascade;
drop schema hub_user_versions cascade;
```

Then, if you make sure your 001-schema.sql migration drops and recreates its own schemas, then reseting your dev db should be as simple as running the above commands and rebooting your server.

```sql
-- Example 001-schema.sql

-- Drop and recreate your schema
drop schema if exists app cascade;
create schema app;
grant usage on schema app to app_postgraphile;

-- Now for your custom tables

create table app.foo (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

-- Grant access to app_postgraphile so that your graphql queries work

grant select on table app.foo to app_postgraphile;

-- Important: Use RLS to control access to each table

alter table app.foo enable row level security;

create policy select_foo on app.foo for select using (
  -- Requests that authenticate with an api key can see all rows
  hub_hidden.is_operator() or
  -- Requests that authenticate with a browser session id (aka users) can only see their own rows
  user_id = hub_hidden.current_user_id()
);
```
