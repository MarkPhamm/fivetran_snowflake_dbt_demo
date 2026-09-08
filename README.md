# Fivetran Snowflake dbt Demo

A small end-to-end ELT demo:

**Neon Postgres (source)** → **Fivetran (extract/load)** → **Snowflake (warehouse)** → **dbt (transform)**

## Prerequisites

All of this demo runs on free tiers:

| Tool | What you need | Sign up |
|---|---|---|
| Neon | Free account (serverless Postgres source) | [console.neon.tech/signup](https://console.neon.tech/signup) |
| Snowflake | Free 30-day trial (warehouse destination) | [signup.snowflake.com](https://signup.snowflake.com/) — walkthrough in [snowflake/README.md](snowflake/README.md) |
| Fivetran | Free account (extract and load) | [fivetran.com/signup](https://fivetran.com/signup) |
| dbt Core | Free, open-source CLI (transforms in Snowflake) | [Install dbt Core](https://docs.getdbt.com/docs/core/installation-overview) |

You do not need dbt Cloud. Install dbt Core locally (`dbt-snowflake`) after the warehouse exists.

## Architecture

```
Neon (fivetran_source / l1_landing)
        |
        |  Fivetran Postgres connector
        v
Snowflake (raw / landing replica)
        |
        |  dbt models
        v
Analytics-ready tables
```

| Layer | Role in this demo |
|---|---|
| Neon | Serverless Postgres. Holds the operational OMS tables Fivetran reads. |
| Fivetran | Managed ELT. Replicates `l1_landing` from Neon into Snowflake on a schedule. |
| Snowflake | Cloud warehouse. Destination for the Fivetran sync and the dbt project. |
| dbt | Transforms the landed replica into cleaned, documented models. |

Neon is the **source**, not the warehouse. Snowflake is where analytics work happens after Fivetran copies the data.

## Repository layout

```
.
├── README.md                 # This file: whole-project overview
├── LICENSE
├── source/                   # Neon / Postgres source setup
│   ├── README.md             # Neon account, project, schema, load, query
│   └── sql/
├── snowflake/                # Snowflake destination for Fivetran
│   ├── README.md             # Trial signup + Fivetran objects
│   └── sql/
└── assets/
    ├── source/               # Neon Console screenshots
    └── snowflake/            # Trial signup + setup-script screenshots
```

## Source data (Neon)

The source database is `fivetran_source`. Schema `l1_landing` contains:

| Table | Description |
|---|---|
| `customers` | Customer profiles |
| `dates` | Calendar dimension |
| `employees` | Store staff and managers |
| `products` | Catalog and supplier cost |
| `suppliers` | Vendor contacts |
| `stores` | Store locations |
| `orders` | Order headers |
| `orderitems` | Line items |

Step-by-step: create a Neon account, create `fivetran_source`, run the SQL, and query until you see 100 customers.

**Read [source/README.md](source/README.md) first.** That guide includes what Neon is, how to sign up, and the screenshots in `assets/source`.

## Fivetran

After the Neon source is loaded and queryable:

1. Create a Fivetran account and destination pointing at Snowflake.
2. Add a **Postgres** source connector.
3. Use the Neon connection string (database `fivetran_source`, SSL required).
4. Select the `l1_landing` schema (or the eight tables above).
5. Run the initial sync and confirm the same row counts in Snowflake.

Connector details will live in a later `fivetran/` guide.

## Snowflake and dbt

Snowflake receives the Fivetran replica. dbt then builds staging and marts on top of those landed tables.

**Read [snowflake/README.md](snowflake/README.md)** for the free-trial signup and the SQL that creates `FIVETRAN_ROLE`, `FIVETRAN_USER`, `FIVETRAN_WAREHOUSE`, and `FIVETRAN_DEMO`.

dbt models will `ref` the Fivetran-synced relations in Snowflake, not Neon. The dbt project is not in the repo yet.

## Suggested order

1. [Set up Neon and load OMS data](source/README.md) until `SELECT * FROM l1_landing.customers` returns 100 rows.
2. [Create a Snowflake trial and Fivetran destination objects](snowflake/README.md).
3. Connect Fivetran from Neon to Snowflake.
4. Build dbt models on the Snowflake replica.

## License and data

This repository is under the [Apache License 2.0](LICENSE).

The OMS sample SQL is from [sleekdata/oms-db-setup](https://github.com/sleekdata/oms-db-setup) (SleekData). Personal and educational use only. Unauthorized commercial use of that data, including use in other YouTube videos, is prohibited.
