-- Create schema Nexa_Sat
-- Create table in the schema
CREATE TABLE Nexa_Sat(
    Customer_ID VARCHAR(50),
    gender VARCHAR(10),
    Partner VARCHAR(3),
    Dependents VARCHAR(3),
    Senior_Citizen INT,
    Call_Duration FLOAT,
    Data_Usage FLOAT,
    Plan_Type VARCHAR(20),
    Plan_Level VARCHAR(20),
    Monthly_Bill_Amount FLOAT,
    Tenure_Months INT,
    Multiple_Lines VARCHAR(3),
    Tech_Support VARCHAR(3),
    Churn INT
);

-- Importing the nexa_sat data using the import wizard
-- View data
SELECT * 
FROM nexa_sat;

-- Data Cleaning
-- Check for duplicates
SELECT customer_id, gender, partner, dependents, 
       senior_citizen, call_duration, data_usage, 
       plan_type, plan_level, monthly_bill_amount, 
       tenure_months, multiple_lines, tech_support, churn
FROM nexa_sat
GROUP BY customer_id, gender, partner, dependents, 
         senior_citizen, call_duration, data_usage, 
         plan_type, plan_level, monthly_bill_amount, 
         tenure_months, multiple_lines, tech_support, churn
HAVING COUNT(*) > 1; -- This filters out rows that are not duplicates

-- Check for null values
SELECT *
FROM nexa_sat
WHERE customer_id IS NULL
OR gender IS NULL
OR partner IS NULL
OR dependents IS NULL
OR senior_citizen IS NULL
OR call_duration IS NULL
OR data_usage IS NULL
OR plan_type IS NULL
OR plan_level IS NULL 
OR monthly_bill_amount IS NULL
OR tenure_months IS NULL
OR multiple_lines IS NULL
OR tech_support IS NULL
OR churn IS NULL;

-- EDA
-- Total users
SELECT COUNT(customer_id) AS total_users
FROM nexa_sat;

-- Total users by level
SELECT plan_level, 
       COUNT(customer_id) AS total_users
FROM nexa_sat
GROUP BY 1;

-- Total revenue
SELECT ROUND(SUM(monthly_bill_amount), 2) AS revenue
FROM nexa_sat;

-- Revenue by plan level 
SELECT plan_level, 
       ROUND(SUM(monthly_bill_amount), 2) AS revenue
FROM nexa_sat
GROUP BY 1
ORDER BY 2 DESC;

-- Churn count by plan type and plan level
SELECT plan_level, 
       plan_type, 
       COUNT(*) AS total_customers,
       SUM(churn) AS churn_count
FROM nexa_sat
GROUP BY 1, 2
ORDER BY 1;

-- Average tenure by level
SELECT plan_level, 
       ROUND(AVG(tenure_months), 2) AS avg_tenure
FROM nexa_sat
GROUP BY 1;

-- CLV Marketing Segments
-- Create table of only existing users
CREATE TABLE existing_users AS
SELECT *
FROM nexa_sat
WHERE churn = 0;

-- View new table
SELECT *
FROM existing_users;

-- Calculate ARPU for existing users
SELECT ROUND(AVG(Monthly_Bill_Amount), 2) AS ARPU
FROM existing_users;

-- Calculate CLV and add column
ALTER TABLE existing_users
ADD COLUMN clv FLOAT;

UPDATE existing_users
SET clv = Monthly_Bill_Amount * tenure_months;

-- View new clv column
SELECT customer_id, clv
FROM existing_users;

-- CLV Score
-- Assign weights and calculate clv score
-- Monthly bill = 40%, tenure = 30%, call_duration = 10%, data = 10%, premium = 10%
ALTER TABLE existing_users
ADD COLUMN clv_score NUMERIC(10, 2);

UPDATE existing_users
SET clv_score =  
    (0.4 * Monthly_Bill_Amount) + 
    (0.3 * Tenure_Months) + 
    (0.1 * Call_Duration) + 
    (0.1 * Data_Usage) + 
    (0.1 * CASE 
            WHEN plan_level = 'Premium' THEN 1 
            ELSE 0 
        END);

-- View new clv_score column
SELECT customer_id, 
       clv_score
FROM existing_users;

-- Group into segments based on scores
-- Add new column
ALTER TABLE existing_users
ADD COLUMN clv_segment VARCHAR(50);

-- Create a temporary table to store percentile values
CREATE TEMPORARY TABLE percentiles AS
SELECT 
    (SELECT clv_score FROM existing_users ORDER BY clv_score LIMIT 1 OFFSET FLOOR(0.85 * COUNT(*) OVER()) - 1) AS p85,
    (SELECT clv_score FROM existing_users ORDER BY clv_score LIMIT 1 OFFSET FLOOR(0.50 * COUNT(*) OVER()) - 1) AS p50,
    (SELECT clv_score FROM existing_users ORDER BY clv_score LIMIT 1 OFFSET FLOOR(0.25 * COUNT(*) OVER()) - 1) AS p25
