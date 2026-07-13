SELECT e.*
FROM {{ ref('stg_emissions') }} e
JOIN {{ ref('stg_companies') }} c
    ON e.company_id = c.company_id
WHERE e.year < c.base_year
  AND is_invalid_year = FALSE