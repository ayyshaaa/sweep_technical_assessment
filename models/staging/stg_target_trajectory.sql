-- Grain : target_id x year (1 ligne per target and year of trajectory point)
-- Source : target_trajectory
-- Data quality issues handled:
--   - Flags: is_orphan_company

WITH source AS (
    SELECT * FROM {{ source('raw', 'target_trajectory') }}
)

SELECT
    -- Identifiers
    CAST(target_id AS VARCHAR)                      AS target_id,
    CAST(company_id AS VARCHAR)                     AS company_id,

    -- Target Scope
    CAST(scope_coverage AS VARCHAR)                 AS scope_coverage,
    CAST(method AS VARCHAR)                         AS method,
    CAST(sbti_validated AS BOOLEAN)                 AS sbti_validated,
    CAST(reduction_pct AS FLOAT)                    AS reduction_pct,

    -- Temporal
    CAST(baseline_year AS INTEGER)                  AS baseline_year,
    CAST(target_year AS INTEGER)                    AS target_year,
    CAST(year AS INTEGER)                           AS year,

    -- Metrics
    CAST(expected_emissions_tco2e AS FLOAT)         AS expected_emissions_tco2e,
    CAST(unit AS VARCHAR)                           AS unit,

    -- Data quality flag
    CASE
        WHEN company_id NOT IN (
            SELECT DISTINCT company_id
            FROM {{ source('raw', 'companies') }}
        )
        THEN TRUE ELSE FALSE
    END                                              AS is_orphan_company

FROM source