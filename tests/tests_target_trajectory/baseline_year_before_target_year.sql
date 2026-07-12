-- baseline_year must be strictly below target_year
SELECT * FROM {{ ref('stg_target_trajectory') }}
WHERE baseline_year >= target_year