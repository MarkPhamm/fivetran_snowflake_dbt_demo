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

![fivetran_setup.sql ran successfully in Snowsight](../assets/snowflake/setup_success.png)

## 2. Attach a key pair

`FIVETRAN_USER` is a `TYPE = SERVICE` user. It has no password. Snowflake is also discontinuing username/password auth for destinations.

On your machine (do not commit these files):

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

Open `rsa_key.pub`, copy the key body only (no `BEGIN PUBLIC KEY` / `END PUBLIC KEY` lines, as a single line). Paste it into [`sql/keypair.sql`](sql/keypair.sql) and run that worksheet as `SECURITYADMIN`.

Keep `rsa_key.p8` for the Fivetran destination form. You will paste the private key there, including the `BEGIN` / `END` lines:

```
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

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

When you add a Snowflake destination in Fivetran:

| Fivetran field | Value |
|---|---|
| Host | `<org>-<account>.snowflakecomputing.com` |
| Port | `443` |
| User | `FIVETRAN_USER` |
| Auth | Key pair |
| Private key | Contents of `rsa_key.p8` |
| Role | `FIVETRAN_ROLE` |
| Database | `FIVETRAN_DEMO` |
| Warehouse | `FIVETRAN_WAREHOUSE` |

Do not reuse `FIVETRAN_USER` for dbt or interactive queries. Give dbt its own role later.

If the account has a network policy, allow [Fivetran IPs](https://fivetran.com/docs/destinations/snowflake/setup-guide#optionalconfiguresnowflakenetworkpolicy). Trial accounts usually have none.

## SQL files

| File | Purpose |
|---|---|
| [`sql/fivetran_setup.sql`](sql/fivetran_setup.sql) | Role, service user, warehouse, database, grants |
| [`sql/keypair.sql`](sql/keypair.sql) | `ALTER USER ... RSA_PUBLIC_KEY` |
| [`sql/verify.sql`](sql/verify.sql) | Confirm objects and print account identifiers |

## Screenshots in `assets/snowflake`

| Asset | What it shows |
|---|---|
| [`free_trial.png`](../assets/snowflake/free_trial.png) | Signup form at [signup.snowflake.com](https://signup.snowflake.com): **AI Data Cloud For Enterprise**, 30-day trial, $400 credits. |
| [`setup_success.png`](../assets/snowflake/setup_success.png) | Snowsight worksheet `fivetran_setup.sql` after a successful run (`SYSADMIN` / `FIVETRAN_WAREHOUSE` / `FIVETRAN_DEMO`). |

## Next step

Add the Snowflake destination in Fivetran, then a Postgres connector pointed at Neon `fivetran_source`. Details are in the [project README](../README.md).
