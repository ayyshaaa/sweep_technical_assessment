-- year must be between baseline_year and target_year
SELECT * FROM {{ ref('stg_target_trajectory') }}
WHERE year < baseline_year
   OR year > target_year