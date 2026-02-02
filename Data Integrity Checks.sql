USE SocialMedia_Campaign;
GO

/* =====================================================
   DATA QUALITY & INTEGRITY VALIDATION SCRIPT
   -----------------------------------------------------
   Purpose:
   This script performs comprehensive data quality checks
   across all core tables in the SocialMedia_Campaign
   database. The goal is to ensure that the data used for
   BI analysis, KPIs, and dashboards is accurate, consistent,
   and reliable.

   The script validates:
   - Uniqueness and duplicate records
   - Domain and range correctness
   - Missing (NULL) values
   - Referential integrity between related tables
   - Logical consistency across dates and events

   This validation layer is a critical prerequisite before
   ETL, modeling, and visualization stages in the BI pipeline.
   ===================================================== */

/* =====================================================
   1. USERS TABLE – DATA QUALITY CHECKS
   ===================================================== */

-- Check for duplicate user_id values
-- Verifies whether the primary identifier of users appears
-- more than once, which may indicate data ingestion issues
-- or missing primary key constraints.
WITH duplicate_users AS (
    SELECT user_id, COUNT(*) AS cnt
    FROM Users
    GROUP BY user_id
    HAVING COUNT(*) > 1
)
SELECT *
FROM duplicate_users;

-- Analyze whether duplicate user_id records represent
-- identical user profiles (same gender, age, country, location)
-- This helps distinguish between true duplicates and
-- conflicting records for the same identifier.
WITH duplicate_users AS (
    SELECT user_id, COUNT(*) AS cnt
    FROM Users
    GROUP BY user_id
    HAVING COUNT(*) > 1
), same_person AS (
    SELECT u.*, d.cnt
    FROM duplicate_users d
    JOIN Users u ON d.user_id = u.user_id
)
SELECT user_id, cnt, user_gender, user_age, country, location,
       COUNT(*) AS identical_rows
FROM same_person
GROUP BY user_id, cnt, user_gender, user_age, country, location
HAVING COUNT(*) > 1;

-- Inspect distinct values in the gender column
-- Used to validate domain consistency and detect invalid
-- or unexpected categorical values.
SELECT DISTINCT user_gender
FROM Users;

-- Validate user age range
-- Ensures that age values fall within a reasonable
-- and realistic numeric range.
SELECT MIN(user_age) AS min_age,
       MAX(user_age) AS max_age
FROM Users;

-- Check for missing values in critical user attributes
-- NULL values in these fields may negatively affect
-- segmentation, targeting, and demographic analysis.
SELECT COUNT(*) AS null_user_id FROM Users WHERE user_id IS NULL;
SELECT COUNT(*) AS null_gender  FROM Users WHERE user_gender IS NULL;
SELECT COUNT(*) AS null_age     FROM Users WHERE user_age IS NULL;
SELECT COUNT(*) AS null_country FROM Users WHERE country IS NULL;
SELECT COUNT(*) AS null_location FROM Users WHERE location IS NULL;

/* =====================================================
   2. CAMPAIGN TABLE – DATA QUALITY CHECKS
   ===================================================== */

-- Check for duplicate campaign identifiers
-- Ensures campaign_id uniquely represents each campaign.
SELECT campaign_id, COUNT(*) AS cnt
FROM Campaign
GROUP BY campaign_id
HAVING COUNT(*) > 1;

-- Check for duplicate campaign names
-- Identifies potential ambiguity in reporting and analysis
-- when campaigns share the same name.
SELECT name, COUNT(*) AS cnt
FROM Campaign
GROUP BY name
HAVING COUNT(*) > 1;

-- Validate campaign date logic
-- Identifies campaigns where the start date is later
-- than the end date, indicating invalid temporal data.
SELECT *
FROM Campaign
WHERE start_date > end_date;

-- Check for missing values in essential campaign attributes
-- NULL values here may lead to incorrect budget allocation
-- and timeline analysis.
SELECT COUNT(*) AS null_campaign_id FROM Campaign WHERE campaign_id IS NULL;
SELECT COUNT(*) AS null_name        FROM Campaign WHERE name IS NULL;
SELECT COUNT(*) AS null_start_date  FROM Campaign WHERE start_date IS NULL;
SELECT COUNT(*) AS null_end_date    FROM Campaign WHERE end_date IS NULL;
SELECT COUNT(*) AS null_budget      FROM Campaign WHERE total_budget IS NULL;

/* =====================================================
   3. AD TABLE – DATA QUALITY CHECKS
   ===================================================== */

-- Check for duplicate ad identifiers
-- Ensures that each ad is uniquely identifiable.
SELECT ad_id, COUNT(*) AS cnt
FROM Ad
GROUP BY ad_id
HAVING COUNT(*) > 1;

