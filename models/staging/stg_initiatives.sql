-- Grain : initiative_id
-- Source : initiatives
-- Data quality issues handled:
--   - kgCO2e to tCO2e conversion
--   - Deduplication on initiative_id
--   - Flags: is_orphan_target

WITH source AS (
    SELECT * FROM {{ source('raw', 'initiatives') }}
),

normalized AS (
    SELECT
        -- Identifiers
        CAST(initiative_id AS VARCHAR)              AS initiative_id,
        CAST(company_id AS VARCHAR)                 AS company_id,
        CAST(target_id AS VARCHAR)                  AS target_id,

        -- Descriptive
        CAST(initiative_name AS VARCHAR)            AS initiative_name,
        CAST(lever_category AS VARCHAR)             AS lever_category,
        CAST(group_type AS VARCHAR)                 AS group_type,
        CAST(parent_group_id AS VARCHAR)            AS parent_group_id,

        -- Temporal
        CAST(start_year AS INTEGER)                 AS start_year,
        CAST(end_year AS INTEGER)                   AS end_year,

        -- Status
        CAST(status AS VARCHAR)                     AS status,

        -- Unit normalisation kgCO2e to tCO2e
        CASE
            WHEN unit = 'kgCO2e'
            THEN CAST(estimated_reduction / 1000 AS FLOAT)
            ELSE CAST(estimated_reduction AS FLOAT)
        END                                         AS estimated_reduction,

        -- Normalized unit
        'tCO2e'                                     AS unit,

        -- Data quality flag
        CASE
            WHEN target_id NOT IN (
                SELECT DISTINCT target_id
                FROM {{ source('raw', 'target_trajectory') }}
            )
            THEN TRUE ELSE FALSE
        END                                         AS is_orphan_target

    FROM source
),

deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY initiative_id
            ORDER BY estimated_reduction DESC NULLS LAST
        ) AS rn
    FROM normalized
)

SELECT * EXCLUDE (rn)
FROM deduplicated
WHERE rn = 1