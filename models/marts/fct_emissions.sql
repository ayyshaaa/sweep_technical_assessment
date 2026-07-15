-- Grain : company_id x year x scope x category
-- Combines stg_emissions with stg_companies for enrichment
-- Filters out invalid data flagged in staging

WITH emissions AS (
    SELECT * FROM {{ ref('stg_emissions') }}
    WHERE is_invalid_year = FALSE
      AND is_invalid_scope = FALSE
      AND is_null_emission = FALSE
),

companies AS (
    SELECT * FROM {{ ref('stg_companies') }}
),

final AS (
    SELECT
        -- Identifiers
        e.company_id,
        c.company_name,
        c.sector,
        c.country,
        c.base_year,

        -- Temporal
        e.year,
        e.year - c.base_year                   AS years_since_baseline,

        -- Emissions
        e.scope,
        e.category,
        e.emissions_tco2e,
        e.unit,

        -- Flags
        e.is_negative_emission

    FROM emissions e
    LEFT JOIN companies c
        ON e.company_id = c.company_id
)

SELECT * FROM final