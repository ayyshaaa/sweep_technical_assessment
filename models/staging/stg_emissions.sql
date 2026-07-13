-- Grain : company_id × year × scope × category
-- Source : emissions
-- Data quality issues handled:
--   - kgCO2e to tCO2e conversion
--   - Deduplication on grain
--   - Flags: is_null_emission, is_negative_emission, is_invalid_year, is_invalid_scope

WITH source AS (
    SELECT * FROM {{ source('raw', 'emissions') }}
),

normalized AS (
    SELECT
        -- Identifiers
        CAST(company_id AS VARCHAR)                 AS company_id,
        CAST(year AS INTEGER)                       AS year,
        CAST(scope AS INTEGER)                      AS scope,
        CAST(LOWER(TRIM(category)) AS VARCHAR)      AS category,

        -- Unit normalisation kgCO2e to tCO2e
        CASE
            WHEN unit = 'kgCO2e'
            THEN CAST(emissions_tco2e / 1000 AS FLOAT)
            ELSE CAST(emissions_tco2e AS FLOAT)
        END                                         AS emissions_tco2e,

        -- Normalized unit
        'tCO2e'                                     AS unit,

        -- Data quality flags
        CASE
            WHEN emissions_tco2e IS NULL
            THEN TRUE ELSE FALSE
        END                                         AS is_null_emission,

        CASE
            WHEN emissions_tco2e < 0
            THEN TRUE ELSE FALSE
        END                                         AS is_negative_emission,

		CASE
		    WHEN year > YEAR(CURRENT_DATE)
		    THEN TRUE ELSE FALSE
		END 										AS is_invalid_year,

        CASE
            WHEN scope NOT IN (1, 2, 3)
            THEN TRUE ELSE FALSE
        END                                         AS is_invalid_scope

    FROM source
),

deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY company_id, year, scope, category
            ORDER BY emissions_tco2e DESC NULLS LAST
        ) AS rn
    FROM normalized
)

SELECT * EXCLUDE (rn)
FROM deduplicated
WHERE rn = 1