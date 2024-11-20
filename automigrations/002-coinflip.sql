-- Example bet table
create table app.coinflip_bet (
  id           uuid  primary key default caas_hidden.uuid_generate_v7(),
  wager        float not null,
  heads        boolean not null,

  net          float not null, -- negative if lost, wager*(multiplier-1) if won
  currency_key text  not null,

  -- lets us easily look up the lastest bets for users, casinos, experiences
  user_id       uuid not null references caas.user(id),
  casino_id     uuid not null references caas.casino(id), 
  experience_id uuid not null references caas.experience(id), 

  foreign key (currency_key, casino_id) references caas.currency(key, casino_id)
)
