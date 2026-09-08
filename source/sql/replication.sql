-- =============================================================================
-- Fivetran incremental sync: publication + replication slot
-- =============================================================================
-- Fivetran can do a one-time SELECT of every table (query-based). For ongoing
-- syncs it prefers logical replication: Postgres writes row changes to the WAL,
-- and Fivetran reads only those changes.
--
-- Two objects make that work:
--
--   publication        which tables are in the change stream
--   replication slot   a bookmark so WAL is not discarded before Fivetran
--                      has read it (even if Fivetran is offline for a bit)
--
-- pgoutput is the built-in decoder Fivetran uses to turn WAL bytes into rows.
--
-- Names below must match the Fivetran Postgres connector form:
--   Replication Slot  = replication_slot_01
--   Publication Name  = publication_01
--
-- Run in the Neon SQL Editor on database fivetran_source, AFTER schema.sql
-- and insert.sql. Logical replication must already be enabled in the Neon
-- Console (Settings -> Logical Replication). Confirm with:
--   SHOW wal_level;   -- expect: logical
--
-- Use a direct Neon host (no "-pooler" in the hostname). Logical replication
-- needs a persistent session; PgBouncer pooling is not compatible.
--
-- Official guides:
--   https://fivetran.com/docs/connectors/databases/postgresql/setup-guide
--   https://neon.com/docs/guides/logical-replication-fivetran
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Replica identity
-- These OMS tables have no PRIMARY KEY. UPDATE/DELETE in the WAL then have
-- no key to identify the row. REPLICA IDENTITY FULL logs the whole old row
-- so Fivetran can match it. Skip this if you later add primary keys.
-- ---------------------------------------------------------------------------
ALTER TABLE l1_landing.customers REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.dates REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.employees REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.products REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.suppliers REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.stores REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.orderitems REPLICA IDENTITY FULL;
ALTER TABLE l1_landing.orders REPLICA IDENTITY FULL;

-- ---------------------------------------------------------------------------
-- 2. Publication
-- A publication is the allow-list of tables whose INSERT/UPDATE/DELETE
-- events go to subscribers. FOR ALL TABLES covers current and future tables
-- in this database (fine for a demo). Tighten to named tables in production.
--
-- Drop first so you can re-run this file after a botched setup.
-- Create the publication BEFORE the slot (Fivetran's required order).
-- ---------------------------------------------------------------------------
DROP PUBLICATION IF EXISTS publication_01;

CREATE PUBLICATION publication_01 FOR ALL TABLES;

-- ---------------------------------------------------------------------------
-- 3. Replication slot
-- The slot stores Fivetran's WAL offset. If the slot is missing, Fivetran
-- cannot start logical replication. If an unused slot is left behind, WAL
-- accumulates and storage grows.
--
-- Drop only when the slot already exists (pg_drop_replication_slot errors
-- on the first run otherwise). Then create a dedicated pgoutput slot.
-- One Fivetran connector per slot. Do not share this slot with another tool.
-- ---------------------------------------------------------------------------
SELECT pg_drop_replication_slot(slot_name)
FROM pg_replication_slots
WHERE slot_name = 'replication_slot_01';

SELECT *
FROM pg_create_logical_replication_slot('replication_slot_01', 'pgoutput');

-- ---------------------------------------------------------------------------
-- 4. Sanity checks (optional; safe to run anytime)
-- ---------------------------------------------------------------------------
SHOW wal_level;

SELECT pubname, puballtables
FROM pg_publication
WHERE pubname = 'publication_01';

SELECT slot_name, plugin, slot_type, active, restart_lsn
FROM pg_replication_slots
WHERE slot_name = 'replication_slot_01';
