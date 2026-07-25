USE greentech;
GO

--------------------------------------------------
-- Data Assessment and understanding the Data Structure
--------------------------------------------------
SELECT * FROM downtime_factors;
SELECT * FROM line_downtime;
SELECT * FROM line_productivity_batches;
SELECT * FROM products;

-- Number of rows
SELECT COUNT(*) AS numbrows_downtime_factors FROM downtime_factors;
SELECT COUNT(*) AS numbrows_line_downtime FROM line_downtime;
SELECT COUNT(*) AS numbrows_line_productivity_batches FROM line_productivity_batches;
SELECT COUNT(*) AS numbrows_products FROM products;

-- Check for Null
SELECT COUNT(*) AS Factor1_nullcount 
FROM line_downtime
WHERE Factor_1 IS NULL;

-- All factors count of null
SELECT COUNT(*) AS all_factors_null_count
FROM line_downtime
WHERE COALESCE(
    Factor_1, Factor_2, Factor_3, Factor_4, Factor_5,
    Factor_6, Factor_7, Factor_8, Factor_9, Factor_10,
    Factor_11, Factor_12, Factor_13
) IS NULL;

-- Start Date repetition in "Date" and "Start_Time" columns
WITH start_dates AS (
    SELECT 
        Date, 
        CAST(Start_TIME AS DATE) AS Start_Date
    FROM line_productivity_batches
)
SELECT *
FROM start_dates
WHERE Date != Start_Date;
GO


--------------------------------------------------
-- Data Cleaning and Transformation
-- Handle null line downtime (unpivoted table)
--------------------------------------------------
IF OBJECT_ID('dbo.downtimes', 'V') IS NOT NULL
    DROP VIEW dbo.downtimes;
GO

CREATE VIEW dbo.downtimes AS
SELECT 
    Batch_ID, 
    REPLACE(Factor, 'Factor_', '') AS Factor_ID, 
    Minutes
FROM line_downtime
UNPIVOT (
    Minutes FOR Factor IN (
        Factor_1, Factor_2, Factor_3, Factor_4, Factor_5, Factor_6,
        Factor_7, Factor_8, Factor_9, Factor_10, Factor_11, Factor_12, Factor_13
    )
) AS UnpivotDowntimes;
GO

SELECT *
FROM dbo.downtimes
ORDER BY Batch_ID;
GO


--------------------------------------------------
-- New batch production table 
-- (Date as Start Date, extract time from start and end time)
--------------------------------------------------
IF OBJECT_ID('dbo.batch_pd', 'V') IS NOT NULL
    DROP VIEW dbo.batch_pd;
GO

CREATE VIEW batch_pd AS
SELECT 
    Date AS Start_Date, 
    Product_ID, 
    Batch_ID, 
    Operator, 
    CAST(End_Time AS DATE) AS End_Date,
    CAST(Start_Time AS TIME) AS Start_Time, 
    CAST(End_Time AS TIME) AS End_Time, 
    Planned_Min_Batch_Hours,
    DATEDIFF(hour, Start_Time, End_Time) AS Actual_Duration,
    DATEDIFF(hour, Start_Time, End_Time) - Planned_Min_Batch_Hours AS Extra_Time_Hr
FROM line_productivity_batches;
GO

SELECT * 
FROM batch_pd;
GO

--------------------------------------------------
-- VALIDATION: Compare downtime minutes vs extra time
--------------------------------------------------
SELECT 
    batch_pd.Batch_ID, 
    SUM(Minutes) AS accounted_delay_minutes, 
    Extra_Time_Hr
FROM batch_pd
JOIN downtimes 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
GROUP BY 
    batch_pd.Batch_ID, 
    Extra_Time_Hr;
GO

--------------------------------------------------
-- ANALYSIS
-- Downtime key factors (which issues cause the most delays?)
--------------------------------------------------
SELECT 
    Factor_Name, 
    COUNT(downtimes.Batch_ID) AS Frequency, 
    SUM(Minutes) AS Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
GROUP BY Factor_Name
ORDER BY Delay_Mins DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Operator vs Non‑Operator Errors
--------------------------------------------------
SELECT
    CASE Operator_Error
        WHEN 1 THEN 'Yes'   -- Operator caused the issue
        WHEN 0 THEN 'No'    -- Not caused by operator
    END AS Operator_Error,
    COUNT(downtimes.Batch_ID) AS Frequency,
    SUM(Minutes) AS Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
GROUP BY Operator_Error
ORDER BY Delay_Mins DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Downtime Operator Errors (Which operator mistakes cause the most delays?)
--------------------------------------------------
SELECT 
    Factor_Name, 
    Description, 
    COUNT(downtimes.Batch_ID) AS Frequency, 
    SUM(Minutes) AS Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
WHERE Operator_Error = 1   -- Only operator-caused issues
GROUP BY 
    Factor_Name, 
    Description
