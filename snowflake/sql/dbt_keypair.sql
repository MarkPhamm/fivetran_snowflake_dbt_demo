-- =============================================================================
-- Attach an RSA public key to DBT_USER
-- =============================================================================
-- Snowflake does not generate or export a private key. Create the pair on
-- your machine, register the PUBLIC key here, and point dbt at the PRIVATE
-- .p8 file. Official docs:
--   https://docs.snowflake.com/en/user-guide/key-pair-auth
--
-- Use a different pair from FIVETRAN_USER so you can rotate them separately.
--
--   mkdir -p ~/.snowflake
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/dbt_rsa_key.p8 -nocrypt
--   openssl rsa -in ~/.snowflake/dbt_rsa_key.p8 -pubout -out ~/.snowflake/dbt_rsa_key.pub
--   chmod 600 ~/.snowflake/dbt_rsa_key.p8
--
-- Copy the public body for Snowflake (macOS):
--   grep -v -- '-----' ~/.snowflake/dbt_rsa_key.pub | tr -d '\n' | pbcopy
-- Paste that one line into RSA_PUBLIC_KEY below. Omit BEGIN/END PUBLIC KEY.
--
-- dbt does not paste the private key. Point private_key_path at:
--   /Users/YOUR_USER/.snowflake/dbt_rsa_key.p8
--
-- Run as SECURITYADMIN. Select this whole script.
-- =============================================================================

USE ROLE SECURITYADMIN;

ALTER USER DBT_USER SET RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_HERE>';
