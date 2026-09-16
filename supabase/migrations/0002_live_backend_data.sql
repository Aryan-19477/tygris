-- TYGRIS: live backend data (persists what Render's ephemeral disk can't).
--
-- Scope is intentionally narrow: only data written at RUNTIME by real
-- /api/identify calls, ranger-triggered alerts, and human review decisions.
-- The 311 camera_stations, the 44-tiger seed roster, and the historical
-- demo simulation all stay in the committed backend/data/pench_unified.db
-- seed file -- that's static, ships with the repo, and is restored fresh
-- on every deploy, so it never needs to live in Supabase.
--
-- Run this whole file once in the Supabase project's SQL editor
-- (Dashboard -> SQL Editor -> New query -> paste -> Run).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Human-in-the-loop review queue (open-world re-ID matches awaiting a
-- reviewer decision). Mirrors routes_review.py's review_queue table.
-- ---------------------------------------------------------------------

create table if not exists review_queue (
  item_id text primary key,
  station_id text,
  zone text,
  uploaded_image text,
  nearest_distance numeric,
  candidates jsonb not null default '[]'::jsonb,
  reason text,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_review_queue_resolved on review_queue(resolved);

-- ---------------------------------------------------------------------
-- Live event log: every real sighting/alert recorded AFTER deploy --
-- auto-matched camera identifications, patrol buffer-zone alerts,
-- territory-check alerts. This is the delta on top of the static seed
-- sightings, not a replacement for them.
-- ---------------------------------------------------------------------

create table if not exists live_sightings (
  event_id text primary key,
  tiger_id text,
  camera_id text,
  latitude double precision,
  longitude double precision,
  zone text,
  flank_side text,
  alert_level text,
  threat_reason text,
  image_path text,
  source_ref text,
  acknowledged boolean not null default false,
  "timestamp" timestamptz not null default now()
);
create unique index if not exists idx_live_sightings_source_ref
  on live_sightings(source_ref) where source_ref is not null;
create index if not exists idx_live_sightings_tiger on live_sightings(tiger_id);
create index if not exists idx_live_sightings_acknowledged on live_sightings(acknowledged);

-- ---------------------------------------------------------------------
-- New tiger identities enrolled via review-queue resolution -- i.e. NOT
-- part of the static 44-tiger seed roster, so they need somewhere durable
-- to live.
-- ---------------------------------------------------------------------

create table if not exists tiger_enrollments (
  tiger_id text primary key,
  name text,
  sex text default 'UNKNOWN',
  life_stage text default 'UNKNOWN',
  territorial_status text default 'UNKNOWN',
  thumbnail text,
  core_centroid_lat double precision,
  core_centroid_lon double precision,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Row Level Security -- same MVP posture as 0001_ranger_ops.sql: no auth
-- yet, so the anon/service key can read+write directly. Tighten before
-- a real public launch.
-- ---------------------------------------------------------------------

alter table review_queue enable row level security;
alter table live_sightings enable row level security;
alter table tiger_enrollments enable row level security;

create policy "anon read review_queue" on review_queue for select using (true);
create policy "anon write review_queue" on review_queue for insert with check (true);
create policy "anon update review_queue" on review_queue for update using (true);

create policy "anon read live_sightings" on live_sightings for select using (true);
create policy "anon write live_sightings" on live_sightings for insert with check (true);
create policy "anon update live_sightings" on live_sightings for update using (true);

create policy "anon read tiger_enrollments" on tiger_enrollments for select using (true);
create policy "anon write tiger_enrollments" on tiger_enrollments for insert with check (true);

-- ---------------------------------------------------------------------
-- Storage: real captured camera-trap photos (currently written to local
-- disk at backend/data/captures/ -- lost on every Render redeploy).
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('captures', 'captures', true)
on conflict (id) do nothing;

create policy "anon read captures" on storage.objects for select using (bucket_id = 'captures');
create policy "anon upload captures" on storage.objects for insert with check (bucket_id = 'captures');
b