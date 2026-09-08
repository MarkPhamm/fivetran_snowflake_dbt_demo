# Fivetran Snowflake dbt Demo

This is a small end-to-end ELT tutorial. You will copy retail sample data from a hosted Postgres database into Snowflake, then clean it with dbt.

**ELT** means Extract, Load, Transform: copy the data first, then reshape it in the warehouse. You do not need to know SQL well to follow the setup. You do need to be comfortable opening a browser, pasting SQL into a console, and running a few commands in a terminal.

The work is two parts. Finish Part 1 before you start Part 2.

| Part | What you do | When you are done |
|---|---|---|
| **1. Ingestion** | Put sample orders into Neon, create a Snowflake trial, and let Fivetran copy the tables | Snowflake has 100 customers in `FIVETRAN_DEMO.L1_LANDING` |
| **2. dbt** | Install dbt on your laptop and build cleaned reporting tables in Snowflake | `dbt run` and `dbt test` succeed |

```
Part 1 — ingestion                         Part 2 — transform
Neon (Postgres)  →  Fivetran  →  Snowflake landing  →  dbt  →  analytics tables
```

Neon is only the **source** (the operational database). Snowflake is the **warehouse** (where analytics happens). Fivetran is the managed copy. dbt never talks to Neon; it only reads the Snowflake replica.

Detailed click-paths and screenshots live in the linked guides. This file is the path through the tutorial.

## Accounts you need

All of this runs on free tiers. Create the accounts when the steps ask for them. You do not need dbt Cloud.

