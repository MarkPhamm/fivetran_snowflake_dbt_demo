# CDC with WAL, publication, replication slot, pgoutput, and replica identity

I found these concepts new and interesting, so I research a bit more on them with these **TLDR**:
* **WAL (Write-Ahead Log)** = Postgres’ history of database changes.
* **CDC (Change Data Capture)** = reading only INSERT/UPDATE/DELETE changes instead of scanning full tables.
* **`wal_level = logical`** = makes WAL detailed enough for tools like Fivetran to decode row-level changes.
* **Publication** = defines **which tables** are included in replication.
* **Replication slot** = remembers **how far Fivetran has read** in the WAL.
* **`pgoutput`** = Postgres’ built-in logical decoding format used to send changes.
* **Replica Identity** = tells Postgres how to identify the old row during UPDATE/DELETE.
* **`REPLICA IDENTITY FULL`** = store the entire old row in WAL when there's no good primary key.
* **Initial sync vs incremental sync** = first copy existing data, then only stream future changes.
* **WAL retention risk** = an unused/stuck replication slot can cause old WAL to pile up and consume storage.

## 1. Start with a normal Postgres database

Imagine you have this table:

```sql
orders
+----------+--------+--------+
| order_id | status | amount |
+----------+--------+--------+
| 101      | NEW    | 50     |
| 102      | NEW    | 80     |
+----------+--------+--------+
```

Then someone runs:

```sql
UPDATE orders
SET status = 'PAID'
WHERE order_id = 101;
```

Postgres changes the table:

```text
101 | PAID | 50
```

But internally, Postgres also writes information about that change into something called the **WAL**.

### WAL = Write-Ahead Log

Think of WAL like an **activity log**:

```text
10:01 INSERT order 101
10:05 INSERT order 102
10:10 UPDATE order 101 NEW -> PAID
10:15 DELETE order 102
```

This isn't literally what the WAL looks like, but conceptually that's what you need.

Postgres needs WAL for its own reliability and recovery.

---

# 2. How can Fivetran know what changed?

Suppose you want:

```text
Postgres
   ↓
Fivetran
   ↓
Snowflake
```

Fivetran has two broad ways of answering:

> "What changed since my last sync?"

### Method A: Query-Based

Fivetran comes back periodically and queries Postgres.

Conceptually:

```text
Fivetran:
"Hey Postgres, show me which rows changed."
```

Current Fivetran Query-Based sync uses Postgres metadata such as `xmin`, and optionally `ctid` for detecting deletes. This may require significantly more table scanning than WAL-based replication. ([Fivetran][1])

### Method B: Logical replication

Instead of repeatedly examining your tables, Fivetran says:

> "Give me the stream of changes Postgres already recorded."

```text
                        WAL
                         │
INSERT customer 1        │
UPDATE order 23          │
DELETE order 45          │
                         ▼
Postgres ───────────→ Fivetran ─────────→ Snowflake
```

That's **CDC: Change Data Capture**.

Fivetran recommends logical replication when possible because it can capture changes directly from PostgreSQL's WAL with less source-side scanning. ([Fivetran][1])

---

# 3. So what is `wal_level = logical`?

By default, Postgres writes WAL primarily for things like recovery and physical replication.

But Fivetran doesn't want:

> "Page 387 of this database changed."

It needs something logically meaningful:

> "`orders` row X was updated."

So Postgres needs to record enough information for the WAL to be **logically decoded**.

That's what:

```sql
wal_level = logical
```

does.

### Mental model

```text
wal_level = replica

WAL:
"some low-level database blocks changed"
```

versus:

```text
wal_level = logical

WAL:
"enough information exists to reconstruct
INSERT / UPDATE / DELETE events"
```

It's still WAL. You're just telling Postgres:

> **Record enough information so external systems can decode database changes.**

That is why Neon requires you to enable logical replication at the project level rather than through your normal SQL script.

After enabling it:

```sql
SHOW wal_level;
```

should return:

```text
logical
```

Neon documents that enabling logical replication restarts active computes and is irreversible for the project. A logical-replication subscriber can also keep the compute active instead of allowing it to scale to zero. ([Neon][2])

---

# 4. Now we have WAL. But do we want every table?

Probably not necessarily.

Imagine your database has:

```text
customers
orders
products
employees
internal_logs
audit_logs
temporary_stuff
```

