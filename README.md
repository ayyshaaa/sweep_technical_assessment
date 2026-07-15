# SWEEP TECHNICAL HOME ASSESSMENT

## How to launch data processing and view results

The project is orchestrated through the `Makefile`, which wraps a Python virtual environment and the dbt CLI (dbt-duckdb adapter, DuckDB as the local database).

### 1. Setup

After git cloning the repository,

```bash
cd sweep_technical_assessment # navigate in the folder
make setup
```

It creates a `venv/` virtual environment and installs the dependencies listed in `requirements.txt` (dbt-core, dbt-duckdb, duckdb, jupyter, pandas, matplotlib, seaborn).

### 2. Build everything

```bash
make all
```

This chains the following targets:
- `deps` — installs dbt package dependencies (`dbt deps`).
- `seed` — loads the CSV files from `seeds/` into DuckDB (`dbt seed`).
- `run` — builds and tests the staging models, then the marts models, in order (`dbt run --select staging`, `dbt test --select staging`, `dbt run --select marts`, `dbt test --select marts`). Running staging tests before marts makes it easy to pinpoint whether a failure comes from a source/transformation issue (staging) or a business-logic issue (marts).
- `notebook` — re-executes `analysis.ipynb` end-to-end with a fresh kernel (`jupyter nbconvert --to notebook --execute --inplace`), updating its outputs in place.
- `docs` — generates and serves the dbt documentation site (`dbt docs generate` && `dbt docs serve --port 8081`), browsable at `http://localhost:8081` to explore the DAG, model definitions, and tests.

> `docs` runs last because `dbt docs serve` blocks the terminal (it runs a local server) — stop it with Ctrl+C once you're done browsing the docs.

Each step can also be run individually, e.g. `make seed` or `make run`.

Data is materialized in a local DuckDB file (`dev.duckdb`, per `profiles.yml`/`~/.dbt/profiles.yml`), which can be queried directly if needed.

### 3. View the results

The `analysis.ipynb` notebook is the deliverable for results: it connects to the DuckDB database populated by `make all` and contains the final charts and figures.

```bash
make notebook          # re-run the notebook headlessly and refresh its saved outputs
make reload-notebook   # same, plus a `seed` + `run` refresh of dev.duckdb beforehand (to use **after the source data or models have been changed**)
```

To browse or edit it interactively instead:

```bash
./venv/bin/jupyter notebook analysis.ipynb
```

### 4. Tests only / cleanup

```bash
make test   # re-run all dbt tests without rebuilding
make clean  # remove dbt artifacts and the venv
```

## Technical stack choices

**dbt Core** was chosen over dbt Cloud to avoid cloud infrastructure setup overhead, keeping the focus on data modeling and analytical quality rather than configuration. The modeling logic is identical to what would run on dbt Cloud with Snowflake in production.

**DuckDB** was chosen as the database backend instead of Snowflake for the following reasons:
- No account or cloud setup is required. The database runs entirely in-process
- Native support for reading CSV files directly, making `dbt seed` straightforward
- Full SQL compatibility including window functions, CTEs, and all features used in this project
- The dbt-duckdb adapter is officially maintained by dbt Labs, ensuring compatibility
The transformation logic written for DuckDB is fully portable to Snowflake. You will need to change the connection profile in `~/.dbt/profiles.yml` though.

**Jupyter Notebook** was used for the exploratory analysis and the analytical questions rather than a BI tool like Metabase, as it allows combining code, outputs, and narrative in a single document that is easy to review.

**Python + pandas** was used for initial exploration and further analysis only. All transformations are handled in SQL via dbt.

**Git + GitHub** for version control, with a `.gitignore` excluding all generated artifacts (`target/`, `dbt_packages/`, `venv/`, `.ipynb_checkpoints/`) to keep the repository clean and reproducible.

## Data quality handling

Earlier-stage, exploratory analysis has been conducted in the `exploration.ipynb` Jupyter notebook to assess the datasets' quality.
The exploration followed an iterative approach, going from general to specific as the understanding of the domain deepened:

**Structure** inspecting column names, data types inferred by pandas, and memory usage via `.info()` and `.head()`.