-- Inspect distinct advertising platforms
-- Validates platform domain values used for channel analysis.
SELECT DISTINCT ad_platform
FROM Ad;

-- Inspect distinct ad types
-- Helps detect unexpected or inconsistent ad classifications.
SELECT DISTINCT ad_type
FROM Ad;

-- Inspect target gender values
-- Ensures consistency in targeting dimensions.
SELECT DISTINCT target_gender
FROM Ad;

-- Check for missing values in critical ad attributes
-- NULLs here may break campaign-ad relationships
-- or skew targeting analysis.
SELECT COUNT(*) AS null_ad_id        FROM Ad WHERE ad_id IS NULL;
SELECT COUNT(*) AS null_campaign_id FROM Ad WHERE campaign_id IS NULL;
SELECT COUNT(*) AS null_platform    FROM Ad WHERE ad_platform IS NULL;
SELECT COUNT(*) AS null_type        FROM Ad WHERE ad_type IS NULL;
SELECT COUNT(*) AS null_gender      FROM Ad WHERE target_gender IS NULL;

/* =====================================================
   4. ADS_EVENTS TABLE – EVENT CONSISTENCY CHECKS
   ===================================================== */

-- Detect events with missing event identifiers
-- Such records cannot be reliably tracked or aggregated.
SELECT *
FROM Ads_Events
WHERE event_id IS NULL;

-- Check for duplicate event identifiers
-- Ensures each event is counted exactly once in analytics.
SELECT event_id, COUNT(*) AS cnt
FROM Ads_Events
GROUP BY event_id
HAVING COUNT(*) > 1;

-- Validate ad_id references in events
-- Identifies events linked to non-existing ads
-- (referential integrity violation).
SELECT *
FROM Ads_Events
WHERE ad_id NOT IN (SELECT ad_id FROM Ad);

-- Validate user_id references in events
-- Ensures all events are associated with valid users.
SELECT *
FROM Ads_Events
WHERE user_id NOT IN (SELECT user_id FROM Users);

-- Validate that events occur within the campaign active period
-- Events outside the campaign timeline may distort
-- performance metrics such as CTR and conversions.
SELECT e.timestamp, c.start_date, c.end_date
FROM Ads_Events e
JOIN Ad a ON e.ad_id = a.ad_id
JOIN Campaign c ON a.campaign_id = c.campaign_id
WHERE e.timestamp < c.start_date
   OR e.timestamp > c.end_date;

-- Detailed view: events occurring before campaign start
SELECT C.campaign_id, C.start_date, AE.timestamp
FROM Campaign C
JOIN Ad A ON C.campaign_id = A.campaign_id
JOIN Ads_Events AE ON AE.ad_id = A.ad_id
WHERE AE.timestamp < C.start_date
ORDER BY C.campaign_id;

-- Detailed view: events occurring after campaign end
SELECT C.campaign_id, C.end_date, AE.timestamp
FROM Campaign C
JOIN Ad A ON C.campaign_id = A.campaign_id
JOIN Ads_Events AE ON AE.ad_id = A.ad_id
WHERE AE.timestamp > C.end_date
ORDER BY C.campaign_id;

/* =====================================================
   5. CROSS-TABLE REFERENTIAL INTEGRITY CHECKS
   ===================================================== */

-- Identify ads linked to non-existing campaigns
-- Indicates broken foreign key relationships.
SELECT *
FROM Ad
WHERE campaign_id NOT IN (SELECT campaign_id FROM Campaign);

-- Identify campaigns that contain no ads
-- Such campaigns may indicate incomplete configuration
-- or unused marketing initiatives.
SELECT *
FROM Campaign
WHERE campaign_id NOT IN (SELECT campaign_id FROM Ad);

/* =====================================================
   6. USER_INTEREST TABLE – DUPLICATION CHECKS
   ===================================================== */

-- Detect duplicate (user_id, interest_id) pairs
-- Ensures that a user is not associated multiple times
-- with the same interest, which could bias interest-based
-- segmentation and recommendation logic.
WITH duplicate_users AS (
    SELECT user_id
    FROM Users
    GROUP BY user_id
    HAVING COUNT(*) > 1
), duplicate_interests AS (
    SELECT user_id, interest_id, COUNT(*) AS cnt
    FROM User_Interest
    GROUP BY user_id, interest_id
    HAVING COUNT(*) > 1
)
SELECT di.*
FROM duplicate_interests di
JOIN duplicate_users du ON di.user_id = du.user_id;

/* =====================================================
   END OF DATA QUALITY & VALIDATION SCRIPT
   ===================================================== */
