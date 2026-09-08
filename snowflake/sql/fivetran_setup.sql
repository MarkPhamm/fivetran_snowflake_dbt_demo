-- =============================================================================
-- Fivetran destination setup (Snowflake)
-- =============================================================================
-- Official guide:
--   https://fivetran.com/docs/destinations/snowflake/setup-guide
--
-- Why this script exists
--   Fivetran is a third-party service. Do not give it ACCOUNTADMIN or your
--   personal login. Create a dedicated user, role, warehouse, and database
--   so Fivetran can only write into FIVETRAN_DEMO and run FIVETRAN_WAREHOUSE.
--
-- What this creates
--   FIVETRAN_ROLE       least-privilege role Fivetran assumes
--   FIVETRAN_USER       SERVICE user (key-pair auth, no password)
--   FIVETRAN_WAREHOUSE  exclusive XSMALL compute, auto-suspend 60s
--   FIVETRAN_DEMO       destination database (Fivetran creates schemas here)
--
-- How to run
--   Sign in to Snowsight as the trial ACCOUNTADMIN (or any user who can
--   assume SECURITYADMIN and SYSADMIN). Select this entire script, then Run.
--   Snowsight only executes highlighted statements.
--
-- After this script
--   Attach a public key with fivetran_keypair.sql, then confirm with verify.sql.
-- =============================================================================

-- One transaction so a mid-script failure does not leave half-created objects.
BEGIN;

-- Session variables. Snowflake object names are stored uppercase unless quoted.
-- IDENTIFIER($var) turns the string into an object name in later statements.
SET ROLE_NAME = 'FIVETRAN_ROLE';
SET USER_NAME = 'FIVETRAN_USER';
SET WAREHOUSE_NAME = 'FIVETRAN_WAREHOUSE';
SET DATABASE_NAME = 'FIVETRAN_DEMO';

-- ---------------------------------------------------------------------------
-- Users and roles (SECURITYADMIN)
-- Snowflake splits admin work: SECURITYADMIN owns users/roles.
-- SYSADMIN cannot CREATE USER. ACCOUNTADMIN can, but this follows the
-- documented Fivetran path so the same script works on locked-down accounts.
-- ---------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

-- Privileges live on the role, not the user. Swap or disable the user later
-- without rewriting grants.
CREATE ROLE IF NOT EXISTS IDENTIFIER($ROLE_NAME);

-- Let SYSADMIN inherit FIVETRAN_ROLE so you can inspect Fivetran objects
-- from a normal admin session (SHOW, SELECT) without becoming FIVETRAN_USER.
GRANT ROLE IDENTIFIER($ROLE_NAME) TO ROLE SYSADMIN;

-- TYPE = SERVICE: no password, no interactive login, no MFA prompt.
-- Snowflake is retiring password auth for this kind of user. Fivetran will
-- authenticate with the RSA key you attach in fivetran_keypair.sql.
-- DEFAULT_ROLE / DEFAULT_WAREHOUSE are what Fivetran uses if the destination
-- form omits them. Still set both fields in Fivetran explicitly.
CREATE USER IF NOT EXISTS IDENTIFIER($USER_NAME)
    TYPE = SERVICE
    DEFAULT_ROLE = $ROLE_NAME
    DEFAULT_WAREHOUSE = $WAREHOUSE_NAME
    COMMENT = 'Fivetran destination service user for the demo';

-- A user with no granted role cannot run anything, even with a valid key.
GRANT ROLE IDENTIFIER($ROLE_NAME) TO USER IDENTIFIER($USER_NAME);

-- Fivetran load defaults. Wrong formats cause sync failures that look like
-- "bad data" rather than "missing privilege".
-- BASE64: Fivetran stages some binary payloads as Base64.
-- AUTO: accept timestamp strings from Postgres without a fixed mask.
ALTER USER IDENTIFIER($USER_NAME) SET BINARY_INPUT_FORMAT = 'BASE64';
ALTER USER IDENTIFIER($USER_NAME) SET TIMESTAMP_INPUT_FORMAT = 'AUTO';

-- ---------------------------------------------------------------------------
-- Warehouse and database (SYSADMIN)
-- Compute (warehouse) is billed separately from storage (database).
-- Do not point Fivetran at the trial default COMPUTE_WH: that warehouse is
-- larger, shared with your worksheets, and easier to leave running.
-- ---------------------------------------------------------------------------
USE ROLE SYSADMIN;

-- Exclusive warehouse so Fivetran loads never queue behind your ad-hoc SQL.
-- XSMALL is enough for this OMS sample.
-- AUTO_SUSPEND = 60: stop billing one minute after the last query.
-- AUTO_RESUME = TRUE: Fivetran can wake it without a manual start.
-- INITIALLY_SUSPENDED: do not start compute just because we created it.
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($WAREHOUSE_NAME)
    WAREHOUSE_SIZE = XSMALL
    WAREHOUSE_TYPE = STANDARD
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Exclusive warehouse for Fivetran loads';

-- Destination only. Neon stays the source. Fivetran creates its own schema
-- (often named after the connector) inside this database on first sync.
-- You do not pre-create l1_landing here.
CREATE DATABASE IF NOT EXISTS IDENTIFIER($DATABASE_NAME)
    COMMENT = 'Fivetran destination. Raw replica of Neon fivetran_source.l1_landing';

-- USAGE: start the warehouse and run statements on it.
-- Without this grant, connection tests fail even if the user exists.
GRANT USAGE
    ON WAREHOUSE IDENTIFIER($WAREHOUSE_NAME)
    TO ROLE IDENTIFIER($ROLE_NAME);

-- USAGE: see the database.
-- MONITOR: Fivetran validates the destination (row counts, load status).
-- CREATE SCHEMA: Fivetran creates the landing schema and tables itself.
-- We do not grant CREATE DATABASE or account-level admin rights.
GRANT CREATE SCHEMA, MONITOR, USAGE
    ON DATABASE IDENTIFIER($DATABASE_NAME)
    TO ROLE IDENTIFIER($ROLE_NAME);

-- ---------------------------------------------------------------------------
-- Optional account privilege (ACCOUNTADMIN)
-- Snowflake on GCP uses a storage integration to stage files.
-- CREATE INTEGRATION is an account privilege, so only ACCOUNTADMIN can grant it.
-- On AWS/Azure this grant is unused for a basic SaaS destination, but the
-- official Fivetran script includes it so the same setup works on all clouds.
-- ---------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE IDENTIFIER($ROLE_NAME);

-- Return to SYSADMIN so the session is not left as ACCOUNTADMIN.
USE ROLE SYSADMIN;

COMMIT;
