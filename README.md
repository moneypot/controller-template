# Controller template

This repo is intended to be a copy-and-pasteable starting point for starting a controller server.

See [moneypot/experience-react-template](https://github.com/moneypot/experience-react-template) for an experience template.

Note: This repo includes a full example of how you might implement a custom game by demonstrating a trivial coin flip game. However, if you really did want to implement a coin flip game, since it has finite outcomes you would want to use hub's generic bet system: https://docs.moneypot.com/docs/controller-dev/outcome-bet/

## Usage

- Rename `.env.development.template` to `.env.development` and customize it. (esp change the database urls)

## Codegen graphql types

```bash
pnpm codegen
```

This will generate the `src/__generated__/graphql.ts` file from the schema.graphql file that hub generates every time it launches.

## Reset database

If you clear out @moneypot/hub' migration version tracking schemas, then it will reset its own `hub` tables and rerun your migrations.

```sql
drop schema hub_core_versions cascade;
drop schema hub_user_versions cascade;
```