Maybe Fivetran should only receive:

```text
customers
orders
products
```

That's where a **Publication** comes in.

---

# 5. Publication = "Which tables am I publishing?"

Think of the WAL as a giant newspaper containing database activity.

The **publication** is your subscription category.

```text
                  PostgreSQL WAL
                       │
         ┌─────────────┼─────────────┐
         │             │             │
     customers       orders      internal_logs
         │             │
         └──── publication_01 ───────┘
                       │
                       ▼
                    Fivetran
```

For example:

```sql
CREATE PUBLICATION publication_01
FOR TABLE customers, orders;
```

means:

> Changes from these tables are eligible to be streamed through this publication.

Your demo instead uses:

```sql
CREATE PUBLICATION publication_01
FOR ALL TABLES;
```

Which effectively says:

> "Fivetran can receive changes from every table."

That's fine for a demo.

Fivetran describes a publication as the group of tables whose change events you want replicated. ([Fivetran][1])

---

# 6. Then what is the replication slot?

This is probably the most important concept.

Imagine WAL events are numbered:

```text
WAL

100  INSERT customer
101  UPDATE order
102  INSERT product
103  DELETE order
104  UPDATE customer
105  INSERT order
```

Fivetran reads:

```text
100
101
102
```

Then disconnects.

How does Postgres know where Fivetran stopped?

That's the **replication slot**.

```text
replication_slot_01

Last consumed:
             ↓
100  101  102  103  104  105
          ↑
       bookmark
```

Conceptually:

```text
replication_slot_01 = "Fivetran has safely processed up to here."
```

Next time Fivetran connects:

```text
Fivetran:
"I was at 102."

Postgres:
"Cool. Here's 103 onward."
```

That's why calling it a **bookmark** is a very good mental model.

---

# 7. Why is the replication slot so important?

Because Postgres normally cleans up old WAL.

Imagine:

```text
100
101
102
103
104
105
```

Eventually Postgres would like to delete:

```text
100
101
102
```

because they are old.

But suppose Fivetran has only consumed through `101`.

The replication slot tells Postgres:

> Don't remove the WAL I still need.

So:

```text
Fivetran position
       ↓
100 101 | 102 103 104 105
          ↑
          must retain
```

Once Fivetran catches up:

```text
100 101 102 103 104 105
                    ↑
               Fivetran here
```

Postgres can release older WAL according to its normal lifecycle.

### This creates an operational risk

Imagine you create:

```text
replication_slot_01
```

and then Fivetran disappears.

Postgres may still think:

> "Someone needs these WAL records."

So WAL retention can grow.

```text
day 1:  █
day 2:  ███
day 3:  ███████
day 4:  ████████████
```

That is why unused replication slots need attention.

Fivetran also requires a unique replication slot per logical-replication connection. ([Fivetran][3])

---

# 8. Publication vs replication slot

This distinction is worth memorizing:

| Object               | Question it answers                       |
| -------------------- | ----------------------------------------- |
| **Publication**      | **WHAT** changes should Fivetran receive? |
| **Replication slot** | **WHERE** has Fivetran read up to?        |

So:

```text
Publication
    ↓
WHAT tables?

customers
orders
products
```

while:

```text
Replication slot
    ↓
WHERE are we in the WAL?

LSN: XXXXXXXXX
```

That's basically the core architecture.

---

# 9. What's `pgoutput` then?

The WAL itself isn't a convenient stream of normal SQL rows.

Something has to decode it.

That's an **output plugin**.

For Fivetran you're using:

```text
pgoutput
```

which is PostgreSQL's standard built-in logical replication output plugin.

So:

```text
WAL
 │
 │ raw Postgres change information
 ▼
pgoutput
 │
 │ logical replication messages
 ▼
Fivetran
```

When you create:

```sql
SELECT pg_create_logical_replication_slot(
    'replication_slot_01',
    'pgoutput'
);
```

you're basically saying:

> Create a bookmark named `replication_slot_01`, and when someone consumes changes through it, encode those changes using `pgoutput`.

Fivetran specifically requires/supports `pgoutput` for this setup. ([Fivetran][1])

---

# 10. Now the tricky one: `REPLICA IDENTITY FULL`

Your demo tables don't have primary keys.

Consider:

