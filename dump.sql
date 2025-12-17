--
-- PostgreSQL database dump
--

\restrict ehvVQg9sXCykDSau5GMOyA6vuPTMNfwbfezpaX3hHR0PmymIHkBhzbz83L7vY1g

-- Dumped from database version 17.7 (Postgres.app)
-- Dumped by pg_dump version 17.7 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app;


--
-- Name: app_secret; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_secret;


--
-- Name: hub; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hub;


--
-- Name: hub_core_versions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hub_core_versions;


--
-- Name: hub_hidden; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hub_hidden;


--
-- Name: hub_secret; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hub_secret;


--
-- Name: hub_user_versions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA hub_user_versions;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: tower_game_status; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.tower_game_status AS ENUM (
    'ACTIVE',
    'BUST',
    'CASHOUT'
);


--
-- Name: chat_message_type; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.chat_message_type AS ENUM (
    'user',
    'system'
);


--
-- Name: hash_kind; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.hash_kind AS ENUM (
    'TERMINAL',
    'INTERMEDIATE',
    'PREIMAGE'
);


--
-- Name: mp_take_request_status; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.mp_take_request_status AS ENUM (
    'PENDING',
    'TRANSFERRED',
    'CONTROLLER_REJECTED',
    'USER_CANCELED'
);


--
-- Name: mp_transfer_status; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.mp_transfer_status AS ENUM (
    'PENDING',
    'COMPLETED',
    'CANCELED',
    'UNCLAIMED',
    'EXPIRED'
);


--
-- Name: outcome; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.outcome AS (
	weight double precision,
	profit double precision
);


--
-- Name: take_request_status; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.take_request_status AS ENUM (
    'PENDING',
    'PROCESSING',
    'COMPLETED',
    'FAILED',
    'REJECTED'
);


--
-- Name: transfer_status_kind; Type: TYPE; Schema: hub; Owner: -
--

CREATE TYPE hub.transfer_status_kind AS ENUM (
    'PENDING',
    'COMPLETED',
    'CANCELED',
    'UNCLAIMED',
    'EXPIRED'
);


--
-- Name: notify_balance_change(); Type: FUNCTION; Schema: hub; Owner: -
--

CREATE FUNCTION hub.notify_balance_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM pg_notify(
          'hub:user:' || NEW.user_id || ':balance_alert',
          json_build_object('currency_key', NEW.currency_key)::text
        );
    ELSIF TG_OP = 'UPDATE' AND NEW.amount IS DISTINCT FROM OLD.amount THEN
        PERFORM pg_notify(
          'hub:user:' || NEW.user_id || ':balance_alert',
          json_build_object('currency_key', NEW.currency_key)::text
        );
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: update_take_request_timestamps(); Type: FUNCTION; Schema: hub; Owner: -
--

CREATE FUNCTION hub.update_take_request_timestamps() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();

  IF OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.status_changed_at = NOW();
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: current_casino_id(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.current_casino_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('session.casino_id', true), '')::uuid;
$$;


--
-- Name: current_experience_id(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.current_experience_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('session.experience_id', true), '')::uuid;
$$;


--
-- Name: current_session_id(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.current_session_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('session.id', true), '')::uuid;
$$;


--
-- Name: current_user_id(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.current_user_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('session.user_id', true), '')::uuid;
$$;


--
-- Name: is_experience_owner(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.is_experience_owner() RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('session.is_experience_owner', true), '') = '1';
$$;


--
-- Name: is_operator(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.is_operator() RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('operator.api_key', true), '') is not null;
$$;


--
-- Name: uuid_generate_v7(); Type: FUNCTION; Schema: hub_hidden; Owner: -
--

CREATE FUNCTION hub_hidden.uuid_generate_v7() RETURNS uuid
    LANGUAGE plpgsql PARALLEL SAFE
    AS $$
  DECLARE
    unix_time_ms CONSTANT bytea NOT NULL DEFAULT substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) from 3);

    buffer                bytea NOT NULL DEFAULT unix_time_ms || gen_random_bytes(10);
  BEGIN
    buffer = set_byte(buffer, 6, (b'0111' || get_byte(buffer, 6)::bit(4))::bit(8)::int);

    buffer = set_byte(buffer, 8, (b'10'   || get_byte(buffer, 8)::bit(6))::bit(8)::int);

    RETURN encode(buffer, 'hex');
  END
$$;


--
-- Name: extract_timestamp_from_uuid_v7(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.extract_timestamp_from_uuid_v7(uuid_v7 uuid) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT to_timestamp(('x'||replace(uuid_v7::text, '-', ''))::bit(48)::bigint / 1000) AS result;
$$;


--
-- Name: notify_new_casino(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_casino() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.is_playground = false THEN
    PERFORM pg_notify('hub:new_casino', json_build_object(
      'id', NEW.id
    )::text);
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: notify_put(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_put() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('hub:user:' || NEW.user_id || ':put',
        json_build_object(
            'currency_key', NEW.currency_key,
            'experience_id', NEW.experience_id,
            'mp_transfer_id', NEW.mp_transfer_id
        )::text);
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: tower_game; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tower_game (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    user_id uuid NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    currency_key text NOT NULL,
    status app.tower_game_status DEFAULT 'ACTIVE'::app.tower_game_status NOT NULL,
    wager bigint NOT NULL,
    doors smallint NOT NULL,
    current_level smallint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone
);


--
-- Name: chat_mute; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.chat_mute (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_id uuid NOT NULL,
    expired_at timestamp with time zone,
    revoked_at timestamp with time zone,
    reason text
);


--
-- Name: active_chat_mute; Type: VIEW; Schema: hub; Owner: -
--

CREATE VIEW hub.active_chat_mute AS
 SELECT DISTINCT ON (casino_id, experience_id, user_id) id,
    casino_id,
    experience_id,
    user_id,
    expired_at,
    revoked_at,
    reason
   FROM hub.chat_mute
  WHERE ((revoked_at IS NULL) AND ((expired_at IS NULL) OR (expired_at > now())))
  ORDER BY casino_id, experience_id, user_id, id DESC;


--
-- Name: session; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.session (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_token uuid NOT NULL,
    expired_at timestamp with time zone DEFAULT (now() + '1 year'::interval) NOT NULL,
    key uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: active_session; Type: VIEW; Schema: hub; Owner: -
--

CREATE VIEW hub.active_session AS
 SELECT id,
    casino_id,
    user_id,
    experience_id,
    user_token,
    expired_at,
    key
   FROM hub.session
  WHERE (expired_at > now());


--
-- Name: api_key; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.api_key (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone
);


--
-- Name: audit_log; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.audit_log (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    balance_id uuid,
    bankroll_id uuid,
    balance_old double precision,
    balance_new double precision,
    balance_delta double precision,
    bankroll_old double precision,
    bankroll_new double precision,
    bankroll_delta double precision,
    action text NOT NULL,
    metadata jsonb,
    ref_type text,
    ref_id text,
    CONSTRAINT audit_log_check CHECK (((balance_id IS NOT NULL) OR (bankroll_id IS NOT NULL))),
    CONSTRAINT audit_log_check1 CHECK (((balance_id IS NULL) OR ((balance_old IS NOT NULL) AND (balance_new IS NOT NULL) AND (balance_delta IS NOT NULL)))),
    CONSTRAINT audit_log_check2 CHECK (((bankroll_id IS NULL) OR ((bankroll_old IS NOT NULL) AND (bankroll_new IS NOT NULL) AND (bankroll_delta IS NOT NULL)))),
    CONSTRAINT audit_log_check3 CHECK (((balance_id IS NOT NULL) OR ((balance_old IS NULL) AND (balance_new IS NULL) AND (balance_delta IS NULL)))),
    CONSTRAINT audit_log_check4 CHECK (((bankroll_id IS NOT NULL) OR ((bankroll_old IS NULL) AND (bankroll_new IS NULL) AND (bankroll_delta IS NULL))))
);


--
-- Name: balance; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.balance (
    casino_id uuid NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    currency_key text NOT NULL,
    amount double precision DEFAULT 0 NOT NULL,
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    CONSTRAINT amount_non_negative CHECK ((amount >= (0)::double precision))
);


--
-- Name: bankroll; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.bankroll (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    currency_key text NOT NULL,
    amount double precision DEFAULT 0 NOT NULL,
    bets bigint DEFAULT 0 NOT NULL,
    wagered double precision DEFAULT 0 NOT NULL,
    expected_value double precision DEFAULT 0 NOT NULL,
    CONSTRAINT amount_non_negative CHECK ((amount >= (0)::double precision))
);


--
-- Name: user; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub."user" (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    mp_user_id uuid NOT NULL,
    uname text NOT NULL,
    client_id uuid
);


--
-- Name: audit_log_view; Type: VIEW; Schema: hub; Owner: -
--

CREATE VIEW hub.audit_log_view AS
 SELECT al.id,
    al.balance_id,
    al.bankroll_id,
    al.balance_old,
    al.balance_new,
    al.balance_delta,
    al.bankroll_old,
    al.bankroll_new,
    al.bankroll_delta,
    al.action,
    al.metadata,
    al.ref_type,
    al.ref_id,
    COALESCE(b.currency_key, br.currency_key) AS currency_key,
    b.user_id,
    u.uname,
    u.mp_user_id,
    COALESCE(b.casino_id, br.casino_id) AS casino_id,
    b.experience_id
   FROM (((hub.audit_log al
     LEFT JOIN hub.balance b ON ((b.id = al.balance_id)))
     LEFT JOIN hub."user" u ON ((u.id = b.user_id)))
     LEFT JOIN hub.bankroll br ON ((br.id = al.bankroll_id)));


--
-- Name: casino; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.casino (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    base_url text NOT NULL,
    name text NOT NULL,
    graphql_url text NOT NULL,
    is_playground boolean DEFAULT false NOT NULL
);


--
-- Name: casino_secret; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.casino_secret (
    id uuid NOT NULL,
    controller_id uuid NOT NULL,
    api_key uuid NOT NULL
);


--
-- Name: chat_message; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.chat_message (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_id uuid,
    type hub.chat_message_type NOT NULL,
    client_id uuid NOT NULL,
    body text NOT NULL,
    hidden_at timestamp with time zone,
    CONSTRAINT chat_message_user_id_check CHECK ((((type = 'user'::hub.chat_message_type) AND (user_id IS NOT NULL)) OR ((type = 'system'::hub.chat_message_type) AND (user_id IS NULL))))
);


--
-- Name: chat_mod; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.chat_mod (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_id uuid NOT NULL
);


--
-- Name: chat_rate_bucket; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.chat_rate_bucket (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_id uuid NOT NULL,
    window_seconds integer NOT NULL,
    bucket_start timestamp with time zone NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


--
-- Name: currency; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.currency (
    key text NOT NULL,
    casino_id uuid NOT NULL,
    display_unit_name text NOT NULL,
    display_unit_scale integer NOT NULL
);


--
-- Name: deposit; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.deposit (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    mp_transfer_id text NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    amount double precision NOT NULL,
    currency_key text NOT NULL,
    CONSTRAINT deposit_amount_check CHECK ((amount > (0)::double precision))
);


--
-- Name: experience; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.experience (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    mp_experience_id uuid NOT NULL,
    name text NOT NULL,
    user_id uuid,
    client_id uuid
);


--
-- Name: faucet_claim; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.faucet_claim (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    user_id uuid NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    currency_key text NOT NULL,
    amount double precision NOT NULL,
    CONSTRAINT faucet_claim_amount_check CHECK ((amount > (0)::double precision))
);


--
-- Name: hash; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.hash (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    kind hub.hash_kind NOT NULL,
    hash_chain_id uuid NOT NULL,
    iteration integer NOT NULL,
    digest bytea NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    client_seed text,
    CONSTRAINT hash_iteration_check CHECK ((iteration >= 0))
);


--
-- Name: hash_chain; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.hash_chain (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    casino_id uuid NOT NULL,
    active boolean NOT NULL,
    max_iteration integer NOT NULL,
    current_iteration integer NOT NULL,
    CONSTRAINT hash_chain_check CHECK (((current_iteration >= 0) AND (current_iteration <= max_iteration))),
    CONSTRAINT hash_chain_max_iteration_check CHECK ((max_iteration > 0))
);


--
-- Name: jwk_set; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.jwk_set (
    casino_id uuid NOT NULL,
    jwks jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: jwk_set_snapshot; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.jwk_set_snapshot (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    jwks jsonb NOT NULL
);


--
-- Name: outcome_bet; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.outcome_bet (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    kind text NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    casino_id uuid NOT NULL,
    currency_key text NOT NULL,
    wager double precision NOT NULL,
    profit double precision NOT NULL,
    outcome_idx smallint,
    outcomes hub.outcome[] DEFAULT '{}'::hub.outcome[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    hash_id uuid NOT NULL,
    CONSTRAINT outcome_bet_check CHECK (((outcome_idx >= 0) AND (outcome_idx <= (array_length(outcomes, 1) - 1))))
);


--
-- Name: take_request; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.take_request (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    mp_take_request_id uuid NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    casino_id uuid NOT NULL,
    currency_key text NOT NULL,
    amount double precision,
    status hub.take_request_status DEFAULT 'PENDING'::hub.take_request_status NOT NULL,
    mp_status hub.mp_take_request_status DEFAULT 'PENDING'::hub.mp_take_request_status NOT NULL,
    status_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    reserved_amount double precision NOT NULL,
    mp_transfer_id uuid,
    mp_transfer_status hub.mp_transfer_status,
    transfer_needs_completion boolean DEFAULT true NOT NULL,
    transfer_completion_attempted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completion_attempt_count integer DEFAULT 0,
    insufficient_balance_error boolean DEFAULT false,
    debug text,
    refunded_at timestamp with time zone,
    transfer_failure_count integer DEFAULT 0,
    transfer_first_failure_at timestamp with time zone
);


--
-- Name: withdrawal; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.withdrawal (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    mp_transfer_id text NOT NULL,
    user_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    amount double precision NOT NULL,
    currency_key text NOT NULL,
    status hub.transfer_status_kind NOT NULL,
    status_at timestamp with time zone DEFAULT now() NOT NULL,
    withdrawal_request_id uuid NOT NULL,
    CONSTRAINT withdrawal_amount_check CHECK ((amount > (0)::double precision))
);


--
-- Name: withdrawal_request; Type: TABLE; Schema: hub; Owner: -
--

CREATE TABLE hub.withdrawal_request (
    id uuid DEFAULT hub_hidden.uuid_generate_v7() NOT NULL,
    casino_id uuid NOT NULL,
    experience_id uuid NOT NULL,
    user_id uuid NOT NULL,
    amount double precision NOT NULL,
    currency_key text NOT NULL,
    mp_transfer_id text,
    CONSTRAINT withdrawal_request_amount_check CHECK ((amount > (0)::double precision))
);


--
-- Name: pg_upgrade_schema_versions; Type: TABLE; Schema: hub_core_versions; Owner: -
--

CREATE TABLE hub_core_versions.pg_upgrade_schema_versions (
    version integer NOT NULL,
    updated_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: transfer_cursor; Type: TABLE; Schema: hub_hidden; Owner: -
--

CREATE TABLE hub_hidden.transfer_cursor (
    casino_id uuid NOT NULL,
    cursor text NOT NULL
);


--
-- Name: pg_upgrade_schema_versions; Type: TABLE; Schema: hub_user_versions; Owner: -
--

CREATE TABLE hub_user_versions.pg_upgrade_schema_versions (
    version integer NOT NULL,
    updated_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


--
-- Name: tower_game tower_game_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tower_game
    ADD CONSTRAINT tower_game_pkey PRIMARY KEY (id);


--
-- Name: api_key api_key_key_key; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.api_key
    ADD CONSTRAINT api_key_key_key UNIQUE (key);


--
-- Name: api_key api_key_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.api_key
    ADD CONSTRAINT api_key_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: balance balance_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.balance
    ADD CONSTRAINT balance_pkey PRIMARY KEY (id);


--
-- Name: bankroll bankroll_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.bankroll
    ADD CONSTRAINT bankroll_pkey PRIMARY KEY (id);


--
-- Name: casino casino_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.casino
    ADD CONSTRAINT casino_pkey PRIMARY KEY (id);


--
-- Name: casino_secret casino_secret_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.casino_secret
    ADD CONSTRAINT casino_secret_pkey PRIMARY KEY (id);


--
-- Name: chat_message chat_message_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_message
    ADD CONSTRAINT chat_message_pkey PRIMARY KEY (id);


--
-- Name: chat_mod chat_mod_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mod
    ADD CONSTRAINT chat_mod_pkey PRIMARY KEY (id);


--
-- Name: chat_mute chat_mute_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mute
    ADD CONSTRAINT chat_mute_pkey PRIMARY KEY (id);


--
-- Name: chat_rate_bucket chat_rate_bucket_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_rate_bucket
    ADD CONSTRAINT chat_rate_bucket_pkey PRIMARY KEY (id);


--
-- Name: currency currency_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.currency
    ADD CONSTRAINT currency_pkey PRIMARY KEY (key, casino_id);


--
-- Name: deposit deposit_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.deposit
    ADD CONSTRAINT deposit_pkey PRIMARY KEY (id);


--
-- Name: experience experience_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.experience
    ADD CONSTRAINT experience_pkey PRIMARY KEY (id);


--
-- Name: faucet_claim faucet_claim_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.faucet_claim
    ADD CONSTRAINT faucet_claim_pkey PRIMARY KEY (id);


--
-- Name: hash_chain hash_chain_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash_chain
    ADD CONSTRAINT hash_chain_pkey PRIMARY KEY (id);


--
-- Name: hash hash_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash
    ADD CONSTRAINT hash_pkey PRIMARY KEY (id);


--
-- Name: jwk_set jwk_set_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.jwk_set
    ADD CONSTRAINT jwk_set_pkey PRIMARY KEY (casino_id);


--
-- Name: jwk_set_snapshot jwk_set_snapshot_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.jwk_set_snapshot
    ADD CONSTRAINT jwk_set_snapshot_pkey PRIMARY KEY (id);


--
-- Name: outcome_bet outcome_bet_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_pkey PRIMARY KEY (id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- Name: take_request take_request_mp_take_request_id_key; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_mp_take_request_id_key UNIQUE (mp_take_request_id);


--
-- Name: take_request take_request_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_pkey PRIMARY KEY (id);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: withdrawal withdrawal_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_pkey PRIMARY KEY (id);


--
-- Name: withdrawal_request withdrawal_request_pkey; Type: CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal_request
    ADD CONSTRAINT withdrawal_request_pkey PRIMARY KEY (id);


--
-- Name: pg_upgrade_schema_versions pg_upgrade_schema_versions_pkey; Type: CONSTRAINT; Schema: hub_core_versions; Owner: -
--

ALTER TABLE ONLY hub_core_versions.pg_upgrade_schema_versions
    ADD CONSTRAINT pg_upgrade_schema_versions_pkey PRIMARY KEY (version);


--
-- Name: transfer_cursor transfer_cursor_pkey; Type: CONSTRAINT; Schema: hub_hidden; Owner: -
--

ALTER TABLE ONLY hub_hidden.transfer_cursor
    ADD CONSTRAINT transfer_cursor_pkey PRIMARY KEY (casino_id);


--
-- Name: pg_upgrade_schema_versions pg_upgrade_schema_versions_pkey; Type: CONSTRAINT; Schema: hub_user_versions; Owner: -
--

ALTER TABLE ONLY hub_user_versions.pg_upgrade_schema_versions
    ADD CONSTRAINT pg_upgrade_schema_versions_pkey PRIMARY KEY (version);


--
-- Name: tower_game_active_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX tower_game_active_idx ON app.tower_game USING btree (user_id, experience_id, casino_id) WHERE (status = 'ACTIVE'::app.tower_game_status);


--
-- Name: tower_game_casino_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX tower_game_casino_idx ON app.tower_game USING btree (casino_id);


--
-- Name: tower_game_experience_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX tower_game_experience_idx ON app.tower_game USING btree (experience_id);


--
-- Name: tower_game_user_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX tower_game_user_idx ON app.tower_game USING btree (user_id);


--
-- Name: active_hash_chain_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX active_hash_chain_idx ON hub.hash_chain USING btree (user_id, experience_id, casino_id) WHERE (active = true);


--
-- Name: audit_log_balance_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX audit_log_balance_id_idx ON hub.audit_log USING btree (balance_id) WHERE (balance_id IS NOT NULL);


--
-- Name: audit_log_bankroll_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX audit_log_bankroll_id_idx ON hub.audit_log USING btree (bankroll_id) WHERE (bankroll_id IS NOT NULL);


--
-- Name: balance_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX balance_casino_id_idx ON hub.balance USING btree (casino_id);


--
-- Name: balance_casino_id_user_id_experience_id_currency_key_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX balance_casino_id_user_id_experience_id_currency_key_key ON hub.balance USING btree (casino_id, user_id, experience_id, currency_key);


--
-- Name: balance_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX balance_experience_id_idx ON hub.balance USING btree (experience_id);


--
-- Name: balance_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX balance_user_id_idx ON hub.balance USING btree (user_id);


--
-- Name: bankroll_casino_id_currency_key_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX bankroll_casino_id_currency_key_key ON hub.bankroll USING btree (casino_id, currency_key);


--
-- Name: bankroll_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX bankroll_casino_id_idx ON hub.bankroll USING btree (casino_id);


--
-- Name: casino_base_url_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX casino_base_url_key ON hub.casino USING btree (base_url);


--
-- Name: casino_graphql_url_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX casino_graphql_url_key ON hub.casino USING btree (graphql_url);


--
-- Name: chat_idempotent_system_message_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX chat_idempotent_system_message_idx ON hub.chat_message USING btree (casino_id, experience_id, client_id) WHERE (type = 'system'::hub.chat_message_type);


--
-- Name: chat_idempotent_user_message_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX chat_idempotent_user_message_idx ON hub.chat_message USING btree (casino_id, experience_id, user_id, client_id) WHERE (type = 'user'::hub.chat_message_type);


--
-- Name: chat_message_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_message_casino_id_idx ON hub.chat_message USING btree (casino_id);


--
-- Name: chat_message_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_message_experience_id_idx ON hub.chat_message USING btree (experience_id);


--
-- Name: chat_message_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_message_user_id_idx ON hub.chat_message USING btree (user_id);


--
-- Name: chat_mod_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mod_casino_id_idx ON hub.chat_mod USING btree (casino_id);


--
-- Name: chat_mod_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mod_experience_id_idx ON hub.chat_mod USING btree (experience_id);


--
-- Name: chat_mod_unique_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX chat_mod_unique_idx ON hub.chat_mod USING btree (casino_id, experience_id, user_id);


--
-- Name: chat_mod_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mod_user_id_idx ON hub.chat_mod USING btree (user_id);


--
-- Name: chat_mute_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mute_casino_id_idx ON hub.chat_mute USING btree (casino_id);


--
-- Name: chat_mute_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mute_experience_id_idx ON hub.chat_mute USING btree (experience_id);


--
-- Name: chat_mute_lookup_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mute_lookup_idx ON hub.chat_mute USING btree (casino_id, experience_id, user_id) WHERE (revoked_at IS NULL);


--
-- Name: chat_mute_one_unrevoked_per_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX chat_mute_one_unrevoked_per_key ON hub.chat_mute USING btree (casino_id, experience_id, user_id) WHERE (revoked_at IS NULL);


--
-- Name: chat_mute_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_mute_user_id_idx ON hub.chat_mute USING btree (user_id);


--
-- Name: chat_rate_bucket_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_rate_bucket_casino_id_idx ON hub.chat_rate_bucket USING btree (casino_id);


--
-- Name: chat_rate_bucket_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_rate_bucket_experience_id_idx ON hub.chat_rate_bucket USING btree (experience_id);


--
-- Name: chat_rate_bucket_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX chat_rate_bucket_user_id_idx ON hub.chat_rate_bucket USING btree (user_id);


--
-- Name: chat_rate_bucket_window_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX chat_rate_bucket_window_idx ON hub.chat_rate_bucket USING btree (casino_id, experience_id, user_id, window_seconds, bucket_start);


--
-- Name: currency_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX currency_casino_id_idx ON hub.currency USING btree (casino_id);


--
-- Name: deposit_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX deposit_casino_id_idx ON hub.deposit USING btree (casino_id);


--
-- Name: deposit_casino_id_mp_transfer_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX deposit_casino_id_mp_transfer_id_key ON hub.deposit USING btree (casino_id, mp_transfer_id);


--
-- Name: deposit_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX deposit_experience_id_idx ON hub.deposit USING btree (experience_id);


--
-- Name: deposit_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX deposit_user_id_idx ON hub.deposit USING btree (user_id);


--
-- Name: experience_casino_id_mp_experience_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX experience_casino_id_mp_experience_id_key ON hub.experience USING btree (casino_id, mp_experience_id);


--
-- Name: experience_mp_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX experience_mp_experience_id_idx ON hub.experience USING btree (mp_experience_id);


--
-- Name: experience_playground_client_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX experience_playground_client_id_idx ON hub.experience USING btree (casino_id, client_id) WHERE (client_id IS NOT NULL);


--
-- Name: faucet_claim_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX faucet_claim_casino_id_idx ON hub.faucet_claim USING btree (casino_id);


--
-- Name: faucet_claim_currency_key_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX faucet_claim_currency_key_idx ON hub.faucet_claim USING btree (currency_key);


--
-- Name: faucet_claim_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX faucet_claim_experience_id_idx ON hub.faucet_claim USING btree (experience_id);


--
-- Name: faucet_claim_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX faucet_claim_user_id_idx ON hub.faucet_claim USING btree (user_id);


--
-- Name: hash_chain_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX hash_chain_casino_id_idx ON hub.hash_chain USING btree (casino_id);


--
-- Name: hash_chain_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX hash_chain_experience_id_idx ON hub.hash_chain USING btree (experience_id);


--
-- Name: hash_chain_preimage_hash_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX hash_chain_preimage_hash_idx ON hub.hash USING btree (hash_chain_id) WHERE (kind = 'PREIMAGE'::hub.hash_kind);


--
-- Name: hash_chain_terminal_hash_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX hash_chain_terminal_hash_idx ON hub.hash USING btree (hash_chain_id) WHERE (kind = 'TERMINAL'::hub.hash_kind);


--
-- Name: hash_chain_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX hash_chain_user_id_idx ON hub.hash_chain USING btree (user_id);


--
-- Name: hash_hash_chain_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX hash_hash_chain_id_idx ON hub.hash USING btree (hash_chain_id);


--
-- Name: hash_hash_chain_id_iteration_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX hash_hash_chain_id_iteration_idx ON hub.hash USING btree (hash_chain_id, iteration);


--
-- Name: jwks_snapshot_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX jwks_snapshot_casino_id_idx ON hub.jwk_set_snapshot USING btree (casino_id);


--
-- Name: outcome_bet_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX outcome_bet_casino_id_idx ON hub.outcome_bet USING btree (casino_id);


--
-- Name: outcome_bet_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX outcome_bet_experience_id_idx ON hub.outcome_bet USING btree (experience_id);


--
-- Name: outcome_bet_hash_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX outcome_bet_hash_id_idx ON hub.outcome_bet USING btree (hash_id);


--
-- Name: outcome_bet_kind_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX outcome_bet_kind_idx ON hub.outcome_bet USING btree (kind);


--
-- Name: outcome_bet_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX outcome_bet_user_id_idx ON hub.outcome_bet USING btree (user_id);


--
-- Name: session_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX session_casino_id_idx ON hub.session USING btree (casino_id);


--
-- Name: session_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX session_experience_id_idx ON hub.session USING btree (experience_id);


--
-- Name: session_key_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX session_key_idx ON hub.session USING btree (key);


--
-- Name: session_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX session_user_id_idx ON hub.session USING btree (user_id);


--
-- Name: session_user_token_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX session_user_token_idx ON hub.session USING btree (user_token);


--
-- Name: single_playground_casino_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX single_playground_casino_idx ON hub.casino USING btree ((true)) WHERE is_playground;


--
-- Name: take_request_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_casino_id_idx ON hub.take_request USING btree (casino_id);


--
-- Name: take_request_casino_id_mp_take_request_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX take_request_casino_id_mp_take_request_id_key ON hub.take_request USING btree (casino_id, mp_take_request_id);


--
-- Name: take_request_casino_id_mp_transfer_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX take_request_casino_id_mp_transfer_id_key ON hub.take_request USING btree (casino_id, mp_transfer_id) WHERE (mp_transfer_id IS NOT NULL);


--
-- Name: take_request_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_experience_id_idx ON hub.take_request USING btree (experience_id);


--
-- Name: take_request_failed_refund_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_failed_refund_idx ON hub.take_request USING btree (casino_id, status, refunded_at) WHERE ((mp_transfer_id IS NULL) AND (status = 'FAILED'::hub.take_request_status) AND (refunded_at IS NULL));


--
-- Name: take_request_status_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_status_idx ON hub.take_request USING btree (status);


--
-- Name: take_request_transfer_retry_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_transfer_retry_idx ON hub.take_request USING btree (casino_id, status, transfer_first_failure_at) WHERE ((mp_transfer_id IS NULL) AND (status = 'PROCESSING'::hub.take_request_status));


--
-- Name: take_request_updated_at_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_updated_at_idx ON hub.take_request USING btree (updated_at);


--
-- Name: take_request_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX take_request_user_id_idx ON hub.take_request USING btree (user_id);


--
-- Name: user_casino_id_mp_user_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX user_casino_id_mp_user_id_key ON hub."user" USING btree (casino_id, mp_user_id);


--
-- Name: user_playground_client_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX user_playground_client_id_idx ON hub."user" USING btree (casino_id, client_id) WHERE (client_id IS NOT NULL);


--
-- Name: withdrawal_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_casino_id_idx ON hub.withdrawal USING btree (casino_id);


--
-- Name: withdrawal_casino_id_mp_transfer_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX withdrawal_casino_id_mp_transfer_id_key ON hub.withdrawal USING btree (casino_id, mp_transfer_id);


--
-- Name: withdrawal_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_experience_id_idx ON hub.withdrawal USING btree (experience_id);


--
-- Name: withdrawal_request_casino_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_request_casino_id_idx ON hub.withdrawal_request USING btree (casino_id);


--
-- Name: withdrawal_request_casino_id_mp_transfer_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX withdrawal_request_casino_id_mp_transfer_id_key ON hub.withdrawal_request USING btree (casino_id, mp_transfer_id) WHERE (mp_transfer_id IS NOT NULL);


--
-- Name: withdrawal_request_experience_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_request_experience_id_idx ON hub.withdrawal_request USING btree (experience_id);


--
-- Name: withdrawal_request_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_request_user_id_idx ON hub.withdrawal_request USING btree (user_id);


--
-- Name: withdrawal_user_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_user_id_idx ON hub.withdrawal USING btree (user_id);


--
-- Name: withdrawal_withdrawal_request_id_idx; Type: INDEX; Schema: hub; Owner: -
--

CREATE INDEX withdrawal_withdrawal_request_id_idx ON hub.withdrawal USING btree (withdrawal_request_id);


--
-- Name: withdrawal_withdrawal_request_id_key; Type: INDEX; Schema: hub; Owner: -
--

CREATE UNIQUE INDEX withdrawal_withdrawal_request_id_key ON hub.withdrawal USING btree (withdrawal_request_id);


--
-- Name: balance balance_change_alert; Type: TRIGGER; Schema: hub; Owner: -
--

CREATE TRIGGER balance_change_alert AFTER INSERT OR UPDATE OF amount ON hub.balance FOR EACH ROW EXECUTE FUNCTION hub.notify_balance_change();


--
-- Name: casino new_casino_trigger; Type: TRIGGER; Schema: hub; Owner: -
--

CREATE TRIGGER new_casino_trigger AFTER INSERT ON hub.casino FOR EACH ROW EXECUTE FUNCTION public.notify_new_casino();


--
-- Name: deposit notify_put_trigger; Type: TRIGGER; Schema: hub; Owner: -
--

CREATE TRIGGER notify_put_trigger AFTER INSERT ON hub.deposit FOR EACH ROW EXECUTE FUNCTION public.notify_put();


--
-- Name: take_request update_take_request_timestamps; Type: TRIGGER; Schema: hub; Owner: -
--

CREATE TRIGGER update_take_request_timestamps BEFORE UPDATE ON hub.take_request FOR EACH ROW EXECUTE FUNCTION hub.update_take_request_timestamps();


--
-- Name: tower_game tower_game_casino_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tower_game
    ADD CONSTRAINT tower_game_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: tower_game tower_game_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tower_game
    ADD CONSTRAINT tower_game_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: tower_game tower_game_experience_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tower_game
    ADD CONSTRAINT tower_game_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: tower_game tower_game_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tower_game
    ADD CONSTRAINT tower_game_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: audit_log audit_log_balance_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.audit_log
    ADD CONSTRAINT audit_log_balance_id_fkey FOREIGN KEY (balance_id) REFERENCES hub.balance(id);


--
-- Name: audit_log audit_log_bankroll_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.audit_log
    ADD CONSTRAINT audit_log_bankroll_id_fkey FOREIGN KEY (bankroll_id) REFERENCES hub.bankroll(id);


--
-- Name: balance balance_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.balance
    ADD CONSTRAINT balance_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: balance balance_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.balance
    ADD CONSTRAINT balance_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: balance balance_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.balance
    ADD CONSTRAINT balance_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: balance balance_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.balance
    ADD CONSTRAINT balance_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: bankroll bankroll_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.bankroll
    ADD CONSTRAINT bankroll_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: bankroll bankroll_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.bankroll
    ADD CONSTRAINT bankroll_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: casino_secret casino_secret_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.casino_secret
    ADD CONSTRAINT casino_secret_id_fkey FOREIGN KEY (id) REFERENCES hub.casino(id);


--
-- Name: chat_message chat_message_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_message
    ADD CONSTRAINT chat_message_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: chat_message chat_message_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_message
    ADD CONSTRAINT chat_message_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: chat_message chat_message_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_message
    ADD CONSTRAINT chat_message_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: chat_mod chat_mod_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mod
    ADD CONSTRAINT chat_mod_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: chat_mod chat_mod_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mod
    ADD CONSTRAINT chat_mod_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: chat_mod chat_mod_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mod
    ADD CONSTRAINT chat_mod_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: chat_mute chat_mute_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mute
    ADD CONSTRAINT chat_mute_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: chat_mute chat_mute_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mute
    ADD CONSTRAINT chat_mute_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: chat_mute chat_mute_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_mute
    ADD CONSTRAINT chat_mute_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: chat_rate_bucket chat_rate_bucket_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_rate_bucket
    ADD CONSTRAINT chat_rate_bucket_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: chat_rate_bucket chat_rate_bucket_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_rate_bucket
    ADD CONSTRAINT chat_rate_bucket_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: chat_rate_bucket chat_rate_bucket_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.chat_rate_bucket
    ADD CONSTRAINT chat_rate_bucket_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: currency currency_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.currency
    ADD CONSTRAINT currency_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: deposit deposit_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.deposit
    ADD CONSTRAINT deposit_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: deposit deposit_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.deposit
    ADD CONSTRAINT deposit_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: deposit deposit_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.deposit
    ADD CONSTRAINT deposit_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: deposit deposit_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.deposit
    ADD CONSTRAINT deposit_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: experience experience_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.experience
    ADD CONSTRAINT experience_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: experience experience_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.experience
    ADD CONSTRAINT experience_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: faucet_claim faucet_claim_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.faucet_claim
    ADD CONSTRAINT faucet_claim_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: faucet_claim faucet_claim_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.faucet_claim
    ADD CONSTRAINT faucet_claim_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: faucet_claim faucet_claim_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.faucet_claim
    ADD CONSTRAINT faucet_claim_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: faucet_claim faucet_claim_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.faucet_claim
    ADD CONSTRAINT faucet_claim_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: hash_chain hash_chain_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash_chain
    ADD CONSTRAINT hash_chain_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: hash_chain hash_chain_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash_chain
    ADD CONSTRAINT hash_chain_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: hash_chain hash_chain_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash_chain
    ADD CONSTRAINT hash_chain_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: hash hash_hash_chain_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.hash
    ADD CONSTRAINT hash_hash_chain_id_fkey FOREIGN KEY (hash_chain_id) REFERENCES hub.hash_chain(id);


--
-- Name: jwk_set jwk_set_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.jwk_set
    ADD CONSTRAINT jwk_set_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: jwk_set_snapshot jwk_set_snapshot_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.jwk_set_snapshot
    ADD CONSTRAINT jwk_set_snapshot_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: outcome_bet outcome_bet_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: outcome_bet outcome_bet_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: outcome_bet outcome_bet_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: outcome_bet outcome_bet_hash_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_hash_id_fkey FOREIGN KEY (hash_id) REFERENCES hub.hash(id);


--
-- Name: outcome_bet outcome_bet_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.outcome_bet
    ADD CONSTRAINT outcome_bet_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: session session_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.session
    ADD CONSTRAINT session_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: session session_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.session
    ADD CONSTRAINT session_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: session session_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.session
    ADD CONSTRAINT session_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: take_request take_request_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: take_request take_request_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: take_request take_request_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: take_request take_request_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.take_request
    ADD CONSTRAINT take_request_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: user user_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub."user"
    ADD CONSTRAINT user_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: withdrawal withdrawal_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: withdrawal withdrawal_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: withdrawal withdrawal_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: withdrawal_request withdrawal_request_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal_request
    ADD CONSTRAINT withdrawal_request_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: withdrawal_request withdrawal_request_currency_key_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal_request
    ADD CONSTRAINT withdrawal_request_currency_key_casino_id_fkey FOREIGN KEY (currency_key, casino_id) REFERENCES hub.currency(key, casino_id);


--
-- Name: withdrawal_request withdrawal_request_experience_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal_request
    ADD CONSTRAINT withdrawal_request_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES hub.experience(id);


--
-- Name: withdrawal_request withdrawal_request_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal_request
    ADD CONSTRAINT withdrawal_request_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: withdrawal withdrawal_user_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_user_id_fkey FOREIGN KEY (user_id) REFERENCES hub."user"(id);


--
-- Name: withdrawal withdrawal_withdrawal_request_id_fkey; Type: FK CONSTRAINT; Schema: hub; Owner: -
--

ALTER TABLE ONLY hub.withdrawal
    ADD CONSTRAINT withdrawal_withdrawal_request_id_fkey FOREIGN KEY (withdrawal_request_id) REFERENCES hub.withdrawal_request(id);


--
-- Name: transfer_cursor transfer_cursor_casino_id_fkey; Type: FK CONSTRAINT; Schema: hub_hidden; Owner: -
--

ALTER TABLE ONLY hub_hidden.transfer_cursor
    ADD CONSTRAINT transfer_cursor_casino_id_fkey FOREIGN KEY (casino_id) REFERENCES hub.casino(id);


--
-- Name: tower_game; Type: ROW SECURITY; Schema: app; Owner: -
--

ALTER TABLE app.tower_game ENABLE ROW LEVEL SECURITY;

--
-- Name: tower_game tower_game_select; Type: POLICY; Schema: app; Owner: -
--

CREATE POLICY tower_game_select ON app.tower_game FOR SELECT USING ((( SELECT hub_hidden.is_operator() AS is_operator) OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: api_key; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.api_key ENABLE ROW LEVEL SECURITY;

--
-- Name: balance; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.balance ENABLE ROW LEVEL SECURITY;

--
-- Name: bankroll; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.bankroll ENABLE ROW LEVEL SECURITY;

--
-- Name: casino; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.casino ENABLE ROW LEVEL SECURITY;

--
-- Name: casino_secret; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.casino_secret ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_message; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.chat_message ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_mod; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.chat_mod ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_mute; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.chat_mute ENABLE ROW LEVEL SECURITY;

--
-- Name: currency; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.currency ENABLE ROW LEVEL SECURITY;

--
-- Name: deposit; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.deposit ENABLE ROW LEVEL SECURITY;

--
-- Name: experience; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.experience ENABLE ROW LEVEL SECURITY;

--
-- Name: faucet_claim; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.faucet_claim ENABLE ROW LEVEL SECURITY;

--
-- Name: hash; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.hash ENABLE ROW LEVEL SECURITY;

--
-- Name: hash_chain; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.hash_chain ENABLE ROW LEVEL SECURITY;

--
-- Name: jwk_set; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.jwk_set ENABLE ROW LEVEL SECURITY;

--
-- Name: jwk_set_snapshot; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.jwk_set_snapshot ENABLE ROW LEVEL SECURITY;

--
-- Name: outcome_bet; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.outcome_bet ENABLE ROW LEVEL SECURITY;

--
-- Name: api_key select_api_key; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_api_key ON hub.api_key FOR SELECT USING (hub_hidden.is_operator());


--
-- Name: balance select_balance; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_balance ON hub.balance FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: bankroll select_bankroll; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_bankroll ON hub.bankroll FOR SELECT USING (true);


--
-- Name: casino select_casino; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_casino ON hub.casino FOR SELECT USING (true);


--
-- Name: casino_secret select_casino_secret; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_casino_secret ON hub.casino_secret FOR SELECT USING (hub_hidden.is_operator());


--
-- Name: chat_message select_chat_message; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_chat_message ON hub.chat_message FOR SELECT USING ((hub_hidden.is_operator() OR ((hidden_at IS NULL) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id())) OR hub_hidden.is_experience_owner()));


--
-- Name: chat_mod select_chat_mod; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_chat_mod ON hub.chat_mod FOR SELECT USING ((hub_hidden.is_operator() OR hub_hidden.is_experience_owner()));


--
-- Name: chat_mute select_chat_mute; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_chat_mute ON hub.chat_mute FOR SELECT USING ((hub_hidden.is_operator() OR (hub_hidden.current_user_id() = user_id) OR hub_hidden.is_experience_owner() OR (EXISTS ( SELECT 1
   FROM hub.chat_mod
  WHERE ((chat_mod.user_id = hub_hidden.current_user_id()) AND (chat_mod.casino_id = chat_mute.casino_id) AND (chat_mod.experience_id = chat_mute.experience_id))))));


--
-- Name: currency select_currency; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_currency ON hub.currency FOR SELECT USING (true);


--
-- Name: deposit select_deposit; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_deposit ON hub.deposit FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: experience select_experience; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_experience ON hub.experience FOR SELECT USING (true);


--
-- Name: faucet_claim select_faucet_claim; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_faucet_claim ON hub.faucet_claim FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: hash select_hash; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_hash ON hub.hash FOR SELECT USING ((hub_hidden.is_operator() OR (EXISTS ( SELECT 1
   FROM hub.hash_chain
  WHERE ((hash_chain.id = hash.hash_chain_id) AND (hash_chain.user_id = hub_hidden.current_user_id()) AND (hash_chain.experience_id = hub_hidden.current_experience_id()) AND (hash_chain.casino_id = hub_hidden.current_casino_id()))))));


--
-- Name: hash_chain select_hash_chain; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_hash_chain ON hub.hash_chain FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: jwk_set select_jwks; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_jwks ON hub.jwk_set FOR SELECT USING (hub_hidden.is_operator());


--
-- Name: jwk_set_snapshot select_jwks_snapshot; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_jwks_snapshot ON hub.jwk_set_snapshot FOR SELECT USING (hub_hidden.is_operator());


--
-- Name: outcome_bet select_outcome_bet; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_outcome_bet ON hub.outcome_bet FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: session select_session; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_session ON hub.session FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: take_request select_take_request; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_take_request ON hub.take_request FOR SELECT USING ((hub_hidden.is_operator() OR (user_id = hub_hidden.current_user_id())));


--
-- Name: user select_user; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_user ON hub."user" FOR SELECT USING (true);


--
-- Name: withdrawal select_withdrawal; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_withdrawal ON hub.withdrawal FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: withdrawal_request select_withdrawal_request; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY select_withdrawal_request ON hub.withdrawal_request FOR SELECT USING ((hub_hidden.is_operator() OR ((user_id = hub_hidden.current_user_id()) AND (experience_id = hub_hidden.current_experience_id()) AND (casino_id = hub_hidden.current_casino_id()))));


--
-- Name: session; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.session ENABLE ROW LEVEL SECURITY;

--
-- Name: take_request; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.take_request ENABLE ROW LEVEL SECURITY;

--
-- Name: bankroll update_bankroll; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY update_bankroll ON hub.bankroll FOR UPDATE USING (hub_hidden.is_operator());


--
-- Name: casino update_casino; Type: POLICY; Schema: hub; Owner: -
--

CREATE POLICY update_casino ON hub.casino FOR UPDATE USING (hub_hidden.is_operator());


--
-- Name: user; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub."user" ENABLE ROW LEVEL SECURITY;

--
-- Name: withdrawal; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.withdrawal ENABLE ROW LEVEL SECURITY;

--
-- Name: withdrawal_request; Type: ROW SECURITY; Schema: hub; Owner: -
--

ALTER TABLE hub.withdrawal_request ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA app; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app TO app_postgraphile;


--
-- Name: SCHEMA hub; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA hub TO app_postgraphile;


--
-- Name: SCHEMA hub_hidden; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA hub_hidden TO app_postgraphile;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_postgraphile;


--
-- Name: TABLE tower_game; Type: ACL; Schema: app; Owner: -
--

GRANT SELECT ON TABLE app.tower_game TO app_postgraphile;


--
-- Name: TABLE chat_mute; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.chat_mute TO app_postgraphile;


--
-- Name: TABLE session; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.session TO app_postgraphile;


--
-- Name: TABLE active_session; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.active_session TO app_postgraphile;


--
-- Name: TABLE api_key; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.api_key TO app_postgraphile;


--
-- Name: TABLE balance; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.balance TO app_postgraphile;


--
-- Name: TABLE bankroll; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT,UPDATE ON TABLE hub.bankroll TO app_postgraphile;


--
-- Name: TABLE "user"; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub."user" TO app_postgraphile;


--
-- Name: TABLE casino; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT,UPDATE ON TABLE hub.casino TO app_postgraphile;


--
-- Name: TABLE casino_secret; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.casino_secret TO app_postgraphile;


--
-- Name: TABLE chat_message; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.chat_message TO app_postgraphile;


--
-- Name: TABLE chat_mod; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.chat_mod TO app_postgraphile;


--
-- Name: TABLE currency; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.currency TO app_postgraphile;


--
-- Name: TABLE deposit; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.deposit TO app_postgraphile;


--
-- Name: TABLE experience; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.experience TO app_postgraphile;


--
-- Name: TABLE faucet_claim; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.faucet_claim TO app_postgraphile;


--
-- Name: TABLE hash; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.hash TO app_postgraphile;


--
-- Name: TABLE hash_chain; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.hash_chain TO app_postgraphile;


--
-- Name: TABLE jwk_set; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.jwk_set TO app_postgraphile;


--
-- Name: TABLE jwk_set_snapshot; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.jwk_set_snapshot TO app_postgraphile;


--
-- Name: TABLE outcome_bet; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.outcome_bet TO app_postgraphile;


--
-- Name: TABLE take_request; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.take_request TO app_postgraphile;


--
-- Name: TABLE withdrawal; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.withdrawal TO app_postgraphile;


--
-- Name: TABLE withdrawal_request; Type: ACL; Schema: hub; Owner: -
--

GRANT SELECT ON TABLE hub.withdrawal_request TO app_postgraphile;


--
-- PostgreSQL database dump complete
--

\unrestrict ehvVQg9sXCykDSau5GMOyA6vuPTMNfwbfezpaX3hHR0PmymIHkBhzbz83L7vY1g

