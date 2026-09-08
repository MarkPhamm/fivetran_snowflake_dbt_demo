-- =============================================================================
-- Confirm Fivetran destination objects
-- =============================================================================
-- Run after fivetran_setup.sql (and keypair.sql if you already attached a key).
-- Use any role that can see these objects (ACCOUNTADMIN or SYSADMIN).
-- In Snowsight, run statement by statement or select all.
--
-- SHOW ... LIKE filters to our demo names so trial defaults (COMPUTE_WH,
-- SNOWFLAKE_SAMPLE_DATA) do not clutter the result.
-- =============================================================================

-- These four should each return one row after a successful setup.
SHOW ROLES LIKE 'FIVETRAN_ROLE';
SHOW USERS LIKE 'FIVETRAN_USER';
SHOW WAREHOUSES LIKE 'FIVETRAN_WAREHOUSE';
SHOW DATABASES LIKE 'FIVETRAN_DEMO';

-- Role grants: expect USAGE on FIVETRAN_WAREHOUSE and
-- CREATE SCHEMA, MONITOR, USAGE on FIVETRAN_DEMO.
-- User grants: expect FIVETRAN_ROLE assigned to FIVETRAN_USER.
SHOW GRANTS TO ROLE FIVETRAN_ROLE;
SHOW GRANTS TO USER FIVETRAN_USER;

-- Values for the Fivetran Snowflake destination form.
-- Host is usually:
--   <organization_name>-<account_name>.snowflakecomputing.com
-- account_locator is the older <locator>.<region>.snowflakecomputing.com form.
-- You can also copy the host from Snowsight: account menu -> View account details.
SELECT
    CURRENT_ORGANIZATION_NAME() AS organization_name,
    CURRENT_ACCOUNT_NAME() AS account_name,
    CURRENT_ACCOUNT() AS account_locator,
    CURRENT_REGION() AS region;
