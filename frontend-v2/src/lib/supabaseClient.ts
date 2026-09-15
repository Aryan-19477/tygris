import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

/**
 * True only when both Supabase env vars are present. The Ranger Ops
 * integration (see supabase/migrations/0001_ranger_ops.sql) is built
 * against placeholder env vars until the user creates the actual Supabase
 * project and pastes real keys into .env.local — until then this stays
 * false and callers should render a "not connected" state instead of
 * calling `supabase`.
 */
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

// When unconfigured, createClient still needs syntactically valid args to
// avoid throwing at import time — the placeholder URL is never actually
// reached because callers gate all usage behind isSupabaseConfigured.
export const supabase = createClient(
  supabaseUrl || "https://placeholder.supabase.co",
  supabaseAnonKey || "placeholder-anon-key"
);
