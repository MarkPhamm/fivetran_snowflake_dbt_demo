-- Create schema
CREATE SCHEMA IF NOT EXISTS l1_landing;

-- CUSTOMERS table
CREATE TABLE IF NOT EXISTS l1_landing.customers (
    customerid VARCHAR(10),
    firstname VARCHAR(50),
    lastname VARCHAR(50),
    email VARCHAR(100),
    phone VARCHAR(50),
    address VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2),
    zipcode VARCHAR(10),
    updated_at TIMESTAMP
);

-- DATES table
CREATE TABLE IF NOT EXISTS l1_landing.dates (
    "date" DATE,
    day INTEGER,
    month INTEGER,
    year INTEGER,
    quarter INTEGER,
    dayofweek VARCHAR(20),
    weekofyear INTEGER,
    updated_at TIMESTAMP
);

-- EMPLOYEES table
CREATE TABLE IF NOT EXISTS l1_landing.employees (
    employeeid INTEGER,
    firstname VARCHAR(50),
    lastname VARCHAR(50),
    email VARCHAR(100),
    jobtitle VARCHAR(50),
    hiredate DATE,
    managerid INTEGER,
    address VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2),
    zipcode VARCHAR(10),
    updated_at TIMESTAMP
);

-- PRODUCTS table
CREATE TABLE IF NOT EXISTS l1_landing.products (
    productid INTEGER,
    name VARCHAR(100),
    category VARCHAR(50),
    retailprice INTEGER,
    supplierprice INTEGER,
    supplierid INTEGER,
    updated_at TIMESTAMP
);

-- SUPPLIERS table
CREATE TABLE IF NOT EXISTS l1_landing.suppliers (
    supplierid INTEGER,
    suppliername VARCHAR(100),
    contactperson VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(30),
    address VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(10),
    zipcode VARCHAR(20),
    updated_at TIMESTAMP
);

-- STORES table
CREATE TABLE IF NOT EXISTS l1_landing.stores (
    storeid VARCHAR(10),
    storename VARCHAR(50),
    address VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(10),
    zipcode VARCHAR(20),
    email VARCHAR(100),
    phone VARCHAR(30),
    updated_at TIMESTAMP
);

-- ORDERITEMS table
CREATE TABLE IF NOT EXISTS l1_landing.orderitems (
    orderid INT,
    orderitemid INT,
    productid INT,
    quantity INT,
    unitprice NUMERIC(10, 2),
    updated_at TIMESTAMP
);

-- ORDERS table
CREATE TABLE IF NOT EXISTS l1_landing.orders (
    orderid INT,
    orderdate DATE,
    customerid VARCHAR(10),
    employeeid INT,
    storeid VARCHAR(10),
    status VARCHAR(2),
    updated_at TIMESTAMP
);
