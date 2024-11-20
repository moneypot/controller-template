drop schema if exists app cascade;        
drop schema if exists app_secret cascade; 

create schema app; -- For public info
create schema app_secret; -- For private info

-- Grant usage of our public schema to app_postgraphile user
grant usage on schema app to app_postgraphile;
