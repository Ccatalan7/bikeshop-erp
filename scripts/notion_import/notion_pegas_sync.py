#!/usr/bin/env python3
"""Quarantined legacy Notion-to-workshop importer."""

raise SystemExit(
    "This legacy importer is quarantined: it targeted an obsolete Supabase "
    "project and performed non-atomic direct writes. Build a tracked, tested "
    "tenant-scoped importer against the canonical workshop aggregate before "
    "syncing Notion data. See docs/development/SUPABASE_WORKFLOW.md."
)