**Completeness** identifying null values per column with `.isnull().sum()`, and duplicate rows on the grain of each table with `.duplicated()` (full-row, then `subset=[...]` on the business key).

**Validity** using `.describe()` to spot out-of-range numerical values and `.value_counts()` to catch invalid or inconsistent categorical values.

**Consistency** checking referential integrity between tables with `.isin()`, and cross-row consistency within a table via `groupby().agg()` (e.g. each target's first/last reported `year` against its `baseline_year`/`target_year`).

**Business rules** verifying domain-specific constraints with a mix of boolean filtering and `groupby()`: scope values restricted to {1, 2, 3}, SBTi-validated targets meeting the ≥42% reduction threshold, parent/child initiative sums (`bottom_up_group` vs its `bottom_up_child` rows) reconciling, and trajectory year-continuity checked with a custom `groupby().apply()` function that diffs the observed years against the expected full range.

### 1. companies.csv
- No duplicates on the `company_id` grain. Each company is unique.
- No null or outlier values detected across the entire set of columns.
- Data types are correct: `company_id`, `company_name`, `sector`, `country` as string, `base_year` as integer.
- 8 companies covering 5 countries (Germany, France, Netherlands, Spain, United Kingdom) and 5 sectors (Industrial manufacturing, Food & beverage, Transport & logistics, Retail, Technology).
- The `base_year` field is uniformly 2019 for all companies, which is consistent with the target_trajectory data.

### 2. emissions.csv

- Data types are correct: `year` and `scope` as int64, `emissions_tco2e` as float64, the rest as string.
- No orphan emissions. All company_id values present in emissions.csv exist in companies.csv.
- The 3 expected scopes (1, 2, 3) are all represented in the dataset.
- 470 out of 478 rows have a non-null value for `emissions_tco2e`. 98% of the dataset is therefore usable.

| Issue | Rows | Details | Handling |
|---|---|---|---|
| Duplicates | 16 | Records exactly 8 duplicated pairs on the grain key `company_id × year × scope × category`. | Deduplicated in staging via `ROW_NUMBER()`, first occurrence kept. |
| Null values in `emissions_tco2e` | 8 | Missing value for emissions, including the duplicate pair (CO-05 \| 2024 \| scope 3 \| Purchased goods & services). | Kept in staging with a `is_null_emission = TRUE` flag. Excluded from analytical calculations in the marts. |
| Outlier year | 1 | CO-07 \| 2099 \| scope 2 \| Purchased electricity \| 9000 tCO2e<br> Clearly incorrect year, most likely a data entry error. The correct value cannot be inferred. | Kept in staging with a `is_invalid_year = TRUE` flag. Excluded from analytical calculations in the marts. |
| Invalid scope | 1 | CO-08 \| 2023 \| scope 4 \| Other \| 5000 tCO2e<br> Scope 4 does not exist in the GHG Protocol standard (accepted values: 1, 2, 3). | Kept in staging with a `is_invalid_scope = TRUE` flag. Excluded from analytical calculations in the marts. |
| Negative emissions | 3 | CO-01 \| 2020 \| scope 3 \| Purchased goods & services \| -119 027 tCO2e<br>CO-07 \| 2024 \| scope 3 \| Upstream transport \| -183 411 tCO2e<br>CO-04 \| 2021 \| scope 1 \| Stationary combustion \| -2 039 tCO2e<br> It might be typos or valid values depending on business rules. | Flagged with `is_negative_emission = TRUE`. |
| Mixed units (kgCO2e vs tCO2e) | 4 | Rows expressed in kgCO2e instead of tCO2e, producing strikingly high values (up to 207 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN emissions_tco2e / 1000 ELSE emissions_tco2e END`. |
| Inconsistent category naming (`electricity`) | 1 | CO-08 used `electricity` in 2022 only, while using `purchased electricity` for all other years — confirming a data entry error rather than a distinct category. | Standardized to `purchased electricity` (Scope 2) in staging. |
| Inconsistent category naming (`travel`) | 2 | CO-02 used `travel` in 2023 only (vs `business travel` in 2021, 2022, 2024). CO-03 used `travel` in 2024 only (vs `business travel` in 2019, 2021, 2023). Both confirm a data entry error rather than a distinct category. | Standardized to `business travel` (Scope 3) in staging. |



### 3. target_trajectory.csv

- No duplicates on the `target_id × year grain`. The composite key is indeed unique.
- For every target, first `year` report fits `baseline_year` and there's no year gap.
- All SBTi validated targets have a reduction rate above or equal to 42%.
- Only one method used ("-% per year (linear)"); the trajectory is linear as expected.
- No `unit` issue here, only tCO2e.

| Issue | Rows | Details | Handling |
|---|---|---|---|
| Invalid company_id (CO-999) | 12 | TGT-900 \| CO-999 \| Scope 1+2 \| target_year 2030<br> A full 12-point trajectory (2019 - 2030) is reported for a `company_id` which does not exist in companies.csv. It's an orphan target that cannot be linked to a company. | Kept in staging with a `is_orphan_company = TRUE` flag. Excluded from company-level rollups in the marts. |

### 4. initiatives.csv

- All initiatives have a `status` value equal to planned, in_progress, or completed, and a `group_type` value equal to standard, bottom_up_group, or bottom_up_child.
- All initiatives have an `end_year` higher than the `start_year`.
- All initiatives have a `company_id` value that exists in companies.csv
- Out of 45 initiatives in total,
42 have a `group_type` value equal to standard or bottom_up_group = no parent = NULL
3 are initiatives with a `group_type` equal to bottom_up_child = parent = not NULL
All 3 bottom_up_child initiatives have a not null `parent_group_id`. Specifically, group GRP-01 (bottom_up_group) aggregates 3 child initiatives whose sum of `estimated_reduction` matches the group's value (9,793 tCO2e). In accordance with the instructions, only the children (bottom_up_child) and standard initiatives are included in the total reduction calculations to avoid double counting.

| Issue | Rows | Details | Handling |
|---|---|---|---|
| Duplicates | 6 | 3 pairs of duplicates are exact across all columns (which includes `initiative_id` grain):<br>INI-0013 \| Fleet electrification \| 988.9 tCO2e<br>INI-0035 \| Energy efficiency \| 4,609,800 kgCO2e<br>INI-0036 \| Supplier engagement \| 6,303,600 kgCO2e | Deduplicated via `ROW_NUMBER()`, same as for emissions. |
| Mixed units (kgCO2e vs tCO2e) | 5 | Rows expressed in kgCO2e instead of tCO2e, producing strikingly high values (up to 21 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN estimated_reduction / 1000 ELSE estimated_reduction END`. |
| Invalid target_id (TGT-999) | 1 | INI-0041 \| CO-04 \| TGT-999<br> This initiative references a `target_id` which does not exist in target_trajectory table. It's an orphan initiative that cannot be linked to a reduction target. I kept in staging with a flag `is_orphan_target = TRUE`, excluded from target-progress calculations. |

## Model choices

### Layers organisation choice

The project follows a standard dbt layered architecture (staging → marts) for several reasons:

**Separation of concerns** each layer has a single, well-defined responsibility. The staging layer handles data quality, typing, and normalization. The marts layer handles business logic and analytical aggregations. Mixing the two would make models harder to maintain and debug.

**Non-destructive approach** raw data is never modified. Issues are flagged in the staging layer rather than deleted, so the original data is always recoverable and auditable. Filtering decisions are deferred to the marts layer where the analytical context is clear.

**Reusability** staging models are built once and referenced by multiple mart models via `ref()`. If the business logic of a mart changes, the staging layer remains untouched. If a source changes, only the corresponding staging model needs to be updated.

**Testability** separating layers makes it easier to pinpoint where a data quality issue originates. A test failure in staging points to a source problem; a test failure in marts points to a transformation problem.

**Transparency** the DAG generated by dbt makes dependencies between models explicit and visible, which helps any team member understand how data flows from raw sources to analytical outputs.

### 1. Staging layer

#### companies staging model (`stg_companies.sql`)

| Model justification | Tests justification |
|---|---|
| The source is already clean, so the transformation is limited to casting and renaming: dbt/DuckDB infers types from the seeded CSV, but that inference can vary depending on the target database, so an explicit `CAST` guarantees the exact type regardless of which warehouse sits behind the adapter. | Tests stay proportionate to the risk: `unique` + `not_null` on `company_id` enforce the primary key, and the same pair on `company_name` catches an unexpected homonym or a duplicated seed row. `string_length` is applied to every string column as a defensive floor/ceiling against empty strings or abnormally long values due to a badly parsed CSV row. `sector` and `country` only get `not_null` — with just 8 companies, an `accepted_values` list would be brittle and not worth maintaining as new companies are onboarded. `base_year` gets `not_null` plus `dbt_utils.accepted_range` bounded to [2019, 2050], consistent with the years observed in `target_trajectory`. It's a sanity check rather than a strict business rule. |

#### emissions staging model (`stg_emissions.sql`)

| Model justification | Tests justification |
|---|---|
| This is the most complex source, so the staging layer does more than casting: `category` is lowercased and trimmed to avoid case-sensitivity duplicates downstream, and inconsistent labels (`electricity` → `purchased electricity`, `travel` → `business travel`) are standardized to their canonical form. Moreover `emissions_tco2e` values recorded in kgCO2e are converted to tCO2e via `CASE WHEN unit = 'kgCO2e'` so the whole column ends up expressed in a single unit. Exact duplicates on the grain (`company_id × year × scope × category`) are removed with a `ROW_NUMBER()` window ordered by `emissions_tco2e DESC NULLS LAST`, so that when a duplicate pair has one null and one populated value, the populated one is the row kept rather than an arbitrary one. All other quality issues (null emissions, negative emissions, invalid year, invalid scope) are not filtered out here: they are flagged with boolean columns (`is_null_emission`, `is_negative_emission`, `is_invalid_year`, `is_invalid_scope`) so the row survives to staging and the exclusion decision is made explicitly in the marts layer, where the analytical context is clear. | `dbt_utils.unique_combination_of_columns` on the grain confirms the deduplication actually worked. `relationships` checks `company_id` against `stg_companies` to catch referential-integrity issues early. `accepted_values` on `scope` and the conditional `not_null` on `emissions_tco2e` are both scoped with a `where: is_invalid_scope = false` / `where: is_null_emission = false` clause. It lets the known bad row pass without failing the whole test suite, while still catching any *new*, unflagged bad row a future source refresh might introduce. Each `is_*` flag is itself tested with `accepted_values: [true, false]` as a basic boolean sanity check. |

#### target_trajectory staging model (`stg_target_trajectory.sql`)

| Model justification | Tests justification |
|---|---|
| The source is already fairly clean, so like `companies`, the transformation is mostly casting and renaming. The one addition is `is_orphan_company`, computed with a `NOT IN` subquery against the `companies` **source** rather than `ref('stg_companies')`. Indeed staging models are kept independent from one another and only depend on sources, so the DAG stays flat and each staging model can be built or tested in isolation. | Tests mirror the exploration findings: `dbt_utils.unique_combination_of_columns` on `target_id × year` confirms the grain, and `relationships` on `company_id` is scoped with `where: is_orphan_company = false` to tolerate the one known orphan (`CO-999`) while still catching any unexpected one. `dbt_utils.accepted_range` bounds `reduction_pct` to [0, 1] and `expected_emissions_tco2e` to non-negative values. Unlike `emissions_tco2e` in the emissions model, no flag was introduced for negative planned emissions, since a negative *target* trajectory value has no plausible business meaning and should hard-fail rather than be silently tolerated. `accepted_values` on `scope_coverage` locks down the set of scope combinations observed during exploration, and on `sbti_validated` as a boolean check. |

#### initiatives staging model (`stg_initiatives.sql`)

| Model justification | Tests justification |
|---|---|
| Same treatment as `emissions`: unit normalization (kgCO2e to tCO2e) and deduplication on the grain (`initiative_id`) via `ROW_NUMBER()` ordered by `estimated_reduction DESC NULLS LAST`. The only flag introduced is `is_orphan_target`, computed against the `target_trajectory` **source** directly, for the same reason as above, that is no cross-dependency between staging models. | Tests enforce `unique` + `not_null` on `initiative_id` (the grain), and `relationships` on both `company_id` (strict, since no orphan company was found in this table during exploration) and `target_id` (scoped with `where: is_orphan_target = false`, to tolerate the known `TGT-999` orphan). `accepted_values` locks `group_type` to `{standard, bottom_up_group, bottom_up_child}` and `status` to `{planned, in_progress, completed}`, since both are business-critical categorical fields used later to decide inclusion in the reduction totals. `dbt_utils.accepted_range` enforces non-negative values on `estimated_reduction`, for the same reason as `expected_emissions_tco2e` in target_trajectory: an estimated *future* reduction being negative would be a data error, not a legitimate business case. Note that `parent_group_id` carries no test — it's nullable by design (only `bottom_up_child` rows populate it), and the parent/child reconciliation (sum of children = group value) is a cross-row business rule verified during exploration rather than one easily expressed as a generic dbt test. |

### 2. Mart layer

#### emissions mart model (`fct_emissions.sql`)

This mart provides a clean, company-enriched view of the raw emissions data, intended as the base table for footprint analysis (by company, sector, scope, category, or trend over time).

It joins two staging models:
- **`stg_emissions`** provides the measured emissions per company, year, scope, and category, already normalized to tCO2e in staging
- **`stg_companies`** enriches the result with company attributes (name, sector, country, base_year)

Three of the data-quality flags raised in `stg_emissions` are filtered out here (`is_invalid_year = FALSE`, `is_invalid_scope = FALSE`, `is_null_emission = FALSE`), consistent with the staging/marts split described above: staging flags, marts decides. `is_negative_emission` is deliberately **not** filtered out. I wanted negative values kept in the table (and exposed as a flag) since they may be legitimate.

The grain is `company_id x year x scope x category` that is one row per reported emission line, unchanged from the source grain. The key computed column is:

- **`years_since_baseline`** = `year - base_year`, letting emissions trajectories be compared across companies on a common time axis relative to their own baseline (though in this dataset `base_year` is uniformly 2019 for every company).

#### company_target_status mart model (`fct_company_target_status.sql`)

This mart is purposedly built to check whether companies are on track to meet their reduction targets.

It joins four staging models:
- **`stg_target_trajectory`** provides the expected emissions trajectory year by year for each target
- **`stg_emissions`** provides actual measured emissions, filtered and aggregated to match the `scope_coverage` of each target (`scope IN (1, 2)`), excluding invalid data flagged in staging.
- **`stg_companies`** enriches the result with company attributes (name, sector, country)
- **`stg_initiatives`** provides the total estimated reduction from all active initiatives linked to each target, with two exclusion rules applied:
  - `bottom_up_group` rows are excluded to avoid double counting with their `bottom_up_child` initiatives
  - Orphan initiatives (linked to non-existent targets like `TGT-999`) are excluded

The grain is `target_id x year` — one row per target per trajectory year. The key computed columns are:

- **`actual_emissions_tco2e`** — actual Scope 1+2 emissions for that company and year
- **`gap_tco2e`** — difference between actual and expected emissions. A positive gap means the company is emitting more than planned (behind schedule). A negative gap means it is ahead of schedule.
- **`is_on_track`** — boolean flag, TRUE if `actual_emissions_tco2e <= expected_emissions_tco2e`
- **`total_initiative_reduction`** — cumulative estimated reduction from all valid initiatives, providing context on whether the planned effort is sufficient to close the gap

Note: All targets in the dataset have a `scope_coverage` of `Scope 1+2`. Therefore, actual emissions in `fct_company_target_status` are filtered to `scope IN (1, 2)` to match the target perimeter. This filter is hardcoded rather than dynamic, as no other scope coverage value appears in the dataset. If future data introduces targets with different scope coverages (e.g. `Scope 1+2+3`), the mart logic would need to be updated to handle this dynamically.


## Assumptions and tradeoffs

- Negative CO2 emissions may exist in certain contexts (carbon sequestration, accounting corrections). Without business validation, emissions source `emissions_tco2e` negative values are kept in tables but excluded from emissions calculations and analysis.
- The expected reduction trajectory is assumed to be strictly decreasing from one year to the next, consistent with the -% per year (linear) method observed in the dataset.
