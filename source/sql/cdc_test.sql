-- =============================================================================
-- CDC test: change rows in Neon and let the pipeline carry them to Snowflake
-- =============================================================================
-- Run this only after the whole demo works end to end: the Fivetran connection
-- syncs l1_landing into FIVETRAN_DEMO, and the dbt job builds TRANSFORM/SERVE.
--
-- Nothing here is special to Fivetran. These are ordinary DML statements.
-- Postgres writes each one to the WAL, and Fivetran picks them up through
-- replication_slot_01 on the next sync, shipping only the changed rows.
--
-- Run in the Neon SQL Editor on database fivetran_source (not neondb).
-- Undo it later with cdc_revert.sql. Verify with snowflake/sql/cdc_verify.sql.
--
-- Target rows are chosen so the arithmetic is easy to check:
--   customer 28222 (Timothy Perez) has exactly one order, 800143, worth 1509.00
--   customer 27613 owns order 800000, whose line 4 is worth 300.00
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. UPDATE
-- CustomerName in SERVE.CUSTOMERREVENUE is built from firstname + lastname,
-- so a rename is visible at the far end of the pipeline.
-- ---------------------------------------------------------------------------
UPDATE l1_landing.customers
SET lastname = 'Perez-CDC',
    updated_at = now()
WHERE customerid = '28222';

-- ---------------------------------------------------------------------------
-- 2. INSERT
-- A new order for the same customer, plus two lines worth 115.00 in total
-- (2 x 40.00 + 1 x 35.00), so 28222 moves from 1 order / 1509.00 to
-- 2 orders / 1624.00 in SERVE.CUSTOMERREVENUE. It shows up there twice, once
-- per surviving version of the customer row; Part 3.2 explains why.
--
-- storeid 1000 is deliberate: orders_stg labels that store 'Online' and no
-- seed order uses it, so this is the only Online row in TRANSFORM.ORDERS_STG.
-- employeeid 507279 is a real employee, so emp_weekly_sales can join it.
-- ---------------------------------------------------------------------------
INSERT INTO l1_landing.orders (orderid, orderdate, customerid, employeeid, storeid, status, updated_at)
VALUES (900001, CURRENT_DATE, '28222', 507279, '1000', '02', now());

INSERT INTO l1_landing.orderitems (orderid, orderitemid, productid, quantity, unitprice, updated_at)
VALUES (900001, 1, 74900, 2, 40.00, now()),
       (900001, 2, 70518, 1, 35.00, now());

-- ---------------------------------------------------------------------------
-- 3. DELETE
-- One line off an unrelated order so the delete can be tracked on its own.
-- Fivetran soft-deletes by default: the row stays in Snowflake with
-- _FIVETRAN_DELETED = TRUE instead of disappearing.
-- ---------------------------------------------------------------------------
DELETE FROM l1_landing.orderitems
WHERE orderid = 800000
  AND orderitemid = 4;

-- ---------------------------------------------------------------------------
-- 4. Source-side check (optional)
-- Expect: lastname Perez-CDC, 2 rows for order 900001, 9 rows for order 800000.
-- ---------------------------------------------------------------------------
SELECT customerid, firstname, lastname, updated_at
FROM l1_landing.customers
WHERE customerid = '28222';

SELECT orderid, orderitemid, quantity, unitprice
FROM l1_landing.orderitems
WHERE orderid = 900001
ORDER BY orderitemid;

SELECT COUNT(*) AS remaining_lines_on_800000
FROM l1_landing.orderitems
WHERE orderid = 800000;
