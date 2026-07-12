-- The trajectory must be decreasing year over year (since this is a REDUCTION trajectory)
WITH trajectory AS (
    SELECT
        target_id,
        year,
        expected_emissions_tco2e,
        LAG(expected_emissions_tco2e) OVER (
            PARTITION BY target_id 
            ORDER BY year
        ) as prev_year_emissions
    FROM {{ ref('stg_target_trajectory') }}
)
SELECT *
FROM trajectory
WHERE expected_emissions_tco2e > prev_year_emissions
  AND prev_year_emissions IS NOT NULL