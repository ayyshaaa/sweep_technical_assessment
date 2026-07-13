SELECT i.*
FROM {{ ref('stg_initiatives') }} i
JOIN {{ ref('stg_companies') }} c
    ON i.company_id = c.company_id
WHERE i.start_year < c.base_year