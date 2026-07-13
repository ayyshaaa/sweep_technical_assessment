SELECT *
FROM {{ ref('stg_emissions') }}
WHERE year > YEAR(CURRENT_DATE)
  AND is_invalid_year = FALSE