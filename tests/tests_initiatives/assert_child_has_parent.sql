SELECT *
FROM {{ ref('stg_initiatives') }}
WHERE group_type = 'bottom_up_child'
  AND parent_group_id IS NULL