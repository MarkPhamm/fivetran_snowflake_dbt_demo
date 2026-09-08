-- =============================================================================
-- dbt role, user, and write schemas on FIVETRAN_DEMO
-- =============================================================================
-- FIVETRAN_USER is for Fivetran only. dbt gets its own service user so
-- transforms cannot create Fivetran-owned objects, and you can rotate keys
-- independently.
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

USE ROLE SYSADMIN;

COMMIT;
