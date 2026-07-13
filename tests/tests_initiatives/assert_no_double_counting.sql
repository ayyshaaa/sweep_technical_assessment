SELECT
    parent.initiative_id,
    parent.estimated_reduction      AS group_reduction,
    SUM(child.estimated_reduction)  AS children_sum
FROM {{ ref('stg_initiatives') }} parent
JOIN {{ ref('stg_initiatives') }} child
    ON child.parent_group_id = parent.initiative_id
WHERE parent.group_type = 'bottom_up_group'
GROUP BY parent.initiative_id, parent.estimated_reduction
HAVING ABS(SUM(child.estimated_reduction) - parent.estimated_reduction) > 0.01