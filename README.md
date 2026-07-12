# SWEEP TECHNICAL HOME ASSESSMENT

## How to launch and view results

## Repository structure and technical stack choices

## Data quality handling

Exploratory analysis has been conducted in the exploration.ipynb Jupyter notebook to assess the datasets' quality.

### 1. companies.csv
- No duplicates on the company_id grain. Each company is unique.
- No null or outlier values detected across the entire set of columns.
- Data types are correct: company_id, company_name, sector, country as string, base_year as integer.
- 8 companies covering 5 countries (Germany, France, Netherlands, Spain, United Kingdom) and 5 sectors (Industrial manufacturing, Food & beverage, Transport & logistics, Retail, Technology).
- The base_year field is uniformly 2019 for all companies, which is consistent with the target_trajectory data.

### 2. emissions.csv

- Data types are correct: year and scope as int64, emissions_tco2e as float64, the rest as string.
- No orphan emissions. All company_id values present in emissions.csv exist in companies.csv.
- The 3 expected scopes (1, 2, 3) are all represented in the dataset.
- 470 out of 478 rows have a non-null value for emissions_tco2e. 98% of the dataset is therefore usable.

| Issue | Rows | Details | Handling |
|---|---|---|---|
| Duplicates | 16 | Records exactly 8 duplicated pairs on the grain key `company_id × year × scope × category`. | Deduplicated in staging via `ROW_NUMBER()`, first occurrence kept. |
| Null values in `emissions_tco2e` | 8 | Missing value for emissions, including the duplicate pair (CO-05 \| 2024 \| scope 3 \| Purchased goods & services). | Kept in staging with a `is_null_emission = TRUE` flag. Excluded from analytical calculations in the marts. |
| Outlier year | 1 | CO-07 \| 2099 \| scope 2 \| Purchased electricity \| 9000 tCO2e. Clearly incorrect year, likely a data entry error. The correct value cannot be inferred. | Kept in staging with a `is_invalid_year = TRUE` flag. Excluded from analytical calculations in the marts. |
| Invalid scope | 1 | CO-08 \| 2023 \| scope 4 \| Other \| 5000 tCO2e — scope 4 does not exist in the GHG Protocol standard (accepted values: 1, 2, 3). | Kept in staging with a `is_invalid_scope = TRUE` flag. Excluded from analytical calculations in the marts. |
| Negative emissions | 3 | CO-01 \| 2020 \| scope 3 \| Purchased goods & services \| -119 027 tCO2e<br>CO-07 \| 2024 \| scope 3 \| Upstream transport \| -183 411 tCO2e<br>CO-04 \| 2021 \| scope 1 \| Stationary combustion \| -2 039 tCO2e<br> It might be typos or valid values depending on business rules. | Flagged with `is_negative_emission = TRUE`. |
| Mixed units — kgCO2e vs tCO2e | 4 | Rows expressed in kgCO2e instead of tCO2e, producing seemingly aberrant values (up to 207 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN emissions_tco2e / 1000 ELSE emissions_tco2e END`. |

### 3. target_trajectory.csv

- No duplicates on the target_id × year grain. The composite key is indeed unique.
- All SBTi validated targets have a reduction rate above or equal to 42%.
- Only one method used ("-% per year (linear)"), the trajectory is linear as expected.
- No unit issue here, only tCO2e.

### 4. initiatives.csv

- All initiatives have a status value equal to planned, in_progress, or completed, and a group_type value equal to standard, bottom_up_group, or bottom_up_child.
- All initiatives have an end date later than the start date.
- All initiatives have a company_id value that exists in companies.csv
- Out of 45 initiatives in total,
42 have a group_type value equal to standard or bottom_up_group = no parent = NULL
3 are initiatives with a group_type equal to bottom_up_child = a parent = not NULL
All 3 bottom_up_child initiatives have a parent_group_id. Specifically, group GRP-01 (bottom_up_group) aggregates 3 child initiatives whose sum of estimated_reduction matches the group's value (9,793 tCO2e). In accordance with the instructions, only the children (bottom_up_child) and standard initiatives are included in the total reduction calculations to avoid double counting.

| Issue | Rows | Details | Handling |
|---|---|---|---|
| Duplicates | 6 | 3 pairs of duplicates are exact across all columns (which includes initiative_id grain):<br>INI-0013 \| Fleet electrification \| 988.9 tCO2e<br>INI-0035 \| Energy efficiency \| 4,609,800 kgCO2e<br>INI-0036 \| Supplier engagement \| 6,303,600 kgCO2e | Deduplicated via `ROW_NUMBER()`, same as for emissions. |
| Mixed units — kgCO2e vs tCO2e | 5 | Rows expressed in kgCO2e instead of tCO2e, producing seemingly aberrant values (up to 21 million). After conversion (/1000), these values are consistent with the rest of the dataset. | Normalized to tCO2e in staging via `CASE WHEN unit = 'kgCO2e' THEN estimated_reduction / 1000 ELSE estimated_reduction END`. |
| Invalid target_id — TGT-999 | 1 | INI-0041 \| CO-04 \| TGT-999. This initiative references a target_id that does not exist in target_trajectory — it's an orphan initiative that cannot be linked to a reduction target. | Kept in staging with a flag `is_orphan = TRUE`, excluded from target-progress calculations. |

## Model choices

## Assumptions and tradeoffs

- Negative CO2 emissions may exist in certain contexts (carbon sequestration, accounting corrections). Without business validation, emissions_tco2e negative values are kept.

- In target_trajectory.csv, all reduction targets only cover Scope 1+2. Scope 3 which is often the most significant, representing up to 90% of emissions for some companies, is never included in the reduction commitments. This constitutes a major limitation in interpreting progress toward targets.