FROM existing_users
LIMIT 1;

-- Update clv_segment based on the calculated percentiles
UPDATE existing_users eu
JOIN percentiles p ON 1=1
SET eu.clv_segment = CASE
    WHEN eu.clv_score > p.p85 THEN 'High Value'
    WHEN eu.clv_score >= p.p50 THEN 'Moderate Value'
    WHEN eu.clv_score >= p.p25 THEN 'Low Value'
    ELSE 'Churn Risk'
END;

-- View segments
SELECT customer_id, clv_score, clv_segment
FROM existing_users;

-- Analyze segments

-- Customer count per segment
SELECT clv_segment, COUNT(*) AS segment_count
FROM existing_users
GROUP BY clv_segment;

-- Average bill and tenure per segment
SELECT clv_segment, 
       ROUND(AVG(monthly_bill_amount), 2) AS avg_monthly_charges,
       ROUND(AVG(tenure_months), 2) AS avg_tenure
FROM existing_users
GROUP BY clv_segment;

-- Tech support count and additional line count
SELECT clv_segment, 
       ROUND(AVG(CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END), 2) AS tech_support_pct,
       ROUND(AVG(CASE WHEN multiple_lines = 'Yes' THEN 1 ELSE 0 END), 2) AS additional_line_pct
FROM existing_users
GROUP BY clv_segment;

-- Revenue per segment
SELECT clv_segment, COUNT(customer_id),
       CAST(SUM(monthly_bill_amount * tenure_months) AS DECIMAL(10,2)) AS total_revenue
FROM existing_users
GROUP BY clv_segment;

-- Cross Selling and Up Selling

-- Senior citizens who could use tech support
SELECT customer_id
FROM existing_users
WHERE senior_citizen = 1
AND dependents = 'No'
AND tech_support = 'No'
AND (clv_segment = 'Churn Risk' OR clv_segment = 'Low Value');

-- Premium discount for basic users with churn risk
SELECT customer_id
FROM existing_users
WHERE clv_segment = 'Churn Risk'
AND plan_level = 'Basic';

-- Multiple lines for dependents and partners on basic plan
SELECT customer_id
FROM existing_users
WHERE multiple_lines = 'No'
AND (dependents = 'Yes' OR partner = 'Yes')
AND plan_level = 'Basic';

-- Basic to premium to longer lock-in period and higher ARPU
SELECT plan_level, AVG(monthly_bill_amount), AVG(tenure_months)
FROM existing_users
WHERE clv_segment = 'Moderate Value'
OR clv_segment = 'High Value'
GROUP BY plan_level;

-- Select higher paying customer IDs for the upgrade offer
SELECT customer_id, monthly_bill_amount
FROM existing_users
WHERE plan_level = 'Basic'
AND (clv_segment = 'High Value' OR clv_segment = 'Moderate Value')
AND monthly_bill_amount > 150;

-- Create Stored Procedures

DELIMITER //

-- Senior citizens who will be offered tech support
CREATE PROCEDURE tech_support_snr_citizens()
BEGIN
    SELECT customer_id
    FROM existing_users
    WHERE senior_citizen = 1
    AND dependents = 'No'
    AND tech_support = 'No'
    AND (clv_segment = 'Churn Risk' OR clv_segment = 'Low Value');
END //

-- At-risk customers who will be offered premium discount
CREATE PROCEDURE churn_risk_discount()
BEGIN
    SELECT customer_id
    FROM existing_users
    WHERE clv_segment = 'Churn Risk'
    AND plan_level = 'Basic';
END //

-- Customers for multiple lines offer
CREATE PROCEDURE multiple_lines_offer()
BEGIN
    SELECT customer_id
    FROM existing_users
    WHERE multiple_lines = 'No'
    AND (dependents = 'Yes' OR partner = 'Yes')
    AND plan_level = 'Basic';
END //

-- High usage customers who will be offered a premium upgrade
CREATE PROCEDURE high_usage_basic()
BEGIN
    SELECT customer_id
    FROM existing_users
    WHERE plan_level = 'Basic'
    AND (clv_segment = 'High Value' OR clv_segment = 'Moderate Value')
    AND monthly_bill_amount > 150;
END //

DELIMITER ;

-- Use Procedures
CALL tech_support_snr_citizens();
CALL churn_risk_discount();
CALL multiple_lines_offer();
CALL high_usage_basic();

-- View segments
SELECT customer_id, 
      clv_score, 
      clv_segment
FROM existing_users;

SELECT * 
FROM existing_users;
