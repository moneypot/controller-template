-- Example bet table
create table app.coinflip_bet (
  id           uuid  primary key default caas_hidden.uuid_generate_v7(),
  wager        float not null,
  heads        boolean not null,

  net          float not null, -- negative if lost, wager*(multiplier-1) if won
  currency_key text  not null, -- e.g. "BTC", "HOUSE"

  -- Remember: the caas database is multi-tenant across every experience on every Moneypot casino.
  user_id       uuid not null references caas.user(id),
  casino_id     uuid not null references caas.casino(id),
  experience_id uuid not null references caas.experience(id),

  -- Currencies are unique per casino
  foreign key (currency_key, casino_id) references caas.currency(key, casino_id)
);
