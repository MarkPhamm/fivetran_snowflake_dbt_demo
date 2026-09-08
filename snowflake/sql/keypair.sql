-- =============================================================================
-- Attach an RSA public key to FIVETRAN_USER
-- =============================================================================
-- SERVICE users cannot use a password. Snowflake is also discontinuing
-- username/password auth for destination connections. Fivetran signs in with
-- the private key; Snowflake verifies it against this public key.
--
-- Generate the pair on your machine. Do not commit rsa_key.p8 or rsa_key.pub.
--
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
--   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
--
-- rsa_key.pub  -> paste the body into RSA_PUBLIC_KEY below (Snowflake).
-- rsa_key.p8   -> paste the full PEM (including BEGIN/END) into Fivetran.
--
-- For RSA_PUBLIC_KEY, use one line and omit:
--   -----BEGIN PUBLIC KEY-----
--   -----END PUBLIC KEY-----
--
-- Run as SECURITYADMIN (it owns user properties). Select this whole script.
-- =============================================================================

USE ROLE SECURITYADMIN;

-- Re-run this statement to rotate the key. Snowflake also supports
-- RSA_PUBLIC_KEY_2 so you can add a new key before removing the old one.
ALTER USER FIVETRAN_USER SET RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_HERE>';
