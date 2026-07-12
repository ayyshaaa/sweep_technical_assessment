-- Grain : company_id (1 line per company)
-- Source : companies

WITH source AS (
    SELECT * FROM {{ source('raw', 'companies') }}
)

SELECT
    -- Identifiers
    CAST(company_id AS VARCHAR)    AS company_id,
    CAST(company_name AS VARCHAR)  AS company_name,

    -- Dimensions
    CAST(sector AS VARCHAR)        AS sector,
    CAST(country AS VARCHAR)       AS country,

    -- Temporal
    CAST(base_year AS INTEGER)     AS base_year

FROM source