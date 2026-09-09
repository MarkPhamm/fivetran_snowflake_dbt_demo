-- =============================================================================
-- Undo cdc_test.sql and put the seed data back
-- =============================================================================
-- Run in the Neon SQL Editor on database fivetran_source (not neondb), after
-- you have finished checking the CDC test in Snowflake.
--
-- These are three more changes, so they travel the same path: sync the Fivetran
-- connection again and the dbt job rebuilds TRANSFORM and SERVE.
--
-- Every value below is restored to its exact seed value, updated_at included.
-- That matters on tables without a primary key: Fivetran keys rows on a hash of
-- all their values, so an identical row hashes back to the _FIVETRAN_ID of the
-- row it soft-deleted earlier and can revive it instead of appending yet another
-- version. Use now() here and you get a third row for customer 28222.
--
-- Even so, the landing tables keep the versions they retired during the test, so
-- SERVE.CUSTOMERREVENUE keeps double-counting customer 28222. To get a clean
-- landing copy, re-sync the customers and orderitems tables from the Fivetran
-- connection's schema tab, which drops and reloads them, then rerun the dbt job.
-- =============================================================================

-- Undo the rename
UPDATE l1_landing.customers
SET lastname = 'Perez',
    updated_at = '2025-06-14 18:29:55'
WHERE customerid = '28222';

-- Remove the test order (lines first)
DELETE FROM l1_landing.orderitems WHERE orderid = 900001;
DELETE FROM l1_landing.orders WHERE orderid = 900001;

-- Put the deleted line back with its seed values
INSERT INTO l1_landing.orderitems (orderid, orderitemid, productid, quantity, unitprice, updated_at)
VALUES (800000, 4, 77443, 10, 30.00, '2025-07-03 00:54:48');

-- Check: Perez, no rows for 900001, ten lines on 800000
SELECT customerid, firstname, lastname, updated_at FROM l1_landing.customers WHERE customerid = '28222';
SELECT COUNT(*) AS rows_for_900001 FROM l1_landing.orders WHERE orderid = 900001;
SELECT COUNT(*) AS lines_on_800000 FROM l1_landing.orderitems WHERE orderid = 800000;
