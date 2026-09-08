-- =============================================================================
-- Attach an RSA public key to FIVETRAN_USER
-- =============================================================================
-- SERVICE users cannot use a password. Snowflake is also discontinuing
-- username/password auth for destination connections. Fivetran signs in with
-- the private key; Snowflake verifies it against this public key.
--
-- Generate a pair that is NOT the dbt key. Do not commit these files.
--
--   mkdir -p ~/.snowflake
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/fivetran_rsa_key.p8 -nocrypt
--   openssl rsa -in ~/.snowflake/fivetran_rsa_key.p8 -pubout -out ~/.snowflake/fivetran_rsa_key.pub
--   chmod 600 ~/.snowflake/fivetran_rsa_key.p8
--
-- Copy the public body for Snowflake (macOS):
--   grep -v -- '-----' ~/.snowflake/fivetran_rsa_key.pub | tr -d '\n' | pbcopy
-- Paste that one line into RSA_PUBLIC_KEY below. Omit BEGIN/END PUBLIC KEY.
--
-- Copy the full private key for the Fivetran UI (includes BEGIN/END):
--   pbcopy < ~/.snowflake/fivetran_rsa_key.p8
--
-- Run as SECURITYADMIN (it owns user properties). Select this whole script.
-- =============================================================================

USE ROLE SECURITYADMIN;

-- Re-run this statement to rotate the key. Snowflake also supports
-- RSA_PUBLIC_KEY_2 so you can add a new key before removing the old one.
ALTER USER FIVETRAN_USER SET RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_HERE>';