ORDER BY 
    SUM(Minutes) DESC;      -- Biggest delays at the top
GO

-- Downtime Non Operator Errors (Which operator mistakes cause the most delays?)
--------------------------------------------------
SELECT 
    Factor_Name, 
    Description, 
    COUNT(downtimes.Batch_ID) AS Frequency, 
    SUM(Minutes) AS Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
WHERE Operator_Error = 0   
GROUP BY 
    Factor_Name, 
    Description
ORDER BY 
    SUM(Minutes) DESC;      

    --------------------------------------------------
-- Products and downtime frequency & delay (mins)
--------------------------------------------------
SELECT 
    batch_pd.Product_ID,
    Product_Name,
    COUNT(downtimes.Batch_ID) AS Frequency,
    SUM(Minutes) AS Delay_Mins
FROM batch_pd
JOIN downtimes 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
JOIN products 
    ON batch_pd.Product_ID = products.Product_ID
GROUP BY 
    batch_pd.Product_ID,
    Product_Name
ORDER BY 
    Delay_Mins DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- How many factors are involved in each product downtime?
--------------------------------------------------
SELECT 
    batch_pd.Product_ID,
    Product_Name,
    COUNT(DISTINCT Factor_ID) AS Distinct_Factors_Count
FROM batch_pd
JOIN products 
    ON batch_pd.Product_ID = products.Product_ID
JOIN downtimes 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
GROUP BY 
    batch_pd.Product_ID,
    Product_Name
ORDER BY 
    batch_pd.Product_ID;
GO

--------------------------------------------------
-- ANALYSIS
-- Top 5 factors for Product 1 downtime
--------------------------------------------------
SELECT TOP 5 
    Factor_Name, 
    SUM(Minutes) AS Prd001_Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE batch_pd.Product_ID = 'PRD001'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Top 5 factors for Product 2 downtime
--------------------------------------------------
SELECT TOP 5 
    Factor_Name, 
    SUM(Minutes) AS Prd002_Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE batch_pd.Product_ID = 'PRD002'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Top 5 factors for Product 3 downtime
--------------------------------------------------
SELECT TOP 5 
    Factor_Name, 
    SUM(Minutes) AS Prd003_Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE batch_pd.Product_ID = 'PRD003'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Top 5 factors for Product 4 downtime
--------------------------------------------------
SELECT TOP 5 
    Factor_Name, 
    SUM(Minutes) AS Prd004_Delay_Mins
FROM downtimes
JOIN downtime_factors 
    ON downtimes.Factor_ID = downtime_factors.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE batch_pd.Product_ID = 'PRD004'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Production Lead Operators
-- (How many batches and how many different products each operator handled)
--------------------------------------------------
SELECT 
    Operator,
    COUNT(Batch_ID) AS Number_of_Batches,
    COUNT(DISTINCT Product_ID) AS Number_of_Products
FROM batch_pd
GROUP BY 
    Operator
ORDER BY 
    Number_of_Batches DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Production Lead Operator and Downtime Duration, Percentage Delayed Batches
--------------------------------------------------
SELECT 
    Operator,
    COUNT(DISTINCT batch_pd.Batch_ID) AS Total_Batches,
    COUNT(DISTINCT downtimes.Batch_ID) AS Number_of_delayed_batches,
    COUNT(downtimes.Batch_ID) AS Number_of_downtimes,
    SUM(Minutes) AS Delay_Mins,
    CAST(
        (COUNT(DISTINCT downtimes.Batch_ID) * 100.0) 
        / COUNT(DISTINCT batch_pd.Batch_ID)
        AS DECIMAL(10,2)
    ) AS Percentage_delayed_batches
FROM batch_pd
LEFT JOIN downtimes 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
GROUP BY 
    Operator
ORDER BY 
    Percentage_delayed_batches DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for top 3 lead operators with the most delay duration
-- 1. Paul
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Paul'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for top 3 lead operators with the most delay duration
-- 1. Paul
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Paul'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for top 3 lead operators with the most delay duration
-- 2. James
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'James'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for top 3 lead operators with the most delay duration
-- 3. Emily
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Emily'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for the top 3 operators with the most percentage delayed batches
-- 1. Linda
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Linda'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for the top 3 operators with the most percentage delayed batches
-- 2. Sophia
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Sophia'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO

--------------------------------------------------
-- ANALYSIS
-- Factors causing downtime for the top 3 operators with the most percentage delayed batches
-- 3. Rita
--------------------------------------------------
SELECT 
    Factor_Name, 
    SUM(Minutes) AS Delay_Mins
FROM downtime_factors
JOIN downtimes 
    ON downtime_factors.Factor_ID = downtimes.Factor_ID
JOIN batch_pd 
    ON batch_pd.Batch_ID = downtimes.Batch_ID
WHERE Operator = 'Rita'
GROUP BY 
    Factor_Name
ORDER BY 
    SUM(Minutes) DESC;
GO







