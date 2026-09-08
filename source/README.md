# Neon source setup

This folder is the **operational source** for the demo: a Postgres database hosted on [Neon](https://neon.tech) that Fivetran will replicate into Snowflake.

Sample data comes from the [SleekMart OMS](https://github.com/sleekdata/oms-db-setup) educational dataset (SleekData). Use it for personal and educational purposes only.

## What is Neon?

[Neon](https://neon.com/docs/get-started/why-neon) is a serverless Postgres platform. It is standard PostgreSQL (drivers, SQL, extensions, and tools you already know), hosted as a managed service.

Neon separates **storage** from **compute**. That architecture is what makes instant branching, autoscaling, and scale-to-zero possible without you managing a Postgres instance.

Neon is now part of Databricks. For this demo we only use it as a hosted Postgres source.

## Why Neon is the Fivetran source

Fivetran needs a real, always-reachable database to extract from. Neon gives us that without running Postgres locally:

- It speaks **standard Postgres**, which Fivetran already supports as a source connector.
- The Free plan is enough for this OMS sample (a few thousand rows).
- The SQL Editor in the Neon Console is enough to create the schema, load data, and confirm rows before you wire Fivetran.
- A connection string from **Connect** is what you later paste into Fivetran.

In this project the Neon database is named `fivetran_source`. All demo tables live in the `l1_landing` schema.

## Key features we rely on

| Feature | Why it matters here |
|---|---|
| Serverless Postgres | No instance to provision. Create a project and start querying. |
| SQL Editor | Run `schema.sql` and `insert.sql` in the browser. |
| Scale to zero | Idle compute suspends after a few minutes, so a demo project stays cheap. |
| Autoscaling | Compute grows with load if you later add more data. |
| Branching | Copy-on-write clones of the database for experiments, without touching the branch Fivetran reads. |
| Connection strings | Host, user, password, and database name for the Fivetran Postgres connector. |
| Free plan | Enough storage and compute hours for this dataset. |

## Create a Neon account

1. Open [https://console.neon.tech/signup](https://console.neon.tech/signup).
2. Sign up with GitHub, Google, email, or another supported identity provider.
3. Verify your email if prompted.
4. You land in the [Neon Console](https://console.neon.tech). The Free plan is enough for this demo.

Official overview: [Why Neon](https://neon.com/docs/get-started/why-neon) and [Tour the Neon Console](https://neon.com/docs/get-started/signing-up).

## Create a project and the `fivetran_source` database

A Neon **project** holds branches, databases, and roles. A **branch** (this demo uses `production`) holds the actual Postgres databases.

1. In the Console, create a project (for example `fivetran demo`).
2. Pick a region close to you. A project starts with a default branch (`production` in the Console) and a default database named `neondb`.
3. Create the database this demo uses:
   - Open your project.
   - Confirm the `production` branch is selected.
   - Under **Postgres Database**, open **Databases**.
   - Click **Add database**.
   - Name it `fivetran_source` and keep the default owner.
   - Click **Create**.

You cannot create this database from `database.sql` inside the `fivetran_source` session itself. Create it in the Console (or while connected to `neondb`), then switch the SQL Editor to `fivetran_source`.

```sql
-- Only if you prefer SQL while connected to neondb:
CREATE DATABASE fivetran_source;
```

## Load the OMS schema and data

SQL files in this folder:

| File | Purpose |
|---|---|
| `database.sql` | Notes on creating `fivetran_source` (Neon already hosts the project). |
| `schema.sql` | Creates `l1_landing` and the eight OMS tables. |
| `insert.sql` | Loads sample customers, dates, employees, products, suppliers, stores, order items, and orders. |
| `replication.sql` | Publication and logical replication slot so Fivetran can sync incrementally. |

Identifiers are unquoted and lowercase so they match Postgres folding (`l1_landing.customers`, not `"L1_LANDING"."CUSTOMERS"`).

### 1. Create tables

In the Neon Console:

1. Open **Postgres Database > SQL Editor**.
2. Set the database dropdown to **`fivetran_source`**.
3. Paste the contents of `schema.sql`.
4. Click **Run**.

You should see **Statement executed successfully** for each `CREATE` statement.

![Schema created successfully in the Neon SQL Editor on fivetran_source](../assets/source/schema_create_success.png)

### 2. Insert sample rows

Still on `fivetran_source` in the SQL Editor:

1. Paste the contents of `insert.sql`.
2. Click **Run**.

The script is large (about 180k characters). The editor may warn that history will be truncated. The inserts still run.

You should see one successful `INSERT` per table. Typical row counts:

| Table | Rows |
|---|---|
| `l1_landing.customers` | 100 |
| `l1_landing.dates` | 365 |
| `l1_landing.employees` | 101 |
| `l1_landing.products` | 200 |
| `l1_landing.suppliers` | 20 |
| `l1_landing.stores` | 10 |
| `l1_landing.orderitems` | 1,651 |
| `l1_landing.orders` | 300 |

![Inserts completed successfully in the Neon SQL Editor](../assets/source/insert_success.png)

### 3. Query to confirm

Run:

```sql
SELECT * FROM l1_landing.customers;
```

You should get **100 rows**. That is the checkpoint that the source is ready for Fivetran.

![SELECT * FROM l1_landing.customers returns 100 rows](../assets/source/query_success.png)

A few more useful checks:

```sql
SELECT COUNT(*) FROM l1_landing.orders;
SELECT COUNT(*) FROM l1_landing.orderitems;

SELECT o.orderid, o.orderdate, c.firstname, c.lastname, o.status
FROM l1_landing.orders o
JOIN l1_landing.customers c ON c.customerid = o.customerid
ORDER BY o.orderdate DESC
LIMIT 10;
```

You can also browse tables under **Postgres Database > Tables**.

## Enable logical replication for Fivetran

Query-based sync (Fivetran `SELECT`s the tables on a schedule) works without extra Postgres objects. Incremental sync uses **logical replication**: Postgres writes row changes to the write-ahead log (WAL), and Fivetran reads only those changes.

That needs three things:

| Piece | What it is | In this demo |
|---|---|---|
| `wal_level = logical` | Postgres records enough WAL detail to decode row changes. | Neon project setting (not SQL). |
| Publication | Allow-list of tables in the change stream. | `publication_01` |
| Replication slot | Bookmark of how far Fivetran has read the WAL. WAL is kept until that offset advances. | `replication_slot_01` with plugin `pgoutput` |

`pgoutput` is the built-in decoder Fivetran uses. The publication and slot names you create must match the Fivetran Postgres connector form exactly.

Enabling logical replication in Neon changes `wal_level` from `replica` to `logical` for the whole project. **That change cannot be reverted** and restarts computes (brief disconnect). A connected subscriber also keeps compute from scaling to zero, which can use more Neon credits. See [Replicate data with Fivetran](https://neon.com/docs/guides/logical-replication-fivetran) and [Fivetran’s Postgres setup](https://fivetran.com/docs/connectors/databases/postgresql/setup-guide).

### 1. Turn on logical replication in Neon

1. Open the project in the Neon Console.
2. Go to **Settings > Logical Replication**.
3. Click **Enable**. You should see **Logical replication is enabled for this project.**

![Logical replication enabled on the Neon project](../assets/source/logical_replication.png)

4. In the SQL Editor on `fivetran_source`, confirm:

```sql
SHOW wal_level;
```

Expect `logical`.

### 2. Run `replication.sql`

Still on `fivetran_source`, paste and run [`sql/replication.sql`](sql/replication.sql). It:

1. Sets `REPLICA IDENTITY FULL` on the OMS tables. They have no primary key, so UPDATE/DELETE need the full old row in the WAL for Fivetran to match them.
2. Drops and recreates publication `publication_01` for **all tables** (simple for this demo).
3. Drops the slot only if it already exists, then creates `replication_slot_01` with `pgoutput`.
4. Prints `wal_level`, the publication, and the slot.

Create the publication **before** the slot. That is Fivetran’s required order.

A leftover unused slot holds WAL forever and can grow storage. Recreate the slot only when you are resetting the connector. One Fivetran connector per slot.

![replication.sql: replica identity, publication_01, statements succeeded](../assets/source/source_and_publication.png)

### 3. Values to enter in Fivetran

Copy these from Neon **Connect** (next section) into the Fivetran PostgreSQL wizard. Full click-path: [fivetran/README.md](../fivetran/README.md#1-postgres-source-neon--fivetran).

| Fivetran field | Value |
|---|---|
| Connection method | Connect directly |
| Host | Direct Neon host (**no** `-pooler` in the hostname) |
| Port | `5432` |
| Database | `fivetran_source` (the form starts empty; do not leave it blank) |
| User | `neondb_owner` (or the role that owns the tables) |
| Password | From Neon Connect / Show password |
| SSL | Required |
| Update method | Logical replication of the WAL using the `pgoutput` plugin |
| Replication slot | `replication_slot_01` |
| Publication name | `publication_01` |

Logical replication is not compatible with Neon’s pooled connection string. Copy **Connect** details and drop `-pooler` from the host if it is there.

If the project uses Neon’s IP Allow list, add [Fivetran’s IPs](https://fivetran.com/docs/connectors/databases/postgresql/setup-guide) before **Save & Test**.

## Screenshots in `assets/source`

These screenshots are the expected Console state after each step:

| Asset | What it shows |
|---|---|
| [`schema_create_success.png`](../assets/source/schema_create_success.png) | SQL Editor on branch `production`, database `fivetran_source`, after `schema.sql` succeeds. |
| [`insert_success.png`](../assets/source/insert_success.png) | Same editor after `insert.sql` loads all eight tables. |
| [`query_success.png`](../assets/source/query_success.png) | `SELECT * FROM l1_landing.customers` returning 100 rows. |
| [`logical_replication.png`](../assets/source/logical_replication.png) | Settings: logical replication enabled. |
| [`source_and_publication.png`](../assets/source/source_and_publication.png) | SQL Editor after `replication.sql`. |
| [`connection.png`](../assets/source/connection.png) | Connect modal: `fivetran_source`, `neondb_owner`, pooling off. Split this URI into Fivetran Host / User / Password / Database. |

If your editor does not look like these, check the database dropdown. Running SQL against `neondb` instead of `fivetran_source` is the usual miss.

## Connection string for Fivetran

When you are ready to connect Fivetran, open **Connect** and map the URI into the Postgres connector form. Do not paste the whole URI into a single Fivetran field.

1. In the project sidebar, click **Connect**.
2. Branch `production`, compute **Primary**, database **`fivetran_source`**, role **`neondb_owner`**.
3. Turn **Connection pooling** **off**. The hostname must not contain `-pooler`.
4. Split the URI. A typical string looks like:

```text
postgresql://neondb_owner:PASSWORD@ep-….us-east-2.aws.neon.tech/fivetran_source?sslmode=require
```

| Piece of the URI | Fivetran field |
|---|---|
| `neondb_owner` | User |
| `PASSWORD` (Show password) | Password |
| host after `@`, before `/` | Host (no `-pooler`) |
| `fivetran_source` (path, not `neondb`) | Database |
| `sslmode=require` | SSL required, port `5432` |

This demo’s Neon project is AWS `us-east-2`. Pick a Fivetran processing region close to that.

![Neon Connect: fivetran_source, pooling off](../assets/source/connection.png)

Do not commit connection strings or passwords to this repo. How those values are typed into Fivetran, including Save & Test and the first sync: [fivetran/README.md](../fivetran/README.md).

## Next step

With `l1_landing` queryable and the publication/slot created, create the Snowflake objects in [snowflake/README.md](../snowflake/README.md) if you have not already, then connect **Neon source → Snowflake destination** in [fivetran/README.md](../fivetran/README.md).
