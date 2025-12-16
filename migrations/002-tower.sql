-- Tower game: a simple multi-step game demonstrating startGame → action → cashout pattern

-- This will codegen into a graphql enum type TowerGameStatus { ACTIVE, BUST, CASHOUT }
create type app.tower_game_status as enum ('ACTIVE', 'BUST', 'CASHOUT');

-- This will codegen into a graphql type TowerGame { id: UUID!, status: TowerGameStatus!, ... }
create table app.tower_game (
  id uuid primary key default hub_hidden.uuid_generate_v7(),

  -- Pretty much every table in your database should have these three columns
  user_id uuid not null references hub.user(id),
  casino_id uuid not null references hub.casino(id),
  experience_id uuid not null references hub.experience(id),

  currency_key text not null,

  status app.tower_game_status not null default 'ACTIVE',
  wager bigint not null,
  doors smallint not null,
  current_level smallint not null default 0,

  created_at timestamptz not null default now(),
  ended_at timestamptz,

  -- Currencies are unique per casino
  foreign key (currency_key, casino_id) references hub.currency(key, casino_id)
);


-- Only one active game per user/experience/casino
create unique index tower_game_active_idx
  on app.tower_game (user_id, experience_id, casino_id)
  where status = 'ACTIVE';

-- Note: Adding foreign key indexes also generates relational queries in our graphql API
create index tower_game_user_idx on app.tower_game (user_id);
create index tower_game_experience_idx on app.tower_game (experience_id);
create index tower_game_casino_idx on app.tower_game (casino_id);

-- Row Level Security (RLS)

-- Important: Unless every row in a table is publicly visible, you want
-- to enable Row Level Security and provide a policy that conditionally
-- allows the current user to view certain (or all) rows.
--
-- We recommend always enabling RLS for all tables, even if the RLS
-- policy is simply `true` (i.e. public access).
alter table app.tower_game enable row level security;

-- We need to let our postgraphile user read the table so it 
-- can successfully query the table and also generate graphql types/queries for it.
grant select on table app.tower_game to app_postgraphile;


-- Important: Use RLS to grant
create policy tower_game_select on app.tower_game for select using (
  -- We're logged in as the "operator" whenever we use our internal hub.api_key
  -- e.g. we might want to view all games when we're on our /dashboard
  (select hub_hidden.is_operator()) OR

  -- Users can view their own games for the current experience/casino
  (
    user_id = hub_hidden.current_user_id()
    and experience_id = hub_hidden.current_experience_id()
    and casino_id = hub_hidden.current_casino_id()
  )
);
