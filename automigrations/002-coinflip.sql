-- Example bet table
create table app.coinflip_bet (
  -- UUIDv7 gives us time-ordered random UUIDs
  id           uuid  primary key default caas_hidden.uuid_generate_v7(),
  wager        float not null,
  heads        boolean not null,

  net          float not null, -- negative if lost, wager*(multiplier-1) if won
  currency_key text  not null, -- e.g. "BTC", "HOUSE"

  -- Let us easily look up bets per casino and per experience
  user_id       uuid not null references caas.user(id),
  casino_id     uuid not null references caas.casino(id),
  experience_id uuid not null references caas.experience(id),

  -- Currencies are unique per casino
  foreign key (currency_key, casino_id) references caas.currency(key, casino_id)
);

-- Note: Adding foreign key indexes also generates relational queries in our graphql API
create index coinflip_bet_user_id_idx on app.coinflip_bet(user_id);
create index coinflip_bet_casino_id_idx on app.coinflip_bet(casino_id);
create index coinflip_bet_experience_id_idx on app.coinflip_bet(experience_id);
