-- TYGRIS Ranger Operations schema.
--
-- Mirrors (field-for-field, same table/column names) the dormant tables
-- already scaffolded in backend/data/pench_unified.db (rangers, teams,
-- team_members, patrols, gps_track_points, observations, photos), so the
-- FastAPI backend can eventually read/write either store with the same
-- shape. Adds tasks, camera_inspections, and territory_checks — the
-- admin-side "is this tiger still here or did it move?" intelligence
-- computed by the backend whenever a ranger logs a wildlife sighting.
--
-- Run this whole file once in the Supabase project's SQL editor
-- (Dashboard -> SQL Editor -> New query -> paste -> Run).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Core ranger-ops tables
-- ---------------------------------------------------------------------

create table if not exists rangers (
  ranger_id text primary key,
  name text not null,
  badge_number text,
  phone text,
  default_beat text,
  role text not null default 'ranger',
  team_id text,
  avatar_seed text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists teams (
  team_id text primary key,
  team_name text not null,
  leader_ranger_id text references rangers(ranger_id),
  beat_or_zone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table rangers
  add constraint rangers_team_id_fkey foreign key (team_id) references teams(team_id) deferrable initially deferred;

create table if not exists team_members (
  team_id text not null references teams(team_id) on delete cascade,
  ranger_id text not null references rangers(ranger_id) on delete cascade,
  primary key (team_id, ranger_id)
);

create table if not exists patrols (
  patrol_id text primary key,
  ranger_id text not null references rangers(ranger_id),
  team_id text references teams(team_id),
  beat_area text,
  patrol_type text,
  patrol_method text,
  armed boolean not null default false,
  status text not null default 'active',
  start_time timestamptz,
  end_time timestamptz,
  start_lat double precision,
  start_lon double precision,
  end_lat double precision,
  end_lon double precision,
  distance_km double precision default 0,
  duration_seconds integer default 0,
  coverage_area_km2 double precision,
  notes text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists gps_track_points (
  point_id text primary key,
  patrol_id text not null references patrols(patrol_id) on delete cascade,
  lat double precision not null,
  lon double precision not null,
  altitude double precision,
  accuracy double precision,
  "timestamp" timestamptz not null,
  sequence_num integer not null
);
create index if not exists idx_gps_track_points_patrol on gps_track_points(patrol_id);

create table if not exists observations (
  observation_id text primary key,
  patrol_id text references patrols(patrol_id) on delete set null,
  ranger_id text not null references rangers(ranger_id),
  obs_type text not null,
  species_category text,
  severity text,
  lat double precision,
  lon double precision,
  "timestamp" timestamptz not null,
  structured_attrs jsonb,
  remarks text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now()
);
create index if not exists idx_observations_patrol on observations(patrol_id);
create index if not exists idx_observations_type on observations(obs_type);
create index if not exists idx_observations_created on observations(created_at);

create table if not exists photos (
  photo_id text primary key,
  observation_id text references observations(observation_id) on delete cascade,
  patrol_id text references patrols(patrol_id) on delete set null,
  camera_inspection_id text,
  storage_path text not null,
  public_url text,
  lat double precision,
  lon double precision,
  "timestamp" timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists tasks (
  task_id text primary key,
  title text not null,
  instructions text,
  assigned_ranger_id text references rangers(ranger_id),
  lat double precision,
  lon double precision,
  location_label text,
  status text not null default 'assigned',
  due_at timestamptz,
  completed_at timestamptz,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists camera_inspections (
  inspection_id text primary key,
  station_camera_id text not null,
  ranger_id text not null references rangers(ranger_id),
  "timestamp" timestamptz not null,
  battery_level integer,
  storage_level integer,
  status text,
  issue_notes text,
  maintenance_notes text,
  action_taken text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now()
);

alter table photos
  add constraint photos_camera_inspection_id_fkey foreign key (camera_inspection_id) references camera_inspections(inspection_id) on delete cascade;

-- ---------------------------------------------------------------------
-- Admin-side intelligence: "is the tiger still here, or did it move?"
-- Computed by the FastAPI backend (backend/app/services/territory_check.py)
-- against the existing camera-network + sightings data whenever a ranger
-- logs a wildlife-sighting/sign observation. One row per check run (a
-- given observation can be re-checked, so this is append-only history,
-- not a 1:1 update).
-- ---------------------------------------------------------------------

create table if not exists territory_checks (
  check_id uuid primary key default gen_random_uuid(),
  observation_id text not null references observations(observation_id) on delete cascade,
  resident_tiger_id text,
  nearest_cameras jsonb not null default '[]'::jsonb,
  status text not null,
  summary text not null,
  computed_at timestamptz not null default now()
);
create index if not exists idx_territory_checks_observation on territory_checks(observation_id);

-- ---------------------------------------------------------------------
-- Realtime: let the Admin dashboard subscribe to new ranger activity.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table observations;
alter publication supabase_realtime add table patrols;
alter publication supabase_realtime add table territory_checks;

-- ---------------------------------------------------------------------
-- Row Level Security.
--
-- MVP posture: the Ranger app has no login yet (single seeded on-device
-- ranger identity), so writes are allowed with just the anon key. This is
-- intentionally permissive for the demo phase — anyone holding the anon
-- key can insert ranger records. Before any real deployment, replace
-- these with Supabase Auth-backed policies keyed to auth.uid() /
-- ranger_id ownership.
-- ---------------------------------------------------------------------

alter table rangers enable row level security;
alter table teams enable row level security;
alter table team_members enable row level security;
alter table patrols enable row level security;
alter table gps_track_points enable row level security;
alter table observations enable row level security;
alter table photos enable row level security;
alter table tasks enable row level security;
alter table camera_inspections enable row level security;
alter table territory_checks enable row level security;

create policy "anon read rangers" on rangers for select using (true);
create policy "anon write rangers" on rangers for insert with check (true);
create policy "anon update rangers" on rangers for update using (true);

create policy "anon read teams" on teams for select using (true);
create policy "anon write teams" on teams for insert with check (true);

create policy "anon read team_members" on team_members for select using (true);
create policy "anon write team_members" on team_members for insert with check (true);

create policy "anon read patrols" on patrols for select using (true);
create policy "anon write patrols" on patrols for insert with check (true);
create policy "anon update patrols" on patrols for update using (true);

create policy "anon read gps_track_points" on gps_track_points for select using (true);
create policy "anon write gps_track_points" on gps_track_points for insert with check (true);

create policy "anon read observations" on observations for select using (true);
create policy "anon write observations" on observations for insert with check (true);
create policy "anon update observations" on observations for update using (true);

create policy "anon read photos" on photos for select using (true);
create policy "anon write photos" on photos for insert with check (true);

create policy "anon read tasks" on tasks for select using (true);
create policy "anon write tasks" on tasks for insert with check (true);
create policy "anon update tasks" on tasks for update using (true);

create policy "anon read camera_inspections" on camera_inspections for select using (true);
create policy "anon write camera_inspections" on camera_inspections for insert with check (true);

create policy "anon read territory_checks" on territory_checks for select using (true);
create policy "service write territory_checks" on territory_checks for insert with check (true);

-- ---------------------------------------------------------------------
-- Storage: ranger-captured photos (observations, camera inspections,
-- task evidence). Public bucket for demo simplicity — tighten with
-- signed URLs + auth once real accounts exist.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('ranger-photos', 'ranger-photos', true)
on conflict (id) do nothing;

create policy "anon read ranger-photos" on storage.objects for select using (bucket_id = 'ranger-photos');
create policy "anon upload ranger-photos" on storage.objects for insert with check (bucket_id = 'ranger-photos');
