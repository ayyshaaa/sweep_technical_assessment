-- Grain : target_id × year (1 ligne per target and year of trajectory point)
-- Source : target_trajectory

WITH source AS (
    SELECT * FROM {{ source('raw', 'target_trajectory') }}
)

SELECT
    -- Identifiants
    CAST(target_id AS VARCHAR)                      AS target_id,
    CAST(company_id AS VARCHAR)                     AS company_id,

    -- Périmètre de la cible
    CAST(scope_coverage AS VARCHAR)                 AS scope_coverage,
    CAST(method AS VARCHAR)                         AS method,
    CAST(sbti_validated AS BOOLEAN)                 AS sbti_validated,
    CAST(reduction_pct AS FLOAT)                    AS reduction_pct,

    -- Temporel
    CAST(baseline_year AS INTEGER)                  AS baseline_year,
    CAST(target_year AS INTEGER)                    AS target_year,
    CAST(year AS INTEGER)                           AS year,

    -- Métriques
    CAST(expected_emissions_tco2e AS FLOAT)         AS expected_emissions_tco2e,
    CAST(unit AS VARCHAR)                           AS unit

FROM source