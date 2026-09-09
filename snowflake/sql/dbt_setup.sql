-- =============================================================================
-- dbt schemas on FIVETRAN_DEMO, plus a local-development role and user
-- =============================================================================
-- Two things run this dbt project:
--
--   1. Fivetran Transformations for dbt Core (the scheduled builds). Fivetran
--      generates its own profiles.yml from the DESTINATION credentials, so the
--      scheduled models are built by FIVETRAN_USER / FIVETRAN_ROLE. That role
--      therefore needs write access on TRANSFORM and SERVE, granted below.
--   2. Your laptop, for development (dbt debug / dbt run before you push).
--      That uses DBT_USER so you are not handing your dev machine the
--      destination's key.
--
-- Creates:
--   DBT_ROLE
--   DBT_USER          TYPE = SERVICE (attach a key the same way as Fivetran)
--   schemas TRANSFORM and SERVE
--
-- Grants read on every current and future schema/table in FIVETRAN_DEMO
-- (covers L1_LANDING after Fivetran syncs) and write on TRANSFORM / SERVE.
-- Reuses FIVETRAN_WAREHOUSE so the trial does not pay for a second warehouse.
--
-- Run as ACCOUNTADMIN (or SECURITYADMIN + SYSADMIN). Select the entire script.
-- Then generate a local key pair and attach the public key with dbt_keypair.sql.
-- Snowflake never creates the .p8 file. See snowflake/README.md section 5.
-- =============================================================================

BEGIN;

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS DBT_ROLE;
GRANT ROLE DBT_ROLE TO ROLE SYSADMIN;

CREATE USER IF NOT EXISTS DBT_USER
    TYPE = SERVICE
    DEFAULT_ROLE = DBT_ROLE
    DEFAULT_WAREHOUSE = FIVETRAN_WAREHOUSE
    COMMENT = 'dbt Core service user for OMS transforms';

GRANT ROLE DBT_ROLE TO USER DBT_USER;

USE ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE FIVETRAN_WAREHOUSE TO ROLE DBT_ROLE;

GRANT USAGE ON DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT CREATE SCHEMA ON DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;

USE DATABASE FIVETRAN_DEMO;

CREATE SCHEMA IF NOT EXISTS TRANSFORM
    COMMENT = 'dbt staging and facts';

CREATE SCHEMA IF NOT EXISTS SERVE
    COMMENT = 'dbt served marts';

GRANT USAGE ON SCHEMA TRANSFORM TO ROLE DBT_ROLE;
GRANT USAGE ON SCHEMA SERVE TO ROLE DBT_ROLE;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA TRANSFORM TO ROLE DBT_ROLE;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA SERVE TO ROLE DBT_ROLE;

-- Landing schema may not exist until the first Fivetran sync. These future
-- grants apply when Fivetran creates L1_LANDING (or any other schema).
GRANT USAGE ON ALL SCHEMAS IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT SELECT ON ALL VIEWS IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE VIEWS IN DATABASE FIVETRAN_DEMO TO ROLE DBT_ROLE;

-- Scheduled runs come from Fivetran Transformations, which authenticates as the
-- destination user. Without these, a dbt job fails on the first model with
-- "Object does not exist or not authorized" on TRANSFORM.
GRANT USAGE ON SCHEMA TRANSFORM TO ROLE FIVETRAN_ROLE;
GRANT USAGE ON SCHEMA SERVE TO ROLE FIVETRAN_ROLE;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA TRANSFORM TO ROLE FIVETRAN_ROLE;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA SERVE TO ROLE FIVETRAN_ROLE;

USE ROLE SECURITYADMIN;

-- A table can only be replaced by the role that owns it. If you built the
-- models locally first, DBT_ROLE owns them and Fivetran cannot overwrite them.
-- Inheriting DBT_ROLE lets Fivetran take over those objects. For the reverse
-- case (Fivetran ran first, now you want to build locally) see
-- snowflake/README.md "Who owns TRANSFORM and SERVE".
GRANT ROLE DBT_ROLE TO ROLE FIVETRAN_ROLE;

USE ROLE SYSADMIN;

COMMIT;
