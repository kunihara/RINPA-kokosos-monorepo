-- KokoSOS minimal schema (Supabase/Postgres)

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  apple_sub text unique,
  apns_token text,
  email text,
  created_at timestamptz not null default now()
);

create table if not exists contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  email text not null,
  role text,
  capabilities jsonb default '{}'::jsonb
);

create table if not exists alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null check (type in ('emergency','going_home')),
  status text not null check (status in ('active','ended','timeout')) default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  max_duration_sec integer not null default 3600,
  revoked_at timestamptz
);

create table if not exists locations (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references alerts(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  accuracy_m double precision,
  battery_pct integer,
  captured_at timestamptz not null default now()
);

create index if not exists idx_locations_alert_time on locations(alert_id, captured_at desc);

create table if not exists deliveries (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references alerts(id) on delete cascade,
  contact_id uuid not null references contacts(id) on delete cascade,
  channel text not null check (channel in ('push','email')),
  status text,
  created_at timestamptz not null default now()
);

create table if not exists revocations (
  alert_id uuid primary key references alerts(id) on delete cascade,
  revoked_at timestamptz not null default now()
);

-- Receiver reactions (preset replies)
create table if not exists reactions (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references alerts(id) on delete cascade,
  contact_id uuid not null,
  preset text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_reactions_alert_time on reactions(alert_id, created_at desc);

-- Retention: purge alerts/locations/deliveries older than 48h
create or replace function purge_old_data() returns void language plpgsql as $$
begin
  delete from locations where captured_at < now() - interval '48 hours';
  delete from deliveries where created_at < now() - interval '48 hours';
  delete from alerts where coalesce(ended_at, started_at) < now() - interval '48 hours';
end;$$;

-- Schedule this via Supabase cron: select purge_old_data();