```text
customers

firstname | lastname | city
----------|----------|--------
John      | Smith    | Boston
John      | Smith    | Boston
John      | Smith    | Dallas
```

Now somebody executes an update.

Postgres tells Fivetran:

> A customer changed to `John Smith, Chicago`.

Fivetran asks:

> Which old row am I supposed to update in Snowflake?

That's difficult because there's no:

```text
customer_id = 123
```

---

## If there WERE a primary key

This is easy:

```text
OLD:
customer_id = 123

NEW:
customer_id = 123
city = Chicago
```

Fivetran can say:

```sql
UPDATE destination
WHERE customer_id = 123;
```

Easy.

---

# 11. Without a PK, Postgres needs more information

That's why you're doing:

```sql
ALTER TABLE customers
REPLICA IDENTITY FULL;
```

This tells Postgres:

> For UPDATE and DELETE events, include the complete old row information in the WAL.

Example:

```text
Before:

John | Smith | Boston
```

Update happens:

```sql
UPDATE ...
SET city = 'Chicago';
```

Logical replication can now effectively expose:

```text
OLD:
John | Smith | Boston

NEW:
John | Smith | Chicago
```

Fivetran can use the old values to identify the previous version.

Fivetran specifically supports tracking updates/deletes for tables without primary keys when their replica identity is `FULL`; it generates `_fivetran_id` to identify rows in destination tables without source primary keys. ([Fivetran][1])

### Mental model

```text
PRIMARY KEY exists
      ↓
"Tell Fivetran the ID of the old row."

No PRIMARY KEY
+ REPLICA IDENTITY FULL
      ↓
"Fine, tell Fivetran the entire old row."
```

That's why `FULL` creates **more WAL data**.

You're logging more information per change.

For your small OMS demo:

> totally reasonable.

For a giant production table:

> you'd normally strongly prefer a proper primary key or suitable replica identity index.

---

# 12. Put everything together

You now have four layers:

```text
                  PostgreSQL
                      │
                      │ INSERT / UPDATE / DELETE
                      ▼
                ┌────────────┐
                │    WAL     │
                └────────────┘
                      │
              wal_level=logical
                      │
                      ▼
             logical decoding
                      │
                 pgoutput
                      │
        ┌─────────────┴─────────────┐
        │                           │
   publication_01          replication_slot_01
        │                           │
   WHAT tables?                WHERE are we?
        │                           │
        └─────────────┬─────────────┘
                      ▼
                   Fivetran
                      │
                      ▼
                  Snowflake
```

If you understand this picture, you've understood most of the setup.

---

# 13. What happens when Fivetran actually starts?

There are really **two phases**.

### Phase 1: Initial sync

Suppose Postgres already has:

```text
customers: 1,000 rows
orders:   50,000 rows
products:    200 rows
```

Fivetran first needs the existing state.

So it does roughly:

```text
Postgres existing tables
        │
        │ initial snapshot / dump
        ▼
     Fivetran
        │
        ▼
    Snowflake
```

Fivetran documentation describes the connection as initially pulling the selected existing data, then using CDC for subsequent changes. ([Fivetran][1])

---

## Phase 2: Incremental CDC

Now someone does:

```sql
INSERT INTO orders ...;

UPDATE customers ...;

DELETE FROM products ...;
```

Postgres writes them to WAL:

```text
WAL
├── INSERT order
├── UPDATE customer
└── DELETE product
```

Fivetran consumes:

```text
replication_slot_01
       │
       ▼
publication_01
       │
       ▼
pgoutput
       │
       ▼
Fivetran
       │
       ▼
Snowflake
```

No need to reload all 50,000 orders.

That's the main benefit.

---

# 14. Why do the names have to match Fivetran?

You create:

```text
publication_01
replication_slot_01
```

Then Fivetran's connector form asks:

```text
Publication Name:
publication_01

Replication Slot:
replication_slot_01
```

Fivetran is literally trying to access those Postgres objects.

If you enter:

```text
publication_1
```

instead of:

```text
publication_01
```

it's simply looking for an object that doesn't exist.

During setup, Fivetran validates both the publication and the WAL replication slot, including that the slot uses `pgoutput`. ([Fivetran][4])

---

# 15. Why publication first, slot second?

Your script does:

```sql
CREATE PUBLICATION publication_01 ...;
```

then:

