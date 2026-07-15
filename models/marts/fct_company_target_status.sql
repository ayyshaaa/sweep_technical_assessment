-- Grain : target_id x year
-- Combines target trajectory with actual emissions and initiative contributions
-- Scope coverage : Scope 1+2 → filter scope IN (1, 2)

WITH targets AS (
    -- Excluding orphan targets (target references a company_id absent from stg_companies)
    SELECT * FROM {{ ref('stg_target_trajectory') }}
    WHERE is_orphan_company = FALSE
),

companies AS (
    SELECT * FROM {{ ref('stg_companies') }}
),

-- Actual emissions aggregate according to target scope_coverage (all targets are Scope 1+2 in this dataset)
-- Excluding invalid data flagged in staging
actual_emissions AS (
    SELECT
        company_id,
        year,
        SUM(emissions_tco2e) AS actual_emissions_tco2e
    FROM {{ ref('stg_emissions') }}
    WHERE scope IN (1, 2)
      AND is_invalid_year = FALSE
      AND is_invalid_scope = FALSE
      AND is_null_emission = FALSE
    GROUP BY company_id, year
),

-- Latest year with reported (valid) actual emissions, used to distinguish forward-looking trajectory points (no actuals yet) from actual reporting gaps
latest_reported_year AS (
    SELECT MAX(year) AS max_year
    FROM {{ ref('stg_emissions') }}
    WHERE is_invalid_year = FALSE
),

-- Reduction sum per target
-- Excluding bottom_up_group to avoid double counting (bottom_up_group initiatives are already included in their parent group)
-- Excluding orphan initiatives
initiative_contributions AS (
    SELECT
        target_id,
        SUM(estimated_reduction) AS total_initiative_reduction
    FROM {{ ref('stg_initiatives') }}
    WHERE group_type != 'bottom_up_group'
      AND is_orphan_target = FALSE
    GROUP BY target_id
),

final AS (
    SELECT
        -- Identifiers
        t.target_id,
        t.company_id,
        c.company_name,
        c.sector,
        c.country,

        -- Scope and reduction method
        t.scope_coverage,
        t.method,
        t.sbti_validated,
        t.reduction_pct,

        -- Temporal
        t.baseline_year,
        t.target_year,
        t.year,

        -- Expected trajectory
        t.expected_emissions_tco2e,

        -- Actual emissions
        a.actual_emissions_tco2e,

        -- Gap : positive = running late, negative = ahead of schedule
        a.actual_emissions_tco2e - t.expected_emissions_tco2e  AS gap_tco2e,

        -- On track if actual emissions <= expected trajectory
        CASE
            WHEN a.actual_emissions_tco2e <= t.expected_emissions_tco2e
            THEN TRUE ELSE FALSE
        END                                                     AS is_on_track,

        -- Initiative contributions
        COALESCE(i.total_initiative_reduction, 0)              AS total_initiative_reduction,

        t.unit,

        -- TRUE if actual emissions could exist for this year (year is within the reported window).
        -- FALSE for forward-looking trajectory points beyond the latest reported emissions year.
        t.year <= r.max_year                                    AS has_reported_actuals

    FROM targets t
    LEFT JOIN companies c
        ON t.company_id = c.company_id
    LEFT JOIN actual_emissions a
        ON t.company_id = a.company_id
        AND t.year = a.year
    LEFT JOIN initiative_contributions i
        ON t.target_id = i.target_id
    CROSS JOIN latest_reported_year r
)

SELECT * FROM final