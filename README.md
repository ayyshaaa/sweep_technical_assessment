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
- `docs` — generates and serves the dbt documentation site (`dbt docs generate` && `dbt docs serve`), browsable at `http://localhost:8080` to explore the DAG, model definitions, and tests.

Each step can also be run individually, e.g. `make seed` or `make run`.

Data is materialized in a local DuckDB file (`dev.duckdb`, per `profiles.yml`/`~/.dbt/profiles.yml`), which can be queried directly if needed.

### 3. View the results

```bash
./venv/bin/jupyter notebook analysis.ipynb
```

The `analysis.ipynb` notebook is the deliverable for results: it connects to the DuckDB database populated by `make all` and contains the final charts and figures. Once the models have been built, launch it with:

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
**Structure** — inspecting column names, data types inferred by pandas, and memory usage via `.info()` and `.head()`.
**Completeness** — identifying null values per column with `.isnull().sum()`, and duplicate rows on the grain of each table with `.duplicated()` (full-row, then `subset=[...]` on the business key).
**Validity** — using `.describe()` to spot out-of-range numerical values and `.value_counts()` to catch invalid or inconsistent categorical values.
**Consistency** — checking referential integrity between tables with `.isin()`, and cross-row consistency within a table via `groupby().agg()` (e.g. each target's first/last reported `year` against its `baseline_year`/`target_year`)
**Business rules** — verifying domain-specific constraints with a mix of boolean filtering and `groupby()`: scope values restricted to {1, 2, 3}, SBTi-validated targets meeting the ≥42% reduction threshold, parent/child initiative sums (`bottom_up_group` vs its `bottom_up_child` rows) reconciling, and trajectory year-continuity checked with a custom `groupby().apply()` function that diffs the observed years against the expected full range.


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
| Outlier year | 1 | CO-07 \| 2099 \| scope 2 \| Purchased electricity \| 9000 tCO2e. Clearly incorrect year, most likely a data entry error. The correct value cannot be inferred. | Kept in staging with a `is_invalid_year = TRUE` flag. Excluded from analytical calculations in the marts. |
| Invalid scope | 1 | CO-08 \| 2023 \| scope 4 \| Other \| 5000 tCO2e — scope 4 does not exist in the GHG Protocol standard (accepted values: 1, 2, 3). | Kept in staging with a `is_invalid_scope = TRUE` flag. Excluded from analytical calculations in the marts. |
| Negative emissions | 3 | CO-01 \| 2020 \| scope 3 \| Purchased goods & services \| -119 027 tCO2e<br>CO-07 \| 2024 \| scope 3 \| Upstream transport \| -183 411 tCO2e<br>CO-04 \| 2021 \| scope 1 \| Stationary combustion \| -2 039 tCO2e<br> It might be typos or valid values depending on business rules. | Flagged with `is_negative_emission = TRUE`. |
| Mixed units — kgCO2e vs tCO2e | 4 | Rows expressed in kgCO2e instead of tCO2e, producing strikingly high values (up to 207 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN emissions_tco2e / 1000 ELSE emissions_tco2e END`. |

### 3. target_trajectory.csv

- No duplicates on the `target_id × year grain`. The composite key is indeed unique.
- For every target, first `year` report fits `baseline_year` and there's no year gap.
- All SBTi validated targets have a reduction rate above or equal to 42%.
- Only one method used ("-% per year (linear)"); the trajectory is linear as expected.
- No `unit` issue here, only tCO2e.

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
| Mixed units — kgCO2e vs tCO2e | 5 | Rows expressed in kgCO2e instead of tCO2e, producing strikingly high values (up to 21 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN estimated_reduction / 1000 ELSE estimated_reduction END`. |
| Invalid target_id — TGT-999 | 1 | INI-0041 \| CO-04 \| TGT-999. This initiative references a `target_id` which does not exist in target_trajectory table. It's an orphan initiative that cannot be linked to a reduction target. I kept in staging with a flag `is_orphan = TRUE`, excluded from target-progress calculations. |

## Model choices

### Layers organisation choice

The project follows a standard dbt layered architecture (staging → marts) for several reasons:
**Separation of concerns** each layer has a single, well-defined responsibility. The staging layer handles data quality, typing, and normalization. The marts layer handles business logic and analytical aggregations. Mixing the two would make models harder to maintain and debug.
**Non-destructive approach** raw data is never modified. Issues are flagged in the staging layer rather than deleted, so the original data is always recoverable and auditable. Filtering decisions are deferred to the marts layer where the analytical context is clear.
**Reusability** staging models are built once and referenced by multiple mart models via `ref()`. If the business logic of a mart changes, the staging layer remains untouched. If a source changes, only the corresponding staging model needs to be updated.
**Testability** separating layers makes it easier to pinpoint where a data quality issue originates. A test failure in staging points to a source problem; a test failure in marts points to a transformation problem.
**Transparency** the DAG generated by dbt makes dependencies between models explicit and visible, which helps any team member understand how data flows from raw sources to analytical outputs.

### 1. Staging layer

- companies staging model
Since the source is clean already, I will only cast and rename attributes. Data types are automatically inferred from the seeded table however it might fail depending on the choosen database. Explicit cast ensures type is exactly what I want, regardless of the choosen database.
I'm conducting simple checks regarding `company_id` primary key unicity, not null or invalid values for each attributes to look out for edge cases.

- target_trajectory staging model


### 2. Mart layer

## Assumptions and tradeoffs

- Negative CO2 emissions may exist in certain contexts (carbon sequestration, accounting corrections). Without business validation, emissions source `emissions_tco2e` negative values are kept.
- The expected reduction trajectory is assumed to be strictly decreasing from one year to the next, consistent with the -% per year (linear) method observed in the dataset.

(In target_trajectory.csv, all reduction targets only cover Scope 1+2. Scope 3 which is often the most significant, representing up to 90% of emissions for some companies, is never included in the reduction commitments. This constitutes a major limitation in interpreting progress toward targets.)
