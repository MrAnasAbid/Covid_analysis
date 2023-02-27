USE Covid_database;

-- A : Creating a star scheme for our dataset
SELECT *
FROM Covid_data
ORDER BY 1,2;

-- The current format for the date column is datetime, since the time is the same, it's better to convert it to a date format
ALTER TABLE Covid_data
ALTER COLUMN date DATE;

-- For better response time with queries, some normalization will be made to the initial data :
 -- We can see that the iso_code determines the location which itself determines the continent, therefore a new table will be created storing this information and the location and continent columns are to be dropped
 -- from the fact table (deaths_vaccine), creating this table also adds an important dimension for further analysis
DROP TABLE IF EXISTS dim_location
CREATE TABLE dim_location
(
iso_code nvarchar(255) NOT NULL PRIMARY KEY,
location nvarchar(255),
continent nvarchar(255)
);

-- We then feed it with the necessary data
INSERT INTO dim_location
SELECT DISTINCT iso_code, location, continent
FROM covid_data
WHERE continent IS NOT NULL;

-- Checking if the table is created and the data is there
SELECT *
FROM dim_location;
	
-- Quickly check if the population is constant overtime
SELECT DISTINCT iso_code, location, population
FROM covid_data
WHERE continent IS NOT NULL;

-- In this dataset, the population is maintained constant for each country, we will store this information in the fact table by creating a new column
ALTER TABLE dim_location
ADD population float;

-- And feeding it with our data
UPDATE dim_location
SET dim_location.population = t2.population
FROM dim_location t1 INNER JOIN Covid_data t2 ON t1.iso_code = t2.iso_code
WHERE t2.continent IS NOT NULL;

-- We can now drop the location, population and continent columns from the fact table
ALTER TABLE covid_data
DROP COLUMN location, continent, population;

-- Also within this very dataset, there are rows where statistics for a whole continent are shown, these were the rows where the continent were null (therefore not included in our dim_location table)
SELECT *
FROM covid_data
WHERE iso_code NOT IN (SELECT iso_code FROM dim_location);

-- All of these rows correspond to a group by continent clause, we can recreate it if necessary, but for now it will be dropped
DELETE 
FROM covid_data
WHERE iso_code NOT IN (SELECT iso_code FROM dim_location);

-- We can easily find this data again if needed
SELECT t1.date, t2.continent, SUM(CAST(t1.total_cases AS INT)) AS total_cases, SUM(CAST(t1.total_deaths AS INT)) AS total_deaths
FROM covid_data t1 INNER JOIN dim_location t2 ON t1.iso_code = t2.iso_code
GROUP BY t1.date,t2.continent
ORDER BY 2,1;

SELECT DISTINCT date, YEAR(date), MONTH(date), DAY(date)
FROM covid_data
ORDER BY date;

-- In order to visualize the evolution of these metrics overtime, it's better to create a time dimension table
CREATE TABLE dim_time
(
date DATE NOT NULL PRIMARY KEY,
year INT,
month INT,
day INT,
);

-- And feed it
INSERT INTO dim_time
SELECT DISTINCT date, YEAR(date), MONTH(date), DAY(date)
FROM covid_data;

-- Creating primary and foreign key constraints for our tables
-- Composite primary key for the fact table, we need both the iso_code and date to determine the resulting values
ALTER TABLE Covid_data
ALTER COLUMN date date NOT NULL;

ALTER TABLE Covid_data
ALTER COLUMN iso_code nvarchar(255) NOT NULL;

ALTER TABLE Covid_data
ADD CONSTRAINT PK_Covid_data
PRIMARY KEY (iso_code, date);

-- Foreign key constraints, fact table's date and iso_code references respectively dim table's date and dim location's iso_code
ALTER TABLE Covid_data
ADD CONSTRAINT FK_date
FOREIGN KEY (date) REFERENCES dim_time(date);

ALTER TABLE Covid_data
ADD CONSTRAINT FK_iso_code
FOREIGN KEY (iso_code) REFERENCES dim_location(iso_code);


-- B : Exploring the data
SELECT iso_code, date, total_cases, new_cases, total_deaths, new_deaths, total_vaccinations, new_vaccinations, people_vaccinated, people_fully_vaccinated
FROM Covid_data;

-- Contraction percentage per country and day
SELECT t1.iso_code, total_cases, t2.population, (new_cases/t2.population) * 100 AS daily_contraction_percentage ,(total_cases/t2.population) * 100 AS rolling_contraction_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code;

