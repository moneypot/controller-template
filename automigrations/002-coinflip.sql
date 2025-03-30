-- Example bet table
create table app.coinflip_bet (
  -- UUIDv7 gives us time-ordered random UUIDs
  id           uuid  primary key default hub_hidden.uuid_generate_v7(),
  wager        int not null,
  heads        boolean not null,

  net          float not null, -- negative if lost, wager*(multiplier-1) if won
  currency_key text  not null, -- e.g. "BTC", "HOUSE"

  -- Let us easily look up bets per casino and per experience
  user_id       uuid not null references hub.user(id),
  casino_id     uuid not null references hub.casino(id),
  experience_id uuid not null references hub.experience(id),

  -- Currencies are unique per casino
  foreign key (currency_key, casino_id) references hub.currency(key, casino_id)
);

-- Note: Adding foreign key indexes also generates relational queries in our graphql API
create index coinflip_bet_user_id_idx on app.coinflip_bet(user_id);
create index coinflip_bet_casino_id_idx on app.coinflip_bet(casino_id);
create index coinflip_bet_experience_id_idx on app.coinflip_bet(experience_id);

-- GRANT

-- We need to let our postgraphile user read from the table so it 
-- can generate graphql api for our CoinflipBet records
grant select on app.coinflip_bet to app_postgraphile;

-- RLS

-- Important: Unless every row in a table is publicly visible, you want
-- to enable Row Level Security and provide a policy that conditionally
-- allows the current user to view each row.
alter table app.coinflip_bet enable row level security;

create policy select_coinflip_bet on app.coinflip_bet for select using (
  -- Operator (you, the admin) can see all rows
  hub_hidden.is_operator() OR
  -- Users can only see their own rows
  user_id = hub_hidden.current_user_id()
);