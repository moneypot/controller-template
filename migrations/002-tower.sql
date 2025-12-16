-- Tower game: a simple multi-step game demonstrating startGame → action → cashout pattern

create type app.tower_game_status as enum ('ACTIVE', 'BUST', 'CASHOUT');

create table app.tower_game (
  id uuid primary key default hub_hidden.uuid_generate_v7(),

  user_id uuid not null references hub.user(id),
  casino_id uuid not null references hub.casino(id),
  experience_id uuid not null references hub.experience(id),

  currency_key text not null,

  status app.tower_game_status not null default 'ACTIVE',
  wager bigint not null,
  doors smallint not null,
  current_level smallint not null default 0,

  created_at timestamptz not null default now(),
  ended_at timestamptz
);

-- Only one active game per user/experience/casino
create unique index tower_game_active_idx
  on app.tower_game (user_id, experience_id, casino_id)
  where status = 'ACTIVE';

-- Index for common queries
create index tower_game_user_idx on app.tower_game (user_id);

-- RLS
alter table app.tower_game enable row level security;

create policy tower_game_select on app.tower_game for select using (
  hub_hidden.is_operator() or user_id = hub_hidden.current_user_id()
);
