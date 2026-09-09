-- =============================================================================
-- Verify the CDC test in Snowflake
-- =============================================================================
-- Companion to source/sql/cdc_test.sql. Run section 1 before you change
-- anything in Neon, and sections 2-3 after the Fivetran sync and dbt job.
--
-- Replace POSTGRES_DEMO_L1_LANDING below if SHOW SCHEMAS reported a different
-- landing schema name (it follows your Fivetran connection name).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Baseline, before running cdc_test.sql
-- Expect: Timothy Perez, 1 order, 1509.00
-- ---------------------------------------------------------------------------
SELECT CUSTOMERID, CUSTOMERNAME, ORDERCOUNT, REVENUE
FROM FIVETRAN_DEMO.SERVE.CUSTOMERREVENUE
WHERE CUSTOMERID = '28222';

-- Revenue for the customer whose order line gets deleted. Write it down.
SELECT CUSTOMERID, REVENUE
FROM FIVETRAN_DEMO.SERVE.CUSTOMERREVENUE
WHERE CUSTOMERID = '27613';

-- ---------------------------------------------------------------------------
-- 2. After the sync: the landing tables
-- ---------------------------------------------------------------------------
-- The update. Expect TWO rows, both with a fresh _FIVETRAN_SYNCED:
--   Perez-CDC  _FIVETRAN_DELETED = FALSE   the new version
--   Perez      _FIVETRAN_DELETED = TRUE    the version it replaced
--
-- These tables have no primary key, so Fivetran keys them on _FIVETRAN_ID, a
-- hash of every column value. Changing lastname changes the hash, so the update
-- arrives as an INSERT of the new row plus a soft DELETE of the old one.
-- Add SELECT * here if you want to see _FIVETRAN_ID differ between them.
SELECT CUSTOMERID, LASTNAME, _FIVETRAN_DELETED, _FIVETRAN_SYNCED
FROM FIVETRAN_DEMO.POSTGRES_DEMO_L1_LANDING.CUSTOMERS
WHERE CUSTOMERID = '28222'
ORDER BY _FIVETRAN_DELETED;

-- 101 rows in total, 100 of them current.
SELECT COUNT(*) AS customer_rows,
       COUNT_IF(COALESCE(_FIVETRAN_DELETED, FALSE) = FALSE) AS current_rows
FROM FIVETRAN_DEMO.POSTGRES_DEMO_L1_LANDING.CUSTOMERS;

-- The insert.
SELECT ORDERID, CUSTOMERID, EMPLOYEEID, STOREID, STATUS
FROM FIVETRAN_DEMO.POSTGRES_DEMO_L1_LANDING.ORDERS
WHERE ORDERID = 900001;

-- The delete. Line 4 is still here, flagged instead of removed.
SELECT ORDERITEMID, QUANTITY, UNITPRICE, _FIVETRAN_DELETED
FROM FIVETRAN_DEMO.POSTGRES_DEMO_L1_LANDING.ORDERITEMS
WHERE ORDERID = 800000
ORDER BY ORDERITEMID;

-- ---------------------------------------------------------------------------
-- 3. After the dbt job: the reporting tables
-- ---------------------------------------------------------------------------
-- Expect TWO rows, both 2 orders and 1624.00: one under Timothy Perez and one
-- under Timothy Perez-CDC. The insert landed (1 order / 1509.00 before), and so
-- did the rename, but customers_stg still carries the superseded customer row,
-- so the join to orders_fact fans out and revenue is counted under both names.
SELECT CUSTOMERID, CUSTOMERNAME, ORDERCOUNT, REVENUE
FROM FIVETRAN_DEMO.SERVE.CUSTOMERREVENUE
WHERE CUSTOMERID = '28222';

-- What the staging models would see if they filtered the flag: one row, 100
-- current customers. This is the fix the project does not make; see Part 3.3.
SELECT COUNT(*) AS current_customer_rows
FROM FIVETRAN_DEMO.POSTGRES_DEMO_L1_LANDING.CUSTOMERS
WHERE COALESCE(_FIVETRAN_DELETED, FALSE) = FALSE;

-- The new order is the only Online row: orders_stg maps StoreID 1000 to Online.
SELECT ORDERID, CUSTOMERID, ORDER_CHANNEL
FROM FIVETRAN_DEMO.TRANSFORM.ORDERS_STG
WHERE ORDER_CHANNEL = 'Online';

-- Unchanged, and that is the point: the soft-deleted line is still summed
-- because orderitems_stg does not filter _FIVETRAN_DELETED.
SELECT CUSTOMERID, REVENUE
FROM FIVETRAN_DEMO.SERVE.CUSTOMERREVENUE
WHERE CUSTOMERID = '27613';
