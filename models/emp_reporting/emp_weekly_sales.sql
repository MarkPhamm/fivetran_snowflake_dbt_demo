{{ config(materialized='table') }}

SELECT
    e.EmployeeID,
    e.EmployeeName,
    DATE_TRUNC('week', o.OrderDate) AS week_start_date,
    COUNT(DISTINCT o.OrderID) AS total_orders,
    SUM(o.Revenue) AS total_sales
FROM
    {{ ref('orders_fact') }} o
JOIN
    {{ ref('employees_stg') }} e
    ON o.EmployeeID = e.EmployeeID
WHERE
    o.EmployeeID IS NOT NULL
GROUP BY 1,2,3