```sql
SELECT pg_create_logical_replication_slot(
    'replication_slot_01',
    'pgoutput'
);
```

Fivetran's current setup documentation explicitly instructs creating the publication **before** creating the logical replication slot. ([Fivetran][3])

One subtle point:

**PostgreSQL itself doesn't fundamentally require the publication to exist merely to execute `pg_create_logical_replication_slot()`.**

This is specifically the setup sequence Fivetran expects/recommends.

So think:

```text
1. Define WHAT we're publishing.
2. Create the consumer's WAL position.
3. Give both names to Fivetran.
```

---

# 16. Your `replication.sql`, translated into English

I'm guessing it roughly looks like this conceptually:

```sql
ALTER TABLE customers REPLICA IDENTITY FULL;
ALTER TABLE orders REPLICA IDENTITY FULL;
ALTER TABLE products REPLICA IDENTITY FULL;
```

Translation:

> "These tables don't have primary keys, so log enough old-row information for Fivetran to understand UPDATEs and DELETEs."

Then:

```sql
DROP PUBLICATION IF EXISTS publication_01;

CREATE PUBLICATION publication_01
FOR ALL TABLES;
```

Translation:

> "Publish changes from all my tables."

Then something like:

```sql
SELECT pg_drop_replication_slot('replication_slot_01');
```

if it exists.

And then:

```sql
SELECT pg_create_logical_replication_slot(
    'replication_slot_01',
    'pgoutput'
);
```

Translation:

> "Start a fresh Fivetran bookmark using PostgreSQL's `pgoutput` decoder."

---

# 17. Why don't we normally keep recreating the slot?

Suppose Fivetran is here:

```text
WAL

A B C D E F G
          ↑
       Fivetran
```

The slot remembers:

```text
"I've consumed through E."
```

If you drop the slot:

```sql
SELECT pg_drop_replication_slot(...);
```

you destroy that bookmark.

Then create a new one:

```text
A B C D E F G H
                ↑
             new slot
```

The new slot starts from a new WAL position.

So you've effectively told Postgres:

> Forget where the previous Fivetran consumer was.

That can force you into re-sync/reset territory.

Hence:

```text
Normal operation
     ↓
KEEP THE SLOT

Resetting demo / rebuilding Fivetran connector
     ↓
DROP + RECREATE may be appropriate
```

---

# 18. The three things you actually need to remember

If somebody asks you tomorrow:

> "What do I need for Postgres → Fivetran CDC?"

Your answer can simply be:

1. **`wal_level = logical`**
   Make Postgres write enough WAL information for logical CDC.

2. **Publication**
   Defines **which tables** Fivetran is allowed to consume changes from.

3. **Replication slot + `pgoutput`**
   Tracks **how far Fivetran has consumed** the WAL and gives Fivetran the change stream.

And because your demo tables don't have PKs:

```text
REPLICA IDENTITY FULL
```

means:

> Include the full old row for updates/deletes so Fivetran can identify what changed.

---

## The one picture I'd keep in your head

```text
                      POSTGRES
                         │
                         │ rows change
                         ▼
                       WAL
                         │
              wal_level = logical
                         │
                         ▼
                     pgoutput
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
      publication_01         replication_slot_01
       "WHAT tables?"          "WHERE am I?"
            │                         │
            └────────────┬────────────┘
                         ▼
                      Fivetran
                         │
                         ▼
                      Snowflake
```

**Publication = WHAT. Slot = WHERE. `pgoutput` = HOW to decode. WAL = the change history. `REPLICA IDENTITY` = HOW to identify the row that changed.**

That's the conceptual model I'd make sure you can explain before touching `replication.sql`.

[1]: https://fivetran.com/docs/connectors/databases/postgresql?utm_source=chatgpt.com "PostgreSQL | Connector Overview | Fivetran Documentation"
[2]: https://neon.com/blog/cdc-with-materialize?utm_source=chatgpt.com "Change Data Capture with Neon and Materialize - Neon"
[3]: https://beta.fivetran.com/docs/connectors/databases/postgresql/setup-guide?utm_source=chatgpt.com "PostgreSQL | Connector Setup Guide | Fivetran Documentation"
[4]: https://fivetran.com/docs/connectors/databases/postgresql/setup-guide?utm_source=chatgpt.com "PostgreSQL | Connector Setup Guide | Fivetran Documentation"