| Tool | Role in this tutorial | Sign up |
|---|---|---|
| [Neon](https://console.neon.tech/signup) | Free serverless Postgres. Holds the sample store data. | Free account |
| [Snowflake](https://signup.snowflake.com/) | Free 30-day trial warehouse. Destination for Fivetran and dbt. | Walkthrough in [snowflake/README.md](snowflake/README.md) |
| [Fivetran](https://fivetran.com/signup) | Free account. Copies Neon into Snowflake. | Free account |
| dbt Core | Free CLI. You install it in Part 2 into a project folder, not globally. | Python 3.10–3.13 (3.12 is the default in [`.python-version`](.python-version)) |

---

# Part 1 — Ingestion: copy Neon into Snowflake

Goal: an exact replica of eight Order Management System (OMS) tables sitting in Snowflake. No cleaning yet.

The sample is SleekMart OMS data (customers, orders, products, and so on). Fivetran will keep copying **changes** after the first load, using Postgres logical replication (a change log, not a full table scan every time).

## 1.1 Load the sample database in Neon

Neon is hosted Postgres. You create a project in the browser, then run SQL in Neon’s SQL Editor.

**Follow [source/README.md](source/README.md).** In short:

1. Sign up and create a project (this demo uses branch `production`).
2. Create a database named `fivetran_source` (do not use the default `neondb` for the rest of the steps).
3. In the SQL Editor, switch the dropdown to `fivetran_source`.
4. Run [`source/sql/schema.sql`](source/sql/schema.sql), then [`source/sql/insert.sql`](source/sql/insert.sql).
5. Run `SELECT * FROM l1_landing.customers;` and confirm **100 rows**.

`l1_landing` is the schema (a folder of tables) Fivetran will read:

| Table | What it is | Rows |
|---|---|---|
| `customers` | Customer profiles | 100 |
| `dates` | Calendar dimension | 365 |
| `employees` | Store staff and managers | 101 |
| `products` | Catalog and supplier cost | 200 |
| `suppliers` | Vendor contacts | 20 |
| `stores` | Store locations | 10 |
| `orders` | Order headers | 300 |
| `orderitems` | Line items | 1,651 |

If the query returns nothing, the usual miss is running SQL against `neondb` instead of `fivetran_source`.

## 1.2 Turn on logical replication

Fivetran can re-read whole tables on a schedule. This demo uses **logical replication**: Postgres writes row changes to its write-ahead log (WAL), and Fivetran reads only those changes.

That needs three things, all described in [source/README.md](source/README.md#enable-logical-replication-for-fivetran):

1. In Neon: **Settings → Logical Replication → Enable**. Confirm with `SHOW wal_level;` → `logical`. This cannot be turned off later and restarts compute briefly.
2. Still on `fivetran_source`, run [`source/sql/replication.sql`](source/sql/replication.sql). It creates publication `publication_01` (which tables to stream) and slot `replication_slot_01` (Fivetran’s bookmark in the WAL).
3. Keep those two names. You will type them into Fivetran later.

If you want the “why” behind WAL, publications, and slots, read [source/postgres_cdc.md](source/postgres_cdc.md) after this part. You do not need it to finish the setup.

## 1.3 Create a Snowflake trial and Fivetran objects

Snowflake is empty until you create a place for Fivetran to write. Do **not** point Fivetran at the trial default warehouse `COMPUTE_WH`.

**Follow [snowflake/README.md](snowflake/README.md).** In short:

1. Start an **AI Data Cloud** trial at [signup.snowflake.com](https://signup.snowflake.com) (not the Cortex Code CLI trial).
2. In Snowsight, run [`snowflake/sql/fivetran_setup.sql`](snowflake/sql/fivetran_setup.sql). That creates `FIVETRAN_ROLE`, `FIVETRAN_USER`, `FIVETRAN_WAREHOUSE`, and database `FIVETRAN_DEMO`.
3. On your laptop, generate a key pair (`fivetran_rsa_key.p8` / `.pub`). Snowflake does not download a private key for you. This pair is **only** for Fivetran.
4. Paste the **public** key body into [`snowflake/sql/fivetran_keypair.sql`](snowflake/sql/fivetran_keypair.sql) and run it.
5. Run [`snowflake/sql/verify.sql`](snowflake/sql/verify.sql) and copy the host: `<org>-<account>.snowflakecomputing.com` (hyphen, not a dot).

`FIVETRAN_USER` is a service user: no password, key-pair only. Keep `~/.snowflake/fivetran_rsa_key.p8` on this machine. You will paste that **private** key into Fivetran next.

## 1.4 Connect Fivetran (source, then destination)

**Follow [fivetran/README.md](fivetran/README.md).** Create the PostgreSQL source first, then the Snowflake destination. Attach the destination before the first sync.

**PostgreSQL source** (Neon → Fivetran):

- Connection method: **Connect directly**.
- Host from Neon **Connect**, pooling **off** (hostname must not contain `-pooler`). Port `5432`. SSL required.
- Database `fivetran_source` (the form starts **empty**; do not leave it blank). User `neondb_owner` and the Neon password.
- Incremental sync: logical replication / `pgoutput`, slot `replication_slot_01`, publication `publication_01`.
- Save & Test. Logical replication should pass. Neon Free often warns about `wal_sender_timeout` and `wal_buffers`. You cannot change those on Neon. **Continue** is fine.

Split the Neon URI into fields. Do not paste the whole `postgresql://…` string into one box. How to split it is in [source/README.md](source/README.md#connection-string-for-fivetran) and [fivetran/README.md](fivetran/README.md#1-postgres-source-neon--fivetran).

**Snowflake destination** (Fivetran → Snowflake):

- Host from `verify.sql`, port `443`, user `FIVETRAN_USER`, database `FIVETRAN_DEMO`, role `FIVETRAN_ROLE`, warehouse `FIVETRAN_WAREHOUSE`.
- Auth: key pair. Paste the full private key (`BEGIN` / `END` included). Leave “encrypted” off.
- Save & Test until host, warehouse, database, stage, and permissions pass.

## 1.5 First sync — Part 1 checkpoint

In Fivetran, the connection stays **Paused** until you pick tables.

1. **Review connection schema** and select `l1_landing` (the eight OMS tables).
2. Start the sync.
3. Expect about half a minute and **2,747 rows** extracted and loaded.

In Snowflake (Snowsight), run:

```sql
SELECT COUNT(*) FROM FIVETRAN_DEMO.L1_LANDING.CUSTOMERS;
```

You want **100**. If the schema has a prefix (for example `POSTGRES_DEMO_L1_LANDING`), note that name. You will tell dbt about it in Part 2.

Part 1 is done. The warehouse now has a landing replica. Next you transform it.

---

# Part 2 — dbt: turn the replica into reporting tables

Goal: dbt reads `FIVETRAN_DEMO.L1_LANDING` and writes cleaned tables into `TRANSFORM` and `SERVE`.

**dbt** (data build tool) is a command-line program. You write SQL files; dbt runs them in Snowflake in the right order, tests the results, and documents the models. It does not extract data. If Part 1 is incomplete, `dbt run` will fail because the landing tables are missing.

You do not need dbt Cloud. Install dbt Core into a virtual environment in **this repo** (`.venv/`). Do not `pip install dbt-snowflake` into your system Python.

Models come from [sleekdata/oms_fivetran_transforms](https://github.com/sleekdata/oms_fivetran_transforms). The dbt project lives at the **repo root** (`dbt_project.yml`, `models/`).

```
FIVETRAN_DEMO.L1_LANDING     Fivetran-synced OMS tables (Part 1)
        |
        v
FIVETRAN_DEMO.TRANSFORM      staging + orders_fact
        |
        v
FIVETRAN_DEMO.SERVE          customerrevenue, emp_weekly_sales
```

| Model | Schema | What it builds |
|---|---|---|
| `customers_stg` | TRANSFORM | Customers plus `CustomerName` |
| `orders_stg` | TRANSFORM | Orders with status labels and channel |
| `orderitems_stg` | TRANSFORM | Lines plus `TotalPrice` |
| `employees_stg` | TRANSFORM | Employees plus `EmployeeName` |
| `orders_fact` | TRANSFORM | Order grain with revenue |
| `customerrevenue` | SERVE | Revenue by customer (`tag:daily`) |
| `emp_weekly_sales` | SERVE | Revenue by employee and week (`tag:weekly`) |

`orders_stg` treats `StoreID = 1000` as Online. The Neon seed stores use other ids, so these seed rows classify as In-store.

## 2.1 Create a dbt user in Snowflake

Fivetran’s user must not run your transforms. A separate `DBT_USER` keeps keys and privileges apart.

1. Confirm landing exists: `SELECT COUNT(*) FROM FIVETRAN_DEMO.L1_LANDING.CUSTOMERS`.
2. In Snowsight, run [`snowflake/sql/dbt_setup.sql`](snowflake/sql/dbt_setup.sql). That creates `DBT_ROLE`, `DBT_USER`, and schemas `TRANSFORM` and `SERVE`.

Full notes: [snowflake/README.md](snowflake/README.md#5-key-pair-for-dbt-dbt_user).

## 2.2 Make a key pair for dbt

Generate this pair **on your laptop**. It must be a **different** pair from Fivetran’s `fivetran_rsa_key.*`.

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/dbt_rsa_key.p8 -nocrypt
openssl rsa -in ~/.snowflake/dbt_rsa_key.p8 -pubout -out ~/.snowflake/dbt_rsa_key.pub
chmod 600 ~/.snowflake/dbt_rsa_key.p8
```

Copy the **public** key body (no `BEGIN` / `END` lines, one line), paste it into [`snowflake/sql/dbt_keypair.sql`](snowflake/sql/dbt_keypair.sql), and run that script as `SECURITYADMIN`:

```bash
grep -v -- '-----' ~/.snowflake/dbt_rsa_key.pub | tr -d '\n' | pbcopy
```

dbt uses the private `.p8` **by file path**. You will not paste the private key into a website.

## 2.3 Install dbt in this repo

Supported Python: **3.10–3.13**. [`.python-version`](.python-version) is **3.12**. Dependencies are locked in [`uv.lock`](uv.lock) and [`requirements.txt`](requirements.txt). Create `.venv` here (it is gitignored). Activate it in every new terminal before you run `dbt`.

With [uv](https://docs.astral.sh/uv/) (preferred):

```bash
uv sync
source .venv/bin/activate
```

`uv sync` will install CPython 3.12 if it is missing.

Or with the stdlib venv:

```bash
python3.12 -m venv .venv   # or python3.10 / python3.11 / python3.13
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

On Windows use `.venv\Scripts\activate`. `which dbt` should end in `.venv/bin/dbt`.

## 2.4 Point dbt at Snowflake

Copy [`profiles.yml.example`](profiles.yml.example) to `~/.dbt/profiles.yml`. Set:

- `account` to your Snowflake `<ORG>-<ACCOUNT>` (same hyphenated host, without `.snowflakecomputing.com`)
- `private_key_path` to an **absolute** path, for example `/Users/YOUR_USER/.snowflake/dbt_rsa_key.p8`

The profile name must stay `oms_dbt_proj` (that is what [`dbt_project.yml`](dbt_project.yml) expects). Do not commit `profiles.yml`, `.p8`, or `.pub` files.

If Fivetran created a prefixed schema, change `vars.fivetran_schema` in `dbt_project.yml` or run with `--vars '{fivetran_schema: YOUR_SCHEMA}'`.

## 2.5 Run dbt — Part 2 checkpoint

From the **repository root**, with `.venv` activated:

```bash
dbt debug
dbt run
dbt test
```

`dbt debug` must connect as `DBT_USER`. `dbt run` builds the seven models. `dbt test` checks the YAML tests in [`models/schema.yml`](models/schema.yml).

In Snowflake you should now see tables in `FIVETRAN_DEMO.TRANSFORM` and `FIVETRAN_DEMO.SERVE`.

---

## Repository layout

```
.
├── README.md                 # This tutorial (Part 1 ingestion, Part 2 dbt)
├── source/                   # Part 1: Neon / Postgres source
├── snowflake/                # Part 1–2: Snowflake SQL and key-pair steps
├── fivetran/                 # Part 1: Fivetran destination + Postgres connector
├── dbt_project.yml           # Part 2: dbt project
├── models/                   # Part 2: SQL models
├── profiles.yml.example      # Part 2: copy to ~/.dbt/profiles.yml
├── pyproject.toml            # Part 2: Python 3.10–3.13 + dbt-snowflake
└── assets/                   # Screenshots used by the guides
```

## License and data

This repository is under the [Apache License 2.0](LICENSE).

The OMS sample SQL is from [sleekdata/oms-db-setup](https://github.com/sleekdata/oms-db-setup). dbt models are from [sleekdata/oms_fivetran_transforms](https://github.com/sleekdata/oms_fivetran_transforms). Both are SleekData material for personal and educational use only. Unauthorized commercial use of that data, including use in other YouTube videos, is prohibited.