-- Overall Contraction percentage per country (didn't expect the smaller countries to have the highest contractions rates)
SELECT t2.location, (t2.population) AS population, (SUM(new_cases)/(t2.population)) * 100 AS overall_contraction_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.location, t2.population
ORDER BY 3 DESC;

-- Overall contraction percentage per continent (In order to query it, we need to add a continent column to our data) :
-- Adding a new column
ALTER TABLE dim_location
ADD total_continent_population BIGINT;

-- Feeding it with the sum over each continent
UPDATE dim_location
SET dim_location.total_continent_population = t2.total_continent_population
FROM dim_location t1 LEFT JOIN (SELECT continent, SUM(population) as total_continent_population FROM dim_location GROUP BY continent) t2 ON t1.continent = t2.continent

-- We can finally see which continents were most affected with covid
SELECT t2.continent, t2.total_continent_population, (SUM(new_cases)/t2.total_continent_population) * 100 AS overall_contraction_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.continent, t2.total_continent_population
ORDER BY 3 DESC;

-- Africa and Asia seem to have a very low contraction percentage, let's look at it in detail :
SELECT t2.continent, t2.location, (t2.population) AS population, (SUM(new_cases)/(t2.population)) * 100 AS overall_contraction_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.continent, t2.location, t2.population
HAVING t2.continent IN ('Asia','Africa')
ORDER BY 4 DESC;

-- This further supports the hypothesis that bigger countries have lesser contraction rate in comparison to the smaller ones, Asia and Africa are the 2 biggest continents which makes
-- it understandable. However, it could also be due to a potential lack of tracking.

-- It would be interesting to look at other metrics : the death/mortality rate (overall deaths divided by the population) and the case fatality rate (overall deaths divided by the cases)
SELECT t1.iso_code, total_cases, t2.population, (new_cases/t2.population) * 100 AS daily_contraction_percentage, (new_deaths/t2.population) * 100 AS daily_mortality_percentage, (new_deaths/NULLIF(total_cases, 0)) * 100 as daily_fatality_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code;

-- Similarly to what was done previously, we will look at these metrics per countries and continents :
-- Countries :
SELECT t2.location,t2.population, ((SUM(CAST(new_cases AS INT))/t2.population)) * 100 AS contraction_percentage, ((SUM(CAST(new_deaths AS INT))/t2.population)) * 100 AS mortality_percentage, ((SUM(CAST(new_deaths AS INT))/SUM(CAST(new_cases AS INT)))) * 100 AS fatality_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.location, t2.population
ORDER BY 3 DESC;

SELECT t2.location,t2.population, ((SUM(CAST(new_cases AS INT))/t2.population)) * 100 AS contraction_percentage, ((SUM(CAST(new_deaths AS INT))/t2.population)) * 100  AS mortality_percentage, ((SUM(CAST(new_deaths AS FLOAT))/SUM(CAST(new_cases AS FLOAT)))) * 100 AS fatality_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.location, t2.population
ORDER BY 5 DESC;
-- It does seem like covid in North Korea is very, very dangerous !
SELECT t1.date, new_cases, total_cases, new_deaths, total_deaths
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
WHERE t2.location LIKE '%North K%'
-- A single case managed to kill 6 people, either this data isn't reliable for north korea, or they have a different covid variant that has a 600% fatality rate. I don't feel like
-- cleaning the data so I'll accept the second hypthesis and move on. Also kudos to England for keeping their secrets for themselves.

SELECT t2.location,t2.population, SUM(CAST(new_cases AS INT)) AS total_cases, SUM(CAST(new_deaths AS INT)) AS total_deaths, ((SUM(CAST(new_cases AS INT))/t2.population)) * 100 AS contraction_percentage, ((SUM(CAST(new_deaths AS INT))/t2.population)) * 1000  AS mortality_permillage, ((SUM(CAST(new_deaths AS FLOAT))/SUM(CAST(new_cases AS FLOAT)))) * 100 AS fatality_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.location, t2.population
HAVING t2.location NOT IN ('North Korea') -- I was joking of course
ORDER BY 7 DESC;
-- With Spain in 115th in terms of fatality percentage (and highest first world country), it is evident that covid took much more of a toll on lesser developped countries.

--Continents :
SELECT t2.continent, t2.total_continent_population, SUM(CAST(new_cases AS INT)) AS total_cases, SUM(CAST(new_deaths AS INT)) AS total_deaths, ((SUM(CAST(new_cases AS FLOAT))/t2.total_continent_population)) * 100 AS contraction_percentage, ((SUM(CAST(new_deaths AS FLOAT))/t2.total_continent_population)) * 1000  AS mortality_permillage, ((SUM(CAST(new_deaths AS FLOAT))/SUM(CAST(new_cases AS FLOAT)))) * 100 AS fatality_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.continent, t2.total_continent_population
ORDER BY 7 DESC;
-- With the lowest contraction percentage, Africa has the highest fatality percentage, followed by South America, it seems like third world countries have had trouble dealing with covid

-- C : Takeaways
-- Whilst primarly preparing the data and looking at it, we did find valuable insights that might help create a machine learning model afterwards :
	-- The contraction rate decreases when the population increases, another factor to take into consideration (that wasn't taken here) is the area of the country.
	-- The socioeconomic index plays a key part in the fatality percentage

-- Another insighful dimension to analyse our data is the evolution through time, it will be done with a more visualization friendly environment.

SELECT date, iso_code, new_cases, total_cases, new_deaths, total_deaths, new_cases_smoothed, new_deaths_smoothed
FROM Covid_data;

SELECT *
FROM dim_location;

SELECT *
FROM dim_time;

SELECT ((SUM(CAST(new_cases AS FLOAT))/t2.total_continent_population)) * 100 AS contraction_percentage, t2.continent
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.continent, t2.total_continent_population


SELECT t2.total_continent_population, ((SUM(CAST(new_cases AS FLOAT))/t2.total_continent_population)) * 100 AS contraction_percentage
FROM Covid_data t1 INNER JOIN dim_location t2 on t1.iso_code = t2.iso_code
GROUP BY t2.continent, t2.total_continent_population

