SELECT i.*
FROM {{ ref('stg_initiatives') }} i
LEFT JOIN {{ ref('stg_initiatives') }} parent
    ON i.parent_group_id = parent.initiative_id
    AND parent.group_type = 'bottom_up_group'
WHERE i.group_type = 'bottom_up_child'
  AND parent.initiative_id IS NULL