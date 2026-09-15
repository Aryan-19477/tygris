"""
Thin wrapper around the Supabase Python client.

The Ranger field app (Flutter) writes patrol/observation data directly into
a Supabase Postgres project (see tygris/supabase/migrations/0001_ranger_ops.sql).
This backend reads that data back out and never receives inbound webhooks
from Supabase (it's cloud-hosted, this server is local) — see
territory_check.py and routes_ranger_ops.py for the polling logic.

Until the user pastes real project credentials into backend/.env, the
SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY env vars are empty. Every caller
here must treat that as an expected, recoverable state — get_supabase_client()
returns None instead of raising so callers can log a warning and skip work
rather than crash the whole backend.
"""

import os
import logging
from typing import Optional

logger = logging.getLogger("tygris.supabase")

_client = None
_client_init_attempted = False
_warned_missing_config = False

try:
    from supabase import create_client, Client  # type: ignore
    _SUPABASE_SDK_AVAILABLE = True
except ImportError:
    Client = None  # type: ignore
    _SUPABASE_SDK_AVAILABLE = False


def get_supabase_client() -> Optional["Client"]:
    """
    Returns a cached Supabase client, or None if the SDK isn't installed or
    SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY aren't configured yet. Never
    raises — callers should check `if client is None` and degrade gracefully.
    """
    global _client, _client_init_attempted, _warned_missing_config

    if _client is not None:
        return _client

    if not _SUPABASE_SDK_AVAILABLE:
        if not _warned_missing_config:
            logger.warning(
                "[ranger-ops] 'supabase' package not installed — /api/ranger/* routes "
                "are disabled. Run: pip install supabase python-dotenv"
            )
            _warned_missing_config = True
        return None

    if _client_init_attempted:
        return None

    _client_init_attempted = True

    if not os.environ.get("SUPABASE_URL"):
        try:
            from dotenv import load_dotenv
            env_file = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
            if os.path.exists(env_file):
                load_dotenv(os.path.abspath(env_file))
        except Exception:
            pass

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip() or os.environ.get("SUPABASE_ANON_KEY", "").strip()

    if not url or not key:
        if not _warned_missing_config:
            logger.warning(
                "[ranger-ops] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set — "
                "ranger-ops features disabled until backend/.env is filled in "
                "(see backend/.env.example and supabase/migrations/0001_ranger_ops.sql)."
            )
            _warned_missing_config = True
        return None

    try:
        _client = create_client(url, key)
        logger.info("[ranger-ops] Supabase client initialized.")
        return _client
    except Exception as exc:
        logger.warning(f"[ranger-ops] Failed to initialize Supabase client: {exc}")
        return None
