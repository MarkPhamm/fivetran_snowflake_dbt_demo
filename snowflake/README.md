# Snowflake destination setup

This folder creates the Snowflake objects Fivetran needs to write the Neon replica.

Official reference: [Fivetran Snowflake destination setup](https://fivetran.com/docs/destinations/snowflake/setup-guide).

Neon (`fivetran_source.l1_landing`) is the **source**. Snowflake database `FIVETRAN_DEMO` is the **destination**. Fivetran creates schemas and tables inside `FIVETRAN_DEMO` during the first sync.

## What gets created

| Object | Name | Purpose |
|---|---|---|
| Role | `FIVETRAN_ROLE` | Least-privilege role Fivetran assumes |
| User | `FIVETRAN_USER` | Service user (key-pair auth, not a password) |
| Warehouse | `FIVETRAN_WAREHOUSE` | Exclusive XSMALL compute, auto-suspend 60s |
| Database | `FIVETRAN_DEMO` | Destination database Fivetran writes into |

Grants on `FIVETRAN_DEMO`: `CREATE SCHEMA`, `MONITOR`, `USAGE`. Fivetran creates its own schema when the Postgres connector syncs (you do not pre-create `l1_landing` here).

The role is also granted to `SYSADMIN` so you can inspect Fivetran objects from a normal admin session.

## Prerequisites

- A Snowflake trial account (steps below).
- A user who can assume `SECURITYADMIN` and `SYSADMIN`. The default trial `ACCOUNTADMIN` can.
- `openssl` on your machine, to generate the key pair.

## Create a free trial account

Snowflake’s trial is a 30-day [AI Data Cloud trial](https://www.snowflake.com/en/snowflake-trial/) with about **$400 in free credits**. That is more than enough for this demo. A credit card is not required to start. Official notes: [Trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account).

Choose the **AI Data Cloud** trial, not the Cortex Code CLI trial. You need a full warehouse so Fivetran can write tables.

1. Open [https://signup.snowflake.com](https://signup.snowflake.com) (or **Start for Free** on [snowflake.com](https://www.snowflake.com)).
2. Leave **AI Data Cloud For Enterprise** selected (not Snowflake CoCo For Developers). The form is step 1 of 2.
3. Enter first name, last name, work email, and why you are signing up. A personal name is fine if you do not have a company.

![Snowflake trial signup: AI Data Cloud with $400 in free credits](../assets/snowflake/free_trial.png)

4. Open the activation email and click the verification link. Check spam if it does not arrive; you can request another email from the signup page.
5. Choose a **cloud** (AWS, Azure, or GCP), a **region**, and an **edition**.
   - Cloud and region **cannot be changed** later. Pick a region close to you (and to Neon if you can).
   - **Enterprise** is the usual trial edition and is fine for this demo.
6. Set the username and password you will use to log in to Snowsight. This is *your* admin user, not `FIVETRAN_USER`.
7. Wait for the account to provision (usually under a minute). Snowflake emails the account URL and identifier.
8. Sign in at [https://app.snowflake.com](https://app.snowflake.com) with that username.

You land in **Snowsight**. The trial user is `ACCOUNTADMIN` and can assume `SECURITYADMIN` and `SYSADMIN`. Snowflake also creates a default warehouse (`COMPUTE_WH`) and sample data. Do **not** point Fivetran at `COMPUTE_WH`. The setup script creates `FIVETRAN_WAREHOUSE` so Fivetran has its own XSMALL warehouse that auto-suspends.

Credits expire after 30 days. If you do not add billing, the account is suspended and you can lose access to the data. This demo uses almost no credits if the Fivetran warehouse stays at XSMALL with `AUTO_SUSPEND = 60`.

If the activation email never arrives, see [Snowflake’s trial FAQ](https://www.snowflake.com/en/snowflake-trial/).

## 1. Run the setup script

1. Open [Snowsight](https://app.snowflake.com) and create a worksheet.
2. Paste [`sql/fivetran_setup.sql`](sql/fivetran_setup.sql).
3. Select the entire script (Snowsight only runs highlighted statements).
4. Click **Run**.

The script is wrapped in `BEGIN` / `COMMIT` and switches roles as it goes. After it finishes, Snowsight should show **Statement executed successfully**, with the worksheet context on `SYSADMIN`, `FIVETRAN_WAREHOUSE`, and `FIVETRAN_DEMO`.

![fivetran_setup.sql ran successfully in Snowsight](../assets/snowflake/setup_user_fivetran.png)

## 2. Attach a key pair

`FIVETRAN_USER` is a `TYPE = SERVICE` user. It has no password. Snowflake is also discontinuing username/password auth for destinations.

On your machine (do not commit these files):

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/fivetran_rsa_key.p8 -nocrypt
openssl rsa -in ~/.snowflake/fivetran_rsa_key.p8 -pubout -out ~/.snowflake/fivetran_rsa_key.pub
chmod 600 ~/.snowflake/fivetran_rsa_key.p8
```

This is a **different** pair from `dbt_rsa_key.*`. Do not reuse the dbt files for Fivetran.

Copy the **public key body** (no `BEGIN` / `END` lines, one line) to the clipboard, then paste it into [`sql/fivetran_keypair.sql`](sql/fivetran_keypair.sql) as `SECURITYADMIN`:

```bash
grep -v -- '-----' ~/.snowflake/fivetran_rsa_key.pub | tr -d '\n' | pbcopy
```

The Fivetran destination form wants the **full private key**, including `BEGIN` / `END`. Copy that separately:

```bash
pbcopy < ~/.snowflake/fivetran_rsa_key.p8
```

That clipboard value should look like:

```
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

Snowsight should report **Statement executed successfully** for `ALTER USER FIVETRAN_USER SET RSA_PUBLIC_KEY`.

![Public key attached to FIVETRAN_USER](../assets/snowflake/adding_key_fivetran.png)

## 3. Verify

Run [`sql/verify.sql`](sql/verify.sql). You should see the role, user, warehouse, and database, plus grants:

- `USAGE` on `FIVETRAN_WAREHOUSE`
- `CREATE SCHEMA`, `MONITOR`, `USAGE` on `FIVETRAN_DEMO`

The last `SELECT` prints account identifiers. Fivetran **Host** is usually:

```
<organization_name>-<account_name>.snowflakecomputing.com
```

You can also copy the host from Snowsight: account menu → **Account** → **View account details**.

## 4. Values to enter in Fivetran

In Fivetran, add the Postgres source first, then a **Snowflake destination** (Destinations, not a source connector). Screenshots of the form and a passing test are in [fivetran/README.md](../fivetran/README.md#3-snowflake-destination-fivetran--snowflake).

| Fivetran field | Value |
|---|---|
| Host | `<org>-<account>.snowflakecomputing.com` (hyphen, not a dot) |
| Port | `443` |
| User | `FIVETRAN_USER` |
| Database | `FIVETRAN_DEMO` |
| Auth | Key pair |
| Private key | Full PEM from `~/.snowflake/fivetran_rsa_key.p8` (`BEGIN` / `END` included) |
| Is private key encrypted? | Off (the `openssl` command used `-nocrypt`) |
| Role | `FIVETRAN_ROLE` (optional in the UI; set it) |
| Warehouse | `FIVETRAN_WAREHOUSE` |

Save & Test should pass host, warehouse, database, internal stage, and permissions. **Validate Passphrase** stays a dash because the key is unencrypted.

Do not reuse `FIVETRAN_USER` for dbt. After the first Fivetran sync, run [`sql/dbt_setup.sql`](sql/dbt_setup.sql), then create a **separate** key pair for `DBT_USER` (next section).

## 5. Key pair for dbt (`DBT_USER`)

Snowflake does not create or download `private_key_path`. You generate the key on your laptop, attach the **public** half to `DBT_USER`, and give dbt the **private** `.p8` file. [Snowflake key-pair auth](https://docs.snowflake.com/en/user-guide/key-pair-auth).

Do not reuse Fivetran’s `fivetran_rsa_key.p8`. `DBT_USER` should have its own pair.

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/dbt_rsa_key.p8 -nocrypt
openssl rsa -in ~/.snowflake/dbt_rsa_key.p8 -pubout -out ~/.snowflake/dbt_rsa_key.pub
chmod 600 ~/.snowflake/dbt_rsa_key.p8
```

Copy the **public key body** to the clipboard (no `BEGIN` / `END` lines, one line), then paste it into [`sql/dbt_keypair.sql`](sql/dbt_keypair.sql) and run as `SECURITYADMIN`:

```bash
grep -v -- '-----' ~/.snowflake/dbt_rsa_key.pub | tr -d '\n' | pbcopy
```

![Public key attached to DBT_USER](../assets/snowflake/adding_key_dbt.png)

dbt uses the private `.p8` by **path**. Do not paste the key into `profiles.yml`. Set `private_key_path` to the absolute file location (below).

In `~/.dbt/profiles.yml` set the **absolute** path to the private key, for example:

```yaml
authenticator: snowflake_jwt
private_key_path: /Users/YOUR_USER/.snowflake/dbt_rsa_key.p8
```

Then from the repo root run `dbt debug`. Do not commit `.p8` or `.pub` files.

If the account has a network policy, allow [Fivetran IPs](https://fivetran.com/docs/destinations/snowflake/setup-guide#optionalconfiguresnowflakenetworkpolicy). Trial accounts usually have none.

## SQL files

| File | Purpose |
|---|---|
| [`sql/fivetran_setup.sql`](sql/fivetran_setup.sql) | Role, service user, warehouse, database, grants |
| [`sql/fivetran_keypair.sql`](sql/fivetran_keypair.sql) | `ALTER USER FIVETRAN_USER ... RSA_PUBLIC_KEY` |
| [`sql/verify.sql`](sql/verify.sql) | Confirm objects and print account identifiers |
| [`sql/dbt_setup.sql`](sql/dbt_setup.sql) | `DBT_ROLE` / `DBT_USER` plus `TRANSFORM` and `SERVE` schemas |
| [`sql/dbt_keypair.sql`](sql/dbt_keypair.sql) | `ALTER USER DBT_USER ... RSA_PUBLIC_KEY` |

## Screenshots in `assets/snowflake`

| Asset | What it shows |
|---|---|
| [`free_trial.png`](../assets/snowflake/free_trial.png) | Signup form at [signup.snowflake.com](https://signup.snowflake.com): **AI Data Cloud For Enterprise**, 30-day trial, $400 credits. |
| [`setup_user_fivetran.png`](../assets/snowflake/setup_user_fivetran.png) | Snowsight `fivetran_setup.sql` after a successful run. |
| [`adding_key_fivetran.png`](../assets/snowflake/adding_key_fivetran.png) | `ALTER USER FIVETRAN_USER SET RSA_PUBLIC_KEY` succeeded. |
| [`adding_key_dbt.png`](../assets/snowflake/adding_key_dbt.png) | `ALTER USER DBT_USER SET RSA_PUBLIC_KEY` succeeded. |

Fivetran destination form and passing tests: [`snowflake_destination_auth.png`](../assets/fivetran/snowflake_destination_auth.png) and [`snowflake_destination_success.png`](../assets/fivetran/snowflake_destination_success.png).

## Next step

Add the Postgres connector, then the Snowflake destination, in [fivetran/README.md](../fivetran/README.md).
