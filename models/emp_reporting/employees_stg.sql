-- models/emp_reporting/employees_stg.sql

select
    employeeid,
    firstname,
    lastname,
    email,
    jobtitle,
    hiredate,
    managerid,
    address,
    city,
    state,
    zipcode,
    updated_at,
    concat(firstname, ' ', lastname) as employeename
from
    {{ source('landing', 'employees') }}