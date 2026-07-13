SELECT i.*
FROM {{ ref('stg_initiatives') }} i
JOIN {{ ref('stg_target_trajectory') }} t
    ON i.target_id = t.target_id
WHERE i.company_id != t.company_id
  AND i.is_orphan_target = FALSE