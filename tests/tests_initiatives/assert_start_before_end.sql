SELECT *
FROM {{ ref('stg_initiatives') }}
WHERE start_year >= end_year