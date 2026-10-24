-- Minimal stand-in for what a Supabase project provides, so the migrations
-- can be tested against a plain Postgres container.

create role anon nologin;
create role authenticated nologin;

create schema auth;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb not null default '{}'
);

-- Supabase reads the user id from the request's JWT claims.
create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid
$$;

grant usage on schema public, auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

-- Supabase's default privileges: API roles get table and function access,
-- and RLS / explicit revokes decide what they can actually do.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
